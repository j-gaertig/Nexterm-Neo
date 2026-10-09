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
  const NextermApiException(this.message);
  final String message;

  @override
  String toString() => 'NextermApiException: $message';
}

/// Thrown when the server rejects the session token (HTTP 401).
/// Callers should drop the stored session and show the login.
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.message = 'Session expired.']);

  final String message;

  @override
  String toString() => 'SessionExpiredException: $message';
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
    // The dev server answers every unknown path with the SPA shell —
    // require a recognizable body (bool for is-fts).
    try {
      final decoded = json.decode(response.body);
      if (decoded is! bool) {
        throw NextermApiException('Not a Nexterm server.');
      }
    } catch (e) {
      if (e is NextermApiException) rethrow;
      throw NextermApiException('Not a Nexterm server.');
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

  /// `GET /api/entries/list` — full entry tree (folders/organizations
  /// nest servers via `entries`). Throws [SessionExpiredException] on
  /// HTTP 401 so callers can return to the login.
  Future<List<dynamic>> fetchEntries(String token) async {
    late http.Response response;
    try {
      response = await http
          .get(Uri.parse('$baseUrl/entries/list'), headers: _headers(token))
          .timeout(NextermApi.timeout);
    } on TimeoutException {
      throw NextermApiException('Server is not responding (timeout).');
    } on SocketException {
      throw NextermApiException('Server unreachable.');
    } catch (_) {
      throw NextermApiException('Connection failed.');
    }
    if (response.statusCode == 401) throw SessionExpiredException();
    if (response.statusCode != 200) {
      throw NextermApiException(
          'Could not load servers (HTTP ${response.statusCode}).');
    }
    try {
      final decoded = json.decode(response.body);
      if (decoded is List) return decoded;
      throw NextermApiException('Invalid server response.');
    } catch (e) {
      if (e is NextermApiException) rethrow;
      throw NextermApiException('Invalid server response.');
    }
  }

  /// Build a WebSocket URL: scheme http→ws/https→wss + path + query.
  static String wsUrl(String apiBaseUrl, String path,
      [Map<String, String>? query]) {
    var url = apiBaseUrl.replaceFirst('http://', 'ws://').replaceFirst(
        'https://', 'wss://');
    if (query == null || query.isEmpty) return '$url$path';
    final qs = query.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$url$path?$qs';
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    final fullPath = '${base.path}$path';
    return base.replace(
        path: fullPath,
        queryParameters: {...base.queryParameters, ...?query});
  }

  /// Authed request with unified errors. 401 → [SessionExpiredException].
  Future<http.Response> _authed(
    String method,
    String path,
    String token, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers(token);
    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response =
              await http.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          response = await http
              .post(uri,
                  headers: headers,
                  body: body != null ? json.encode(body) : null)
              .timeout(timeout);
        case 'PUT':
          response = await http
              .put(uri,
                  headers: headers,
                  body: body != null ? json.encode(body) : null)
              .timeout(timeout);
        case 'PATCH':
          response = await http
              .patch(uri,
                  headers: headers,
                  body: body != null ? json.encode(body) : null)
              .timeout(timeout);
        case 'DELETE':
          response =
              await http.delete(uri, headers: headers).timeout(timeout);
        default:
          throw NextermApiException('Connection failed.');
      }
    } on TimeoutException {
      throw NextermApiException('Server is not responding (timeout).');
    } on SocketException {
      throw NextermApiException('Server unreachable.');
    } catch (e) {
      if (e is NextermApiException || e is SessionExpiredException) {
        rethrow;
      }
      throw NextermApiException('Connection failed.');
    }
    if (response.statusCode == 401) throw SessionExpiredException();
    return response;
  }

  dynamic _decode(http.Response response, {bool allowEmpty = false}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (allowEmpty && response.body.isEmpty) return null;
      dynamic decoded;
      try {
        decoded = json.decode(response.body);
      } catch (_) {
        throw NextermApiException('Invalid server response.');
      }
      // Several routes answer HTTP 200 with `{code, message}` on error
      // (e.g. entries wake/duplicate). Numeric code = failure.
      // (Device codes use a *string* code and are unaffected.)
      if (decoded is Map && decoded['code'] is int) {
        final m = decoded['message'];
        throw NextermApiException(
            m is String ? m : 'Request failed.');
      }
      return decoded;
    }
    String? message;
    try {
      final data = json.decode(response.body);
      if (data is Map) {
        final m = data['message'] ?? data['error'];
        if (m is String) message = m;
      }
    } catch (_) {}
    throw NextermApiException(
        message ?? 'Request failed (HTTP ${response.statusCode}).');
  }

  // -- Entries ---------------------------------------------------------

  /// `GET /api/entries/:entryId` — full detail incl. config.
  Future<Map<String, dynamic>> fetchEntry(
      String token, int entryId) async {
    final data = _decode(
        await _authed('GET', '/entries/$entryId', token));
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw NextermApiException('Invalid server response.');
  }

  /// `GET /api/entries/recent` — recently connected servers.
  Future<List<Map<String, dynamic>>> fetchRecent(String token,
      {int limit = 5}) async {
    final data = _decode(await _authed(
        'GET', '/entries/recent', token, query: {'limit': '$limit'}));
    if (data is! List) throw NextermApiException('Invalid server response.');
    return data
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// `PUT /api/entries/` — create. Returns the new id.
  Future<int> createEntry(
      String token, Map<String, dynamic> payload) async {
    final data =
        _decode(await _authed('PUT', '/entries/', token, body: payload));
    if (data is Map && data['id'] is num) {
      return (data['id'] as num).toInt();
    }
    throw NextermApiException('Invalid server response.');
  }

  /// `PATCH /api/entries/:entryId` — partial update.
  Future<void> updateEntry(
      String token, int entryId, Map<String, dynamic> payload) async {
    _decode(await _authed('PATCH', '/entries/$entryId', token,
        body: payload));
  }

  /// `DELETE /api/entries/:entryId`.
  Future<void> deleteEntry(String token, int entryId) async {
    _decode(
        await _authed('DELETE', '/entries/$entryId', token));
  }

  /// `POST /api/entries/:entryId/duplicate`.
  Future<void> duplicateEntry(String token, int entryId) async {
    _decode(await _authed('POST', '/entries/$entryId/duplicate', token));
  }

  /// `POST /api/entries/:entryId/wake` — Wake-on-LAN.
  Future<void> wakeEntry(String token, int entryId) async {
    _decode(await _authed('POST', '/entries/$entryId/wake', token));
  }

  // -- Identities ------------------------------------------------------

  /// `GET /api/identities/list` — no secrets included.
  Future<List<Map<String, dynamic>>> fetchIdentities(
      String token) async {
    final data = _decode(await _authed('GET', '/identities/list', token));
    if (data is! List) throw NextermApiException('Invalid server response.');
    return data
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// `PUT /api/identities/` — create (`server/routes/identity.js`,
  /// `server/validations/identity.js`: name/type required).
  Future<void> createIdentity(
      String token, Map<String, dynamic> payload) async {
    _decode(await _authed('PUT', '/identities/', token, body: payload));
  }

  /// `PATCH /api/identities/:id` — update.
  Future<void> updateIdentity(
      String token, int identityId, Map<String, dynamic> payload) async {
    _decode(await _authed(
        'PATCH', '/identities/$identityId', token,
        body: payload));
  }

  /// `DELETE /api/identities/:id` — delete.
  Future<void> deleteIdentity(String token, int identityId) async {
    _decode(
        await _authed('DELETE', '/identities/$identityId', token));
  }

  // -- Connections -----------------------------------------------------

  /// `POST /api/connections/` — open a session. Returns the raw result
  /// (`{sessionId, ...}`).
  Future<Map<String, dynamic>> createConnection(
      String token, Map<String, dynamic> body) async {
    final response =
        await _authed('POST', '/connections/', token, body: body);
    if (response.statusCode != 200 && response.statusCode != 201) {
      String? message;
      try {
        final data = json.decode(response.body);
        if (data is Map) {
          final m = data['error'] ?? data['message'];
          if (m is String) message = m;
        }
      } catch (_) {}
      throw NextermApiException(
          message ?? 'Could not open session (HTTP ${response.statusCode}).');
    }
    final data = _decode(response);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw NextermApiException('Invalid server response.');
  }

  /// `GET /api/connections` — active sessions (tabId/browserId filter).
  Future<List<Map<String, dynamic>>> listConnections(String token,
      {String? tabId, String? browserId}) async {
    final query = <String, String>{};
    final t = tabId;
    if (t != null) query['tabId'] = t;
    final b = browserId;
    if (b != null) query['browserId'] = b;
    final data =
        _decode(await _authed('GET', '/connections', token, query: query));
    if (data is! List) throw NextermApiException('Invalid server response.');
    return data
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// `POST /api/connections/:id/hibernate` etc. — lifecycle helpers.
  Future<void> hibernateConnection(String token, String id) async {
    _decode(await _authed('POST', '/connections/$id/hibernate', token));
  }

  Future<void> resumeConnection(
      String token, String id, Map<String, dynamic> body) async {
    _decode(
        await _authed('POST', '/connections/$id/resume', token, body: body));
  }

  Future<void> deleteConnection(String token, String id) async {
    _decode(await _authed('DELETE', '/connections/$id', token));
  }

  Future<void> duplicateConnection(
      String token, String id, Map<String, dynamic> body) async {
    _decode(await _authed('POST', '/connections/$id/duplicate', token,
        body: body));
  }

  /// `POST /api/connections/:entryId/exec` — one-shot SSH command.
  Future<Map<String, dynamic>> execCommand(
      String token, int entryId, String command,
      {int? identityId}) async {
    final data = _decode(await _authed(
        'POST', '/connections/$entryId/exec', token,
        query: identityId != null ? {'identityId': '$identityId'} : null,
        body: {'command': command}));
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw NextermApiException('Invalid server response.');
  }

  /// `POST /api/connections/:id/paste-password` — type an identity
  /// password into the session stream (`submit` appends Enter).
  Future<void> pasteIdentityPassword(String token, String sessionId,
      {int? identityId, bool submit = false}) async {
    final body = <String, dynamic>{'submit': submit};
    if (identityId != null) body['identityId'] = identityId;
    _decode(await _authed(
        'POST', '/connections/$sessionId/paste-password', token,
        body: body));
  }

  // -- Monitoring ------------------------------------------------------

  /// `GET /api/monitoring/` — all monitored servers.
  Future<List<Map<String, dynamic>>> fetchMonitoring(
      String token) async {
    final data = _decode(await _authed('GET', '/monitoring/', token));
    if (data is! List) throw NextermApiException('Invalid server response.');
    return data
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// `GET /api/monitoring/:serverId?timeRange=` — detail + history.
  Future<Map<String, dynamic>> fetchServerMonitoring(
      String token, String serverId, String range) async {
    final data = _decode(await _authed(
        'GET', '/monitoring/$serverId', token,
        query: {'timeRange': range}));
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw NextermApiException('Invalid server response.');
  }

  /// `GET /api/monitoring/integration/:integrationId?timeRange=`.
  Future<Map<String, dynamic>> fetchIntegrationMonitoring(
      String token, String integrationId, String range) async {
    final data = _decode(await _authed(
        'GET', '/monitoring/integration/$integrationId', token,
        query: {'timeRange': range}));
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw NextermApiException('Invalid server response.');
  }

  // -- Snippets & scripts ----------------------------------------------

  /// `GET /api/snippets/all`.
  Future<List<Map<String, dynamic>>> fetchSnippets(
      String token) async {
    final data = _decode(await _authed('GET', '/snippets/all', token));
    if (data is! List) throw NextermApiException('Invalid server response.');
    return data
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// `PUT /api/snippets/` — create.
  Future<void> createSnippet(
      String token, Map<String, dynamic> payload) async {
    _decode(
        await _authed('PUT', '/snippets/', token, body: payload));
  }

  /// `DELETE /api/snippets/:id`.
  Future<void> deleteSnippet(
      String token, int snippetId, int? organizationId) async {
    _decode(await _authed('DELETE', '/snippets/$snippetId', token,
        query: organizationId != null
            ? {'organizationId': '$organizationId'}
            : null));
  }

  /// `GET /api/scripts/` — script library.
  Future<List<Map<String, dynamic>>> fetchScripts(String token,
      {String? search}) async {
    final data = _decode(await _authed('GET', '/scripts/', token,
        query: search != null && search.isNotEmpty
            ? {'search': search}
            : null));
    if (data is! List) throw NextermApiException('Invalid server response.');
    return data
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  // -- Account & login sessions ----------------------------------------

  /// `GET /api/accounts/me`.
  Future<Map<String, dynamic>> fetchMe(String token) async {
    final data = _decode(await _authed('GET', '/accounts/me', token));
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw NextermApiException('Invalid server response.');
  }

  /// `GET /api/sessions/list` — active login sessions.
  Future<List<Map<String, dynamic>>> fetchLoginSessions(
      String token) async {
    final data = _decode(await _authed('GET', '/sessions/list', token));
    if (data is! List) throw NextermApiException('Invalid server response.');
    return data
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// `DELETE /api/sessions/:id` — revoke a login session.
  Future<void> revokeLoginSession(String token, String id) async {
    _decode(await _authed('DELETE', '/sessions/$id', token));
  }

  /// `PATCH /api/accounts/name` — update first/last name
  /// (`server/validations/account.js`: at least one required).
  Future<void> updateProfileName(String token,
      {String? firstName, String? lastName}) async {
    if (firstName == null && lastName == null) {
      throw ArgumentError(
          'First or last name is required.');
    }
    final body = <String, dynamic>{};
    final f = firstName;
    if (f != null) body['firstName'] = f;
    final l = lastName;
    if (l != null) body['lastName'] = l;
    _decode(await _authed('PATCH', '/accounts/name', token, body: body));
  }

  /// `PATCH /api/accounts/password` — change password (min 3 chars).
  Future<void> changePassword(String token, String newPassword) async {
    _decode(await _authed('PATCH', '/accounts/password', token,
        body: {'password': newPassword}));
  }

  /// `GET /api/monitoring/settings/global` — admin only (403 otherwise).
  Future<Map<String, dynamic>> fetchMonitoringGlobalSettings(
      String token) async {
    final data =
        _decode(await _authed('GET', '/monitoring/settings/global', token));
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw NextermApiException('Invalid server response.');
  }

  /// `PATCH /monitoring/settings/global` — admin only.
  /// Only known keys are sent (the GET response may carry read-only
  /// extras like `id`/timestamps that fail server validation).
  Future<void> updateMonitoringGlobalSettings(
      String token, Map<String, dynamic> payload) async {
    const allowed = {
      'statusCheckerEnabled',
      'statusInterval',
      'monitoringEnabled',
      'monitoringInterval',
      'dataRetentionHours',
      'connectionTimeout',
      'batchSize',
    };
    final body = <String, dynamic>{
      for (final e in payload.entries)
        if (allowed.contains(e.key)) e.key: e.value,
    };
    _decode(await _authed('PATCH', '/monitoring/settings/global', token,
        body: body));
  }
}
