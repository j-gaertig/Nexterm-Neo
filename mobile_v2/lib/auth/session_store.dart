import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistierte Login-Session.
///
/// Das Session-Token liegt verschlüsselt im Secure Storage (Keychain/
/// Keystore), nur Server-URL und Label in den SharedPreferences.
class SessionInfo {
  const SessionInfo(
      {required this.token, required this.baseUrl, required this.label});

  final String token;
  final String baseUrl;
  final String label;
}

class SessionStore {
  SessionStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static const String _kToken = 'nexterm_v2.token';
  static const String _kBaseUrl = 'nexterm_v2.base_url';
  static const String _kLabel = 'nexterm_v2.label';

  Future<SessionInfo?> load() async {
    try {
      // Timeout: löst nie auf, wenn das Plugin fehlt (z. B. Widget-Tests).
      final token = await _secure
          .read(key: _kToken)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString(_kBaseUrl);
      if (token == null ||
          token.isEmpty ||
          baseUrl == null ||
          baseUrl.isEmpty) {
        return null;
      }
      return SessionInfo(
        token: token,
        baseUrl: baseUrl,
        label: prefs.getString(_kLabel) ?? baseUrl,
      );
    } catch (_) {
      // Secure Storage nicht verfügbar (z. B. in Widget-Tests).
      return null;
    }
  }

  Future<void> save(SessionInfo session) async {
    await _secure.write(key: _kToken, value: session.token);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBaseUrl, session.baseUrl);
      await prefs.setString(_kLabel, session.label);
    } catch (_) {
      // Rollback: kein verwaistes Token ohne baseUrl zurücklassen.
      try {
        await _secure.delete(key: _kToken);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secure.delete(key: _kToken);
    } catch (_) {}
    await prefs.remove(_kBaseUrl);
    await prefs.remove(_kLabel);
  }
}
