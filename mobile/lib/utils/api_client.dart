import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class ApiClient {
  static const Duration _timeout = Duration(seconds: 30);
  static const String _appVersion = '1.2.2';
  static String get userAgent =>
      'NextermMobile/$_appVersion (${Platform.operatingSystem}; ${Platform.operatingSystemVersion})';

  static String normalizeBaseUrl(String url) {
    url = url.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://'))
      url = 'https://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (!url.endsWith('/api')) url = '$url/api';
    return url;
  }

  static Map<String, String> _headers(
    Map<String, String>? headers,
    String? token,
  ) => {
    'Content-Type': 'application/json',
    'User-Agent': userAgent,
    ...?headers,
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Resolves the endpoint against [baseUrl], falling back to the active
  /// account's server. Callers that target a specific server (QR login, adding
  /// another instance) must pass [baseUrl] instead of mutating the global one.
  static String _url(String endpoint, String? baseUrl) =>
      '${baseUrl ?? ApiConfig.baseUrl}$endpoint';

  static Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    String? token,
    Duration? timeout,
    String? baseUrl,
  }) => http
      .get(
        Uri.parse(_url(endpoint, baseUrl)),
        headers: _headers(headers, token),
      )
      .timeout(timeout ?? _timeout);

  static Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    String? token,
    Duration? timeout,
    String? baseUrl,
  }) => http
      .post(
        Uri.parse(_url(endpoint, baseUrl)),
        headers: _headers(headers, token),
        body: body != null ? json.encode(body) : null,
      )
      .timeout(timeout ?? _timeout);

  static Future<http.Response> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    String? token,
    Duration? timeout,
    String? baseUrl,
  }) => http
      .put(
        Uri.parse(_url(endpoint, baseUrl)),
        headers: _headers(headers, token),
        body: body != null ? json.encode(body) : null,
      )
      .timeout(timeout ?? _timeout);

  static Future<http.Response> patch(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    String? token,
    Duration? timeout,
    String? baseUrl,
  }) => http
      .patch(
        Uri.parse(_url(endpoint, baseUrl)),
        headers: _headers(headers, token),
        body: body != null ? json.encode(body) : null,
      )
      .timeout(timeout ?? _timeout);

  static Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? headers,
    String? token,
    Duration? timeout,
    String? baseUrl,
  }) => http
      .delete(
        Uri.parse(_url(endpoint, baseUrl)),
        headers: _headers(headers, token),
      )
      .timeout(timeout ?? _timeout);

  static String buildWebSocketUrl(
    String endpoint, {
    Map<String, String>? queryParams,
    String? baseUrl,
  }) {
    final wsUrl = (baseUrl ?? ApiConfig.baseUrl)
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    if (queryParams == null || queryParams.isEmpty) return '$wsUrl$endpoint';
    final query = queryParams.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
    return '$wsUrl$endpoint?$query';
  }
}
