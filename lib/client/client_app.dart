import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart' as classic;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:heart_03/utils/utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:heart_03/l10n/app_localizations.dart';
import 'package:heart_03/main.dart';

class DiscoveredDevice {
  final String name;
  final String address;
  final int rssi;
  final bool isBle;
  final dynamic device;

  DiscoveredDevice({required this.name, required this.address, required this.rssi, required this.isBle, required this.device});
}

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ClientPage(title: 'Bluetooth Scanner');
  }
}

class ClientPage extends StatefulWidget {
  const ClientPage({super.key, required this.title});

  final String title;

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> with SingleTickerProviderStateMixin {
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

  // Static Name, Address -> auto connect targets
  final String _targetDeviceName = "DESKTOP-5VPL89H";
  final String _targetDeviceAddress = "E8:48:B8:C8:20:00";

  StreamSubscription<classic.BluetoothDiscoveryResult>? _classicSubscription;
  StreamSubscription<List<ble.ScanResult>>? _bleSubscription;
  Timer? _discoveryTimer;

  List<DiscoveredDevice> results = [];

  bool get isConnected => (_classicConnection?.isConnected ?? false) || (_bleDevice != null);

  // Heart Rate Animation & Data
  int? _currentBpm;
  late AnimationController _heartController;
  late Animation<double> _heartAnimation;

  // List member
  final String _listMember = "- Mem A.\n- Mem B.\n- Mem C.";

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _heartAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _heartController, curve: Curves.easeInOut));
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
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.permissionsTitle),
        content: Text(l10n.permissionsContent),
        actions: [
          TextButton(onPressed: () => SystemNavigator.pop(), child: Text(l10n.no)),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _checkPermissions();
            },
            child: Text(l10n.agree),
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
      // Full detail logging for Classic
      Utils.instance.printLogs(
        _tag,
        "_startDiscovery common: Name: ${r.device.name}, Address: ${r.device.address}, RSSI: ${r.rssi}, Type: ${r.device.type}, BondState: ${r.device.bondState}",
      );

      _addDevice(
        DiscoveredDevice(name: r.device.name ?? "Unknown Classic", address: r.device.address, rssi: r.rssi, isBle: false, device: r.device),
      );
    });

    // BLE Scan
    _bleSubscription = ble.FlutterBluePlus.onScanResults.listen((scanResults) {
      for (ble.ScanResult r in scanResults) {
        String name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : (r.device.platformName.isNotEmpty ? r.device.platformName : "Unknown BLE");

        // Full detail logging for BLE
        Utils.instance.printLogs(
          _tag,
          "_startDiscovery BLE: Device: ${r.device.remoteId}, Name: $name, RSSI: ${r.rssi}, Services: ${r.advertisementData.serviceUuids}",
        );

        _addDevice(DiscoveredDevice(name: name, address: r.device.remoteId.toString(), rssi: r.rssi, isBle: true, device: r.device));
      }
    });

    await ble.FlutterBluePlus.startScan(timeout: _discoveryTimeout);
  }

  void _addDevice(DiscoveredDevice device) {
    if (!mounted) return;

    // 1. Check for Auto-Connect FIRST (before any filters)
    if (!isConnecting &&
        !isConnected &&
        device.name == _targetDeviceName &&
        device.address.toUpperCase() == _targetDeviceAddress.toUpperCase()) {
      Utils.instance.printLogs(_tag, "_addDevice detected target -> auto connect");
      _onDeviceTap(device);
      return;
    }

    // Requirement: Skip BLE from list
    if (device.isBle) return;

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

    await ble.FlutterBluePlus.stopScan().catchError((_) {});
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

  void _updateBpmFromData(String data) {
    final match = RegExp(r'BPM\s*:\s*(\d+)').firstMatch(data);
    if (match != null) {
      final bpmStr = match.group(1);
      if (bpmStr != null) {
        final bpm = int.tryParse(bpmStr);
        if (bpm != null) {
          setState(() {
            _currentBpm = bpm;
            // Animation logic
            bool isDanger = bpm >= 100;
            _heartController.duration = Duration(milliseconds: isDanger ? 300 : 800);
            _heartController.repeat(reverse: true);
          });
        }
      }
    }
  }

  Future<void> _connectToClassic(classic.BluetoothDevice device) async {
    final l10n = AppLocalizations.of(context)!;
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

      _classicConnection!.input!
          .listen((data) {
            if (mounted) {
              setState(() {
                String resultDecode = utf8.decode(data);
                Utils.instance.printLogs(_tag, "_connectToClassic: $data . resultDecode= $resultDecode");
                _updateBpmFromData(resultDecode);
                _receivedData += resultDecode;
                if (_receivedData.length > 2000) _receivedData = _receivedData.substring(_receivedData.length - 2000);
              });
            }
          })
          .onDone(() {
            if (mounted) {
              setState(() {
                _classicConnection = null;
                connectedDeviceName = null;
                _currentBpm = null;
              });
            }
          });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.classicConnectionFailed(e.toString()))));
      setState(() => connectedDeviceName = null);
    } finally {
      if (mounted) setState(() => isConnecting = false);
    }
  }

  Future<void> _connectToBle(ble.BluetoothDevice device) async {
    final l10n = AppLocalizations.of(context)!;
    Utils.instance.printLogs(_tag, "_connectToBle: ${device.remoteId}");
    setState(() {
      isConnecting = true;
      connectedDeviceName = device.platformName.isEmpty ? "Unknown BLE" : device.platformName;
    });

    try {
      // Settle delay
      await Future.delayed(const Duration(milliseconds: 1500));

      // Connect loop
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

          // Critical fix: Wait for handshake to finish if autoConnect is true
          if (useAutoConnect) {
            Utils.instance.printLogs(_tag, "Waiting for connection to finalize...");
            await device.connectionState
                .where((s) => s == ble.BluetoothConnectionState.connected)
                .first
                .timeout(const Duration(seconds: 20));
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
      await Future.delayed(const Duration(milliseconds: 1500));

      // Discover and subscribe
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
                    _updateBpmFromData(decoded);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.serviceNotFound)));
      }

      setState(() {
        _bleDevice = device;
      });

      device.connectionState.listen((state) {
        if (state == ble.BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _bleDevice = null;
            connectedDeviceName = null;
            _currentBpm = null;
            _bleDataSubscription?.cancel();
          });
        }
      });
    } catch (e) {
      if (mounted) {
        Utils.instance.printLogs(_tag, "Final error: $e");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.bleConnectionFailed(e.toString()))));
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
    setState(() {
      connectedDeviceName = null;
      _currentBpm = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(l10n.scannerTitle),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/images/Logo_IUH.png', height: 80),
                            const SizedBox(height: 16),
                            const SizedBox(height: 8),
                            Text(
                              l10n.memberTitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _listMember,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.normal),
                            ),
                            const Divider(height: 32),
                            ListTile(
                              leading: const Icon(Icons.language),
                              title: const Text("English"),
                              onTap: () {
                                MyApp.of(context).setLocale(const Locale('en'));
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.language),
                              title: const Text("Tiếng Việt"),
                              onTap: () {
                                MyApp.of(context).setLocale(const Locale('vi'));
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              _buildStatusBar(),
              if (isDiscovering) const LinearProgressIndicator(),
              Expanded(child: isConnected ? _buildDataView() : _buildScanView()),
            ],
          ),
        ),
        if (isConnecting)
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    l10n.connecting,
                    style: const TextStyle(color: Colors.white, fontSize: 18, decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusBar() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isConnected ? l10n.connectedTo(connectedDeviceName ?? "Unknown") : l10n.statusDisconnected,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: (isDiscovering || isConnecting) ? null : (isConnected ? _disconnect : _startDiscovery),
            child: Text(isConnected ? l10n.disconnect : (isDiscovering ? l10n.scanning : l10n.scan)),
          ),
        ],
      ),
    );
  }

  Widget _buildScanView() {
    final l10n = AppLocalizations.of(context)!;
    if (results.isEmpty && !isDiscovering && hasSearched) {
      return Center(
        child: Text(l10n.noDeviceFound, style: const TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final d = results[i];
        return ListTile(
          leading: const Icon(Icons.bluetooth),
          title: Text(d.name),
          subtitle: Text("${d.address} | ${d.rssi} dBm"),
          onTap: () => _onDeviceTap(d),
        );
      },
    );
  }

  Widget _buildDataView() {
    final l10n = AppLocalizations.of(context)!;
    bool isDanger = (_currentBpm ?? 0) >= 100;
    Color bgColor = isDanger ? Colors.red.shade50 : Colors.green.shade50;

    return Container(
      color: bgColor,
      child: Column(
        children: [
          // Heart Rate Visual Section
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                ScaleTransition(
                  scale: _heartAnimation,
                  child: Icon(Icons.favorite, color: isDanger ? Colors.red : Colors.green, size: 80),
                ),
                const SizedBox(height: 10),
                Text(l10n.bpm, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  _currentBpm?.toString() ?? "--",
                  style: TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: isDanger ? Colors.red : Colors.green),
                ),
              ],
            ),
          ),
          // Terminal Section
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  _receivedData.isEmpty ? l10n.waitingForData : _receivedData,
                  style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(onPressed: () => setState(() => _receivedData = ""), child: Text(l10n.clearTerminal)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopDiscovery();
    _classicConnection?.dispose();
    _bleDevice?.disconnect();
    _bleDataSubscription?.cancel();
    _heartController.dispose();
    super.dispose();
  }
}
