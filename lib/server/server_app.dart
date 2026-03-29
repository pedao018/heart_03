import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
  Timer? _dataTimer;
  int _currentHeartRate = 70;

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
        _dataTimer?.cancel();
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

        // MANDATORY: Set connectable to true and timeout to 0 (infinite)
        // Default timeout is 400ms, which is too short.
        final AdvertiseSettings advertiseSettings = AdvertiseSettings(
          connectable: true,
          timeout: 0, 
        );

        await blePeripheral.start(
          advertiseData: advertiseData,
          advertiseSettings: advertiseSettings,
        );
        
        _startDataSimulation();
        setState(() {
          _isAdvertising = true;
          _status = "Advertising... (Connectable)";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Error: $e";
      });
    }
  }

  void _startDataSimulation() {
    _dataTimer?.cancel();
    _dataTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      // Only attempt to send if a device is connected
      bool connected = await blePeripheral.isConnected;
      if (!connected) {
        setState(() => _status = "Advertising... (Waiting for connection)");
        return;
      }

      // Simulate heart rate fluctuation
      _currentHeartRate = 65 + (timer.tick % 15);
      final String data = "HR: $_currentHeartRate bpm";

      try {
        // Send data to connected clients
        await blePeripheral.sendData(Uint8List.fromList(utf8.encode(data)));
        setState(() {
          _status = "Sending: $data";
        });
      } catch (e) {
        debugPrint("Send error: $e");
      }
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _dataTimer?.cancel();
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
