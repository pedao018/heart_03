import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

class ServerApp extends StatelessWidget {
  const ServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Server',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ServerPage(title: 'Heart Server (BLE Advertiser)'),
    );
  }
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key, required this.title});
  final String title;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final FlutterBlePeripheral blePeripheral = FlutterBlePeripheral();
  bool _isAdvertising = false;
  String _status = "Idle";
  StreamSubscription? _stateSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _listenToState();
  }

  void _listenToState() {
    _stateSubscription = blePeripheral.onPeripheralStateChanged?.listen((state) {
      setState(() {
        _status = "Peripheral State: ${state.name}";
      });
    });
  }

  Future<void> _checkPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();
  }

  void _toggleAdvertising() async {
    try {
      final bool isSupported = await blePeripheral.isSupported;
      if (!isSupported) {
        setState(() => _status = "BLE Advertising not supported");
        return;
      }

      final bool advertising = await blePeripheral.isAdvertising;
      if (advertising) {
        await blePeripheral.stop();
        setState(() {
          _isAdvertising = false;
          _status = "Stopped Advertising";
        });
      } else {
        // Define the advertisement data
        final AdvertiseData advertiseData = AdvertiseData(
          serviceUuid: 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7', // Custom UUID
          localName: 'HeartServer-A54',
          includeDeviceName: true,
        );

        await blePeripheral.start(advertiseData: advertiseData);
        setState(() {
          _isAdvertising = true;
          _status = "Advertising... (Visible to Client)";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Error: $e";
      });
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isAdvertising ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
              size: 100,
              color: _isAdvertising ? Colors.deepPurple : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              _status,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _toggleAdvertising,
              icon: Icon(_isAdvertising ? Icons.stop : Icons.play_arrow),
              label: Text(_isAdvertising ? "Stop Advertising" : "Start Advertising"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                "When Advertising is ON, the Client phone can find this device using the specific Service UUID.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            )
          ],
        ),
      ),
    );
  }
}
