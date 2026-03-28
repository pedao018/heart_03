import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  classic.BluetoothConnection? _connection;
  String _receivedData = "";
  bool isConnecting = false;
  bool isDiscovering = false;
  bool hasSearched = false;
  String? connectedDeviceName;

  final String _tag = "ClientPageState";
  final Duration _discoveryTimeout = const Duration(seconds: 30);

  StreamSubscription<classic.BluetoothDiscoveryResult>? _classicSubscription;
  StreamSubscription<List<ble.ScanResult>>? _bleSubscription;
  Timer? _discoveryTimer;

  List<DiscoveredDevice> results = [];

  bool get isConnected => (_connection?.isConnected ?? false);

  @override
  void initState() {
    super.initState();
    // Step 1: Check permissions on app open
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissions());
  }

  // --- Step 1: Permission Flow ---
  Future<void> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
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
              _checkPermissions(); // Request again
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

  // --- Step 2: Scanning Logic ---
  void _startDiscovery() async {
    if (isDiscovering || isConnecting) return;

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

  void _stopDiscovery() {
    _classicSubscription?.cancel();
    _bleSubscription?.cancel();
    ble.FlutterBluePlus.stopScan();
    _discoveryTimer?.cancel();
    setState(() => isDiscovering = false);
  }

  // --- Step 3: Connection & Data ---
  void _onDeviceTap(DiscoveredDevice d) {
    if (isConnecting || isConnected) return;
    
    _stopDiscovery(); // Stop scan on tap

    if (!d.isBle) {
      _connectToClassic(d.device as classic.BluetoothDevice);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("BLE connection requires GATT services implementation."))
      );
    }
  }

  Future<void> _connectToClassic(classic.BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
      connectedDeviceName = device.name;
    });
    try {
      // Step 3a: Check bonding state
      if (!device.isBonded) {
        Utils.instance.printLogs(_tag, "Bonding with ${device.name}...");
        bool? bonded = await classic.FlutterBluetoothSerial.instance.bondDeviceAtAddress(device.address);
        if (bonded != true) {
          throw Exception("Bonding failed or was cancelled");
        }
      }

      // Step 3b: Connect
      _connection = await classic.BluetoothConnection.toAddress(device.address);
      Utils.instance.printLogs(_tag, "Connected to ${device.name}");

      _connection!.input!.listen((data) {
        setState(() {
          _receivedData += utf8.decode(data);
          if (_receivedData.length > 1000) _receivedData = _receivedData.substring(_receivedData.length - 1000);
        });
      }).onDone(() {
        setState(() {
          _connection = null;
          connectedDeviceName = null;
        });
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to connect: $e")));
      Utils.instance.printLogs("Failed to connect: $e");
      setState(() => connectedDeviceName = null);
    } finally {
      setState(() => isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          // Control Bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isConnected 
                      ? "Connected to: $connectedDeviceName" 
                      : (isConnecting ? "Connecting..." : "Status: Disconnected"),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: isDiscovering ? null : (isConnected ? () => _connection?.dispose() : _startDiscovery),
                  child: Text(isConnected ? "Disconnect" : (isDiscovering ? "Scanning..." : "Scan")),
                ),
              ],
            ),
          ),

          if (isDiscovering) const LinearProgressIndicator(),

          // Main Content
          Expanded(
            child: isConnected 
              ? _buildDataView()
              : _buildScanView(),
          ),
        ],
      ),
    );
  }

  Widget _buildScanView() {
    if (results.isEmpty && !isDiscovering && hasSearched) {
      return const Center(child: Text("No device found", style: TextStyle(color: Colors.grey)));
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
    _connection?.dispose();
    super.dispose();
  }
}
