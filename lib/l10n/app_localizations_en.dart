// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get scannerTitle => 'Bluetooth Scanner';

  @override
  String get permissionsTitle => 'Permissions Required';

  @override
  String get permissionsContent =>
      'You can\'t use the app if permission is not granted';

  @override
  String get no => 'No';

  @override
  String get agree => 'Agree';

  @override
  String get noDeviceFound => 'No device found';

  @override
  String get scan => 'Scan';

  @override
  String get scanning => 'Scanning...';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get connecting => 'Connecting...';

  @override
  String connectedTo(String deviceName) {
    return 'Connected to: $deviceName';
  }

  @override
  String get statusDisconnected => 'Status: Disconnected';

  @override
  String get waitingForData => '> Waiting for data...';

  @override
  String get clearTerminal => 'Clear Terminal';

  @override
  String get bpm => 'BPM';

  @override
  String get serviceNotFound => 'Heart Service not found on Server device.';

  @override
  String bleConnectionFailed(String error) {
    return 'BLE connection failed: $error';
  }

  @override
  String classicConnectionFailed(String error) {
    return 'Failed to connect: $error';
  }
}
