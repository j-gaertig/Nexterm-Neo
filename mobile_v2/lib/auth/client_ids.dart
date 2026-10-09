import 'package:shared_preferences/shared_preferences.dart';

/// Stable device/app identifiers for `POST /api/connections`
/// (`tabId`/`browserId`, mirrors the web client's session sync).
class ClientIds {
  static const _kDeviceId = 'nexterm_v2.device_id';
  static String? _appInstanceId;

  /// Persisted per-device id.
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  /// Per-app-launch id.
  static String appInstanceId() => _appInstanceId ??=
      'app_${DateTime.now().millisecondsSinceEpoch}';
}
