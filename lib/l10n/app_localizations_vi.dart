// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get scannerTitle => 'Nhịp Tim Bluetooth';

  @override
  String get permissionsTitle => 'Yêu cầu quyền truy cập';

  @override
  String get permissionsContent =>
      'Bạn không thể sử dụng ứng dụng nếu không cấp quyền';

  @override
  String get no => 'Không';

  @override
  String get agree => 'Đồng ý';

  @override
  String get noDeviceFound => 'Không tìm thấy thiết bị';

  @override
  String get scan => 'Quét';

  @override
  String get scanning => 'Đang quét...';

  @override
  String get disconnect => 'Ngắt kết nối';

  @override
  String get connecting => 'Đang kết nối...';

  @override
  String connectedTo(String deviceName) {
    return 'Đã kết nối với: $deviceName';
  }

  @override
  String get statusDisconnected => 'Trạng thái: Đã ngắt kết nối';

  @override
  String get disconnected => 'Đã ngắt kết nối !!!';

  @override
  String get waitingForData => '> Đang chờ dữ liệu...';

  @override
  String get clearTerminal => 'Xóa màn hình';

  @override
  String get bpm => 'BPM';

  @override
  String get bpmNormal => 'Trạng thái: Bình thường';

  @override
  String get bpmWarning => 'Trạng thái: Cảnh báo!';

  @override
  String get serviceNotFound => 'Không tìm thấy dịch vụ Heart trên máy chủ.';

  @override
  String bleConnectionFailed(String error) {
    return 'Kết nối BLE thất bại: $error';
  }

  @override
  String classicConnectionFailed(String error) {
    return 'Kết nối thất bại: $error';
  }

  @override
  String get memberTitle => 'Danh sách thành viên:';

  @override
  String get bleConnectRestrict => 'Kết nối với BLE bị hạn chế.';
}
