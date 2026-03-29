import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart' as classic;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:heart_03/utils/utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class DiscoveredDevice {
  final String name;
  final String address;
  final int rssi;
  final bool isBle;
  final dynamic device;

  DiscoveredDevice({
    required this.name,
    required this.address,
    required this.rssi,
    required this.isBle,
    required this.device,
  });
}

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ClientPage(title: 'Bluetooth Scanner'),
    );
  }
}

class ClientPage extends StatefulWidget {
  const ClientPage({super.key, required this.title});
  final String title;

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  classic.BluetoothConnection? _classicConnection;
  ble.BluetoothDevice? _bleDevice;
  String _receivedData = "";
  bool isConnecting = false;
  bool isDiscovering = false;
  bool hasSearched = false;
  String? connectedDeviceName;
  StreamSubscription? _bleDataSubscription;

  final Duration _discoveryTimeout = const Duration(seconds: 30);
  final String targetServiceUuid = 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7';
  final String _tag = "ClientPage";

  StreamSubscription<classic.BluetoothDiscoveryResult>? _classicSubscription;
  StreamSubscription<List<ble.ScanResult>>? _bleSubscription;
  Timer? _discoveryTimer;

  List<DiscoveredDevice> results = [];

  bool get isConnected => (_classicConnection?.isConnected ?? false) || (_bleDevice != null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissions());
  }

  // --- 1. Permission Logic ---
  Future<void> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      _showPermissionDialog();
    } else {
      _checkHardwareStatus();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Permissions Required"),
        content: const Text("You can't use the app if permission is not granted"),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _checkPermissions();
            },
            child: const Text("Agree"),
          ),
        ],
      ),
    );
  }

  Future<void> _checkHardwareStatus() async {
    classic.BluetoothState state = await classic.FlutterBluetoothSerial.instance.state;
    if (state == classic.BluetoothState.STATE_OFF) {
      await classic.FlutterBluetoothSerial.instance.requestEnable();
    }
    if (Platform.isAndroid) {
      bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationEnabled) {
        await Geolocator.openLocationSettings();
      }
    }
  }

  // --- 2. Scanning Logic ---
  void _startDiscovery() async {
    if (isDiscovering || isConnecting || isConnected) return;

    setState(() {
      isDiscovering = true;
      hasSearched = false;
      results.clear();
    });

    _discoveryTimer?.cancel();
    _discoveryTimer = Timer(_discoveryTimeout, () {
      _stopDiscovery();
      setState(() => hasSearched = true);
    });

    // Classic Discovery
    _classicSubscription = classic.FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
      _addDevice(DiscoveredDevice(
        name: r.device.name ?? "Unknown Classic",
        address: r.device.address,
        rssi: r.rssi,
        isBle: false,
        device: r.device,
      ));
    });

    // BLE Scan
    _bleSubscription = ble.FlutterBluePlus.onScanResults.listen((scanResults) {
      for (ble.ScanResult r in scanResults) {
        String name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : (r.device.platformName.isNotEmpty ? r.device.platformName : "Unknown BLE");

        _addDevice(DiscoveredDevice(
          name: name,
          address: r.device.remoteId.toString(),
          rssi: r.rssi,
          isBle: true,
          device: r.device,
        ));
      }
    });

    await ble.FlutterBluePlus.startScan(timeout: _discoveryTimeout);
  }

  void _addDevice(DiscoveredDevice device) {
    if (!mounted) return;
    setState(() {
      final idx = results.indexWhere((d) => d.address == device.address);
      if (idx >= 0) {
        results[idx] = device;
      } else {
        results.add(device);
      }
      results.sort((a, b) => b.rssi.compareTo(a.rssi));
    });
  }

  void _stopDiscovery() async {
    _classicSubscription?.cancel();
    _bleSubscription?.cancel();
    
    // Crucial: Stop BLE Scan
    await ble.FlutterBluePlus.stopScan().catchError((_) {});
    
    // Crucial: Stop Classic Discovery
    await classic.FlutterBluetoothSerial.instance.cancelDiscovery().catchError((_) {});
    
    _discoveryTimer?.cancel();
    if (mounted) setState(() => isDiscovering = false);
  }

  void _onDeviceTap(DiscoveredDevice d) {
    if (isConnecting || isConnected) return;
    _stopDiscovery();

    if (!d.isBle) {
      _connectToClassic(d.device as classic.BluetoothDevice);
    } else {
      _connectToBle(d.device as ble.BluetoothDevice);
    }
  }

  Future<void> _connectToClassic(classic.BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
      connectedDeviceName = device.name;
    });

    try {
      if (!device.isBonded) {
        bool? bonded = await classic.FlutterBluetoothSerial.instance.bondDeviceAtAddress(device.address);
        if (bonded != true) throw Exception("Bonding failed");
      }

      _classicConnection = await classic.BluetoothConnection.toAddress(device.address);

      _classicConnection!.input!.listen((data) {
        if (mounted) {
          setState(() {
            _receivedData += utf8.decode(data);
            if (_receivedData.length > 2000) _receivedData = _receivedData.substring(_receivedData.length - 2000);
          });
        }
      }).onDone(() {
        if (mounted) {
          setState(() {
            _classicConnection = null;
            connectedDeviceName = null;
          });
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to connect: $e")));
      setState(() => connectedDeviceName = null);
    } finally {
      if (mounted) setState(() => isConnecting = false);
    }
  }

  Future<void> _connectToBle(ble.BluetoothDevice device) async {
    Utils.instance.printLogs(_tag,"_connectToBle: ${device.remoteId}");
    setState(() {
      isConnecting = true;
      connectedDeviceName = device.platformName.isEmpty ? "Unknown BLE" : device.platformName;
    });

    try {
      // 1. Stabilization delay
      await Future.delayed(const Duration(milliseconds: 1000));

      // 2. Connect with retry loop
      bool success = false;
      int attempt = 0;
      while (attempt < 2 && !success) {
        try {
          Utils.instance.printLogs(_tag, "Connection Attempt ${attempt + 1}");
          bool useAutoConnect = (attempt == 1);
          
          await device.connect(
            license: ble.License.free, 
            autoConnect: useAutoConnect,
            mtu: useAutoConnect ? null : 512,
            timeout: const Duration(seconds: 15),
          );

          // If autoConnect is true, connect() returns immediately. We must wait.
          if (useAutoConnect) {
            Utils.instance.printLogs(_tag, "Waiting for connection to finalize...");
            await device.connectionState
                .where((s) => s == ble.BluetoothConnectionState.connected)
                .first
                .timeout(const Duration(seconds: 15));
          }
          
          success = true;
        } catch (e) {
          attempt++;
          Utils.instance.printLogs(_tag, "Attempt $attempt failed: $e");
          if (attempt >= 2) rethrow;
          await device.disconnect().catchError((_) {});
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      Utils.instance.printLogs(_tag, "Connected successfully. Discovering services...");
      await Future.delayed(const Duration(milliseconds: 1000)); 

      // 3. Discover services and subscribe
      List<ble.BluetoothService> services = await device.discoverServices();
      bool serviceFound = false;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == targetServiceUuid.toLowerCase()) {
          serviceFound = true;
          for (var char in service.characteristics) {
            if (char.properties.notify || char.properties.indicate) {
              await char.setNotifyValue(true);
              _bleDataSubscription?.cancel();
              _bleDataSubscription = char.lastValueStream.listen((value) {
                if (mounted) {
                  setState(() {
                    String decoded = utf8.decode(value);
                    _receivedData += "$decoded\n";
                    if (_receivedData.length > 2000) _receivedData = _receivedData.substring(_receivedData.length - 2000);
                  });
                }
              });
            }
          }
        }
      }

      if (!serviceFound && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Heart Service not found on Server device.")));
      }

      setState(() {
        _bleDevice = device;
      });

      device.connectionState.listen((state) {
        if (state == ble.BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _bleDevice = null;
            connectedDeviceName = null;
            _bleDataSubscription?.cancel();
          });
        }
      });

    } catch (e) {
      if (mounted) {
        Utils.instance.printLogs(_tag, "Final error: $e");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("BLE connection failed: $e")));
        setState(() => connectedDeviceName = null);
      }
    } finally {
      if (mounted) setState(() => isConnecting = false);
    }
  }

  void _disconnect() async {
    if (_classicConnection != null) {
      _classicConnection!.dispose(); 
      setState(() => _classicConnection = null);
    }
    if (_bleDevice != null) {
      await _bleDevice!.disconnect();
      setState(() {
        _bleDevice = null;
        _bleDataSubscription?.cancel();
      });
    }
    setState(() => connectedDeviceName = null);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          ),
          body: Column(
            children: [
              _buildStatusBar(),
              if (isDiscovering) const LinearProgressIndicator(),
              Expanded(
                child: isConnected ? _buildDataView() : _buildScanView(),
              ),
            ],
          ),
        ),
        if (isConnecting)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Connecting...", style: TextStyle(color: Colors.white, fontSize: 18, decoration: TextDecoration.none)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isConnected
                  ? "Connected to: $connectedDeviceName"
                  : "Status: Disconnected",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: (isDiscovering || isConnecting)
                ? null
                : (isConnected ? _disconnect : _startDiscovery),
            child: Text(isConnected ? "Disconnect" : (isDiscovering ? "Scanning..." : "Scan")),
          ),
        ],
      ),
    );
  }

  Widget _buildScanView() {
    if (results.isEmpty && !isDiscovering && hasSearched) {
      return const Center(child: Text("No device found", style: TextStyle(color: Colors.grey, fontSize: 16)));
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final d = results[i];
        return ListTile(
          leading: Icon(d.isBle ? Icons.bluetooth_audio : Icons.bluetooth),
          title: Text(d.name),
          subtitle: Text("${d.address} | ${d.rssi} dBm"),
          onTap: () => _onDeviceTap(d),
        );
      },
    );
  }

  Widget _buildDataView() {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                _receivedData.isEmpty ? "> Waiting for data..." : _receivedData,
                style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ElevatedButton(
            onPressed: () => setState(() => _receivedData = ""),
            child: const Text("Clear Terminal"),
          ),
        )
      ],
    );
  }

  @override
  void dispose() {
    _stopDiscovery();
    _classicConnection?.dispose();
    _bleDevice?.disconnect();
    _bleDataSubscription?.cancel();
    super.dispose();
  }
}
