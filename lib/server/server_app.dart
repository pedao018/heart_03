import 'package:flutter/material.dart';
import 'package:heart_03/utils/utils.dart';

class ServerApp extends StatelessWidget {
  const ServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Measure Demo',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const ServerPage(title: 'Heart Measure - Server'),
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
  void init() {
    Utils.instance.printLogs("ServerPage", "init");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            ElevatedButton(
              onPressed: () {
                init();
              },
              child: Text("Send Data"),
            ),
          ],
        ),
      ),
    );
  }
}
