import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart' as classic;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:heart_03/utils/utils.dart';
import 'package:permission_handler/permission_handler.dart';

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
      title: 'Heart Measure Demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen)),
      home: const ClientPage(title: 'Heart Measure - Client'),
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
  classic.BluetoothConnection? connection;
  String _receivedData = "";
  bool isConnecting = false;
  bool isDiscovering = false;
  final String _tag = "ClientPageState";

  final String _targetDeviceName = "HC-05";
  final Duration _discoveryTimeout = const Duration(seconds: 30);

  StreamSubscription<classic.BluetoothDiscoveryResult>? _classicSubscription;
  StreamSubscription<List<ble.ScanResult>>? _bleSubscription;
  Timer? _discoveryTimer;

  List<DiscoveredDevice> results = [];

  bool get isConnected => (connection?.isConnected ?? false);

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.bluetoothAdvertise,
    ].request();
    _checkBluetoothStatus();
  }

  Future<void> _checkBluetoothStatus() async {
    classic.BluetoothState state = await classic.FlutterBluetoothSerial.instance.state;
    if (state == classic.BluetoothState.STATE_OFF) {
      await classic.FlutterBluetoothSerial.instance.requestEnable();
    }
  }

  void _startDiscovery() async {
    setState(() {
      isDiscovering = true;
      results.clear();
    });

    _discoveryTimer?.cancel();
    _discoveryTimer = Timer(_discoveryTimeout, _stopDiscovery);

    // 1. Classic Discovery (HC-05)
    _classicSubscription = classic.FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
      _addDevice(DiscoveredDevice(
        name: r.device.name ?? "Unknown Classic",
        address: r.device.address,
        rssi: r.rssi,
        isBle: false,
        device: r.device,
      ));

      if (r.device.name == _targetDeviceName) {
        _stopDiscovery();
        _connectToClassic(r.device);
      }
    });

    // 2. BLE Scan (iPhones, Sensors)
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
    Utils.instance.printLogs(_tag, "_addDevice: $device");
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

  void _connectToHC05() async {
    classic.BluetoothState state = await classic.FlutterBluetoothSerial.instance.state;
    if (state != classic.BluetoothState.STATE_ON) {
      await classic.FlutterBluetoothSerial.instance.requestEnable();
      return;
    }

    setState(() => isConnecting = true);

    try {
      List<classic.BluetoothDevice> bonded = await classic.FlutterBluetoothSerial.instance.getBondedDevices();
      classic.BluetoothDevice? target = bonded.where((d) => d.name == _targetDeviceName).firstOrNull;

      if (target != null) {
        _connectToClassic(target);
      } else {
        setState(() => isConnecting = false);
        _startDiscovery();
      }
    } catch (e) {
      Utils.instance.printLogs(_tag, "Error: $e");
      setState(() => isConnecting = false);
    }
  }

  void _connectToClassic(classic.BluetoothDevice device) async {
    _stopDiscovery();
    setState(() => isConnecting = true);
    try {
      connection = await classic.BluetoothConnection.toAddress(device.address);
      connection!.input!.listen((data) {
        setState(() {
          _receivedData += utf8.decode(data);
          if (_receivedData.length > 500) _receivedData = _receivedData.substring(_receivedData.length - 500);
        });
      }).onDone(() => setState(() => connection = null));
    } catch (e) {
      Utils.instance.printLogs(_tag, "Classic Conn Error: $e");
    } finally {
      setState(() => isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [if (isDiscovering) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))]
      ),
      body: Column(
        children: [
          ListTile(
            title: Text(isConnected ? "Connected to $_targetDeviceName" : "Disconnected"),
            trailing: isConnecting ? const CircularProgressIndicator() : ElevatedButton(
              onPressed: isConnected ? () => connection?.dispose() : _connectToHC05,
              child: Text(isConnected ? "Disconnect" : "Connect"),
            ),
          ),
          if (results.isNotEmpty) ...[
            const Divider(),
            const Text("Discovered (Classic & BLE):", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final d = results[i];
                  return ListTile(
                    leading: Icon(d.isBle ? Icons.bluetooth_audio : Icons.bluetooth, color: d.isBle ? Colors.blue : Colors.grey),
                    title: Text(d.name),
                    subtitle: Text("${d.address} | ${d.isBle ? 'BLE' : 'Classic'}"),
                    trailing: Text("${d.rssi} dBm"),
                    onTap: d.isBle ? null : () => _connectToClassic(d.device),
                  );
                },
              ),
            )
          ],
          const Divider(),
          const Text("Data:"),
          Expanded(child: Container(width: double.infinity, color: Colors.black12, child: SingleChildScrollView(reverse: true, child: Text(_receivedData)))),
          ElevatedButton(onPressed: () => setState(() => _receivedData = ""), child: const Text("Clear")),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopDiscovery();
    connection?.dispose();
    super.dispose();
  }
}
