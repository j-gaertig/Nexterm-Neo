import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_info.dart';

/// Minimaler HTTP-Client für die Nexterm-REST-API.
///
/// Alle Pfade aus `mobile_v2/API.md`. Auth per Session-Token
/// (`Authorization: Bearer <96hex>`), siehe `server/middlewares/auth.js`.
class NextermApiException implements Exception {
  NextermApiException(this.message);
  final String message;

  @override
  String toString() => 'NextermApiException: $message';
}

/// Antwort von `POST /api/auth/device/create`.
class DeviceCode {
  DeviceCode({required this.code, required this.token, required this.expiresAt});

  final String code;
  final String token;
  final DateTime expiresAt;
}

/// Ergebnis einer Session-Prüfung.
enum SessionStatus {
  /// Token gültig (HTTP 200).
  valid,

  /// Token abgelehnt (HTTP 401) — Session verwerfen.
  invalid,

  /// Unklar (Netzwerkfehler, Timeout, Serverfehler) — Session behalten.
  unknown,
}
/// Antwort von `POST /api/auth/device/poll`.
class DevicePoll {
  DevicePoll({required this.status, this.token});

  final String status;
  final String? token;

  bool get isPending => status == 'pending';
  bool get isAuthorized => status == 'authorized';
  bool get isInvalid => status == 'invalid';
}

class NextermApi {
  NextermApi({required String baseUrl}) : baseUrl = normalizeBaseUrl(baseUrl);

  final String baseUrl;

  static const Duration timeout = Duration(seconds: 30);

  static String get userAgent =>
      'NextermMobileV2/${AppInfo.version} (${Platform.operatingSystem}; ${Platform.operatingSystemVersion})';

  /// Server-URL normalisieren: Schema ergänzen, `/api` anhängen.
  /// Das Schema wird case-insensitiv erkannt; ein vorhandenes
  /// `/api`-Suffix (exakt) bleibt unverändert.
  static String normalizeBaseUrl(String url) {
    url = url.trim();
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      url = 'https://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (!url.toLowerCase().endsWith('/api')) url = '$url/api';
    return url;
  }

  /// Web-Basis ohne `/api`-Suffix (für "Im Browser öffnen").
  static String webBaseUrl(String apiBaseUrl) {
    var url = apiBaseUrl;
    if (url.endsWith('/api')) url = url.substring(0, url.length - 4);
    return url;
  }

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        'User-Agent': userAgent,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// `GET /api/service/is-fts` — Erreichbarkeit prüfen.
  Future<void> checkServer() async {
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('$baseUrl/service/is-fts'), headers: _headers(null))
          .timeout(timeout);
    } on TimeoutException {
      throw NextermApiException('Server antwortet nicht (Timeout).');
    } on SocketException {
      throw NextermApiException('Server nicht erreichbar.');
    } catch (_) {
      throw NextermApiException('Verbindung fehlgeschlagen.');
    }
    if (response.statusCode != 200) {
      throw NextermApiException(
          'Kein Nexterm-Server (HTTP ${response.statusCode}).');
    }
  }

  /// `POST /api/auth/device/create` — Geräte-Code für den Login erzeugen.
  Future<DeviceCode> createDeviceCode() async {
    late http.Response response;
    try {
      response = await http
          .post(Uri.parse('$baseUrl/auth/device/create'),
              headers: _headers(null),
              body: json.encode({'clientType': 'mobile'}))
          .timeout(timeout);
    } on TimeoutException {
      throw NextermApiException('Server antwortet nicht (Timeout).');
    } on SocketException {
      throw NextermApiException('Server nicht erreichbar.');
    } catch (_) {
      throw NextermApiException('Verbindung fehlgeschlagen.');
    }
    if (response.statusCode == 429) {
      throw NextermApiException(
          'Zu viele Versuche. Bitte später erneut versuchen.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw NextermApiException(
          'Code konnte nicht erstellt werden (HTTP ${response.statusCode}).');
    }
    late final Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw NextermApiException('Ungültige Server-Antwort.');
    }
    final Object? code = data['code'];
    final Object? token = data['token'];
    if (code is! String || token is! String || code.isEmpty || token.isEmpty) {
      final Object? message = data['message'];
      throw NextermApiException(
          message is String ? message : 'Ungültige Server-Antwort.');
    }
    final Object? expiresAt = data['expiresAt'];
    return DeviceCode(
      code: code,
      token: token,
      expiresAt: expiresAt is String
          ? DateTime.tryParse(expiresAt) ??
              DateTime.now().add(const Duration(minutes: 10))
          : DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  /// `POST /api/auth/device/poll` — auf Freigabe warten.
  Future<DevicePoll> pollDeviceCode(String token) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/auth/device/poll'),
              headers: _headers(null), body: json.encode({'token': token}))
          .timeout(timeout);
      if (response.statusCode != 200) {
        // Nur Client-Fehler beenden das Warten; 429/5xx → weiter pollen.
        if (response.statusCode == 400 ||
            response.statusCode == 401 ||
            response.statusCode == 404 ||
            response.statusCode == 410) {
          return DevicePoll(status: 'invalid');
        }
        return DevicePoll(status: 'error');
      }
      final Map<String, dynamic> data =
          json.decode(response.body) as Map<String, dynamic>;
      final Object? status = data['status'];
      final Object? sessionToken = data['token'];
      return DevicePoll(
        status: status is String ? status : 'invalid',
        token: sessionToken is String ? sessionToken : null,
      );
    } catch (_) {
      return DevicePoll(status: 'error');
    }
  }

  /// `GET /api/accounts/me` — Session-Token prüfen.
  ///
  /// Nur HTTP 401 bedeutet "ungültig". Netzwerkfehler/Timeouts und
  /// Serverfehler ergeben [SessionStatus.unknown] — die gespeicherte
  /// Session darf dann nicht gelöscht werden (Offline-Start).
  Future<SessionStatus> checkSession(String token,
      {Duration? timeout}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/accounts/me'), headers: _headers(token))
          .timeout(timeout ?? NextermApi.timeout);
      if (response.statusCode == 200) return SessionStatus.valid;
      if (response.statusCode == 401) return SessionStatus.invalid;
      return SessionStatus.unknown;
    } catch (_) {
      return SessionStatus.unknown;
    }
  }

  /// `POST /api/auth/logout` — Server-Session beenden (Token im Body).
  /// Fehler werden ignoriert — lokales Abmelden folgt ohnehin.
  Future<void> logout(String token) async {
    try {
      await http
          .post(Uri.parse('$baseUrl/auth/logout'),
              headers: _headers(null), body: json.encode({'token': token}))
          .timeout(NextermApi.timeout);
    } catch (_) {}
  }
}
