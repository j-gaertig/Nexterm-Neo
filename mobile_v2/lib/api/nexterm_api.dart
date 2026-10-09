import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_info.dart';

/// Minimal HTTP client for the Nexterm REST API.
///
/// All paths from `mobile_v2/API.md`. Auth via session token
/// (`Authorization: Bearer <96hex>`), see `server/middlewares/auth.js`.
class NextermApiException implements Exception {
  NextermApiException(this.message);
  final String message;

  @override
  String toString() => 'NextermApiException: $message';
}

/// Response of `POST /api/auth/device/create`.
class DeviceCode {
  DeviceCode({required this.code, required this.token, required this.expiresAt});

  final String code;
  final String token;
  final DateTime expiresAt;
}

/// Session check result.
enum SessionStatus {
  /// Token valid (HTTP 200).
  valid,

  /// Token rejected (HTTP 401) — discard the session.
  invalid,

  /// Unclear (network error, timeout, server error) — keep the session.
  unknown,
}
/// Response of `POST /api/auth/device/poll`.
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

  /// Normalize a server URL: add scheme, append `/api`.
  /// The scheme is detected case-insensitively; an existing
  /// `/api` suffix (exact) is kept as is.
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

  /// Web base without `/api` suffix (for "open in browser").
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

  /// `GET /api/service/is-fts` — check reachability.
  Future<void> checkServer() async {
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('$baseUrl/service/is-fts'), headers: _headers(null))
          .timeout(timeout);
    } on TimeoutException {
      throw NextermApiException('Server is not responding (timeout).');
    } on SocketException {
      throw NextermApiException('Server unreachable.');
    } catch (_) {
      throw NextermApiException('Connection failed.');
    }
    if (response.statusCode != 200) {
      throw NextermApiException(
          'Not a Nexterm server (HTTP ${response.statusCode}).');
    }
  }

  /// `POST /api/auth/device/create` — create a device code for login.
  Future<DeviceCode> createDeviceCode() async {
    late http.Response response;
    try {
      response = await http
          .post(Uri.parse('$baseUrl/auth/device/create'),
              headers: _headers(null),
              body: json.encode({'clientType': 'mobile'}))
          .timeout(timeout);
    } on TimeoutException {
      throw NextermApiException('Server is not responding (timeout).');
    } on SocketException {
      throw NextermApiException('Server unreachable.');
    } catch (_) {
      throw NextermApiException('Connection failed.');
    }
    if (response.statusCode == 429) {
      throw NextermApiException(
          'Too many attempts. Please try again later.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw NextermApiException(
          'Could not create code (HTTP ${response.statusCode}).');
    }
    late final Map<String, dynamic> data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw NextermApiException('Invalid server response.');
    }
    final Object? code = data['code'];
    final Object? token = data['token'];
    if (code is! String || token is! String || code.isEmpty || token.isEmpty) {
      final Object? message = data['message'];
      throw NextermApiException(
          message is String ? message : 'Invalid server response.');
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

  /// `POST /api/auth/device/poll` — wait for approval.
  Future<DevicePoll> pollDeviceCode(String token) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/auth/device/poll'),
              headers: _headers(null), body: json.encode({'token': token}))
          .timeout(timeout);
      if (response.statusCode != 200) {
        // Only client errors end the wait; 429/5xx → keep polling.
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

  /// `GET /api/accounts/me` — check the session token.
  ///
  /// Only HTTP 401 means "invalid". Network errors/timeouts and
  /// server errors yield [SessionStatus.unknown] — the stored
  /// session must not be deleted then (offline start).
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

  /// `POST /api/auth/logout` — end the server session (token in body).
  /// Errors are ignored — local logout happens anyway.
  Future<void> logout(String token) async {
    try {
      await http
          .post(Uri.parse('$baseUrl/auth/logout'),
              headers: _headers(null), body: json.encode({'token': token}))
          .timeout(NextermApi.timeout);
    } catch (_) {}
  }
}
