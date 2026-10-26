import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failed API request with the server's human-readable error when one was
/// provided. UI code uses [statusCode] to distinguish permission, missing
/// session, and validation errors instead of showing raw status codes.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  factory ApiException.fromResponse(
    http.Response response, {
    String fallback = 'Request failed',
  }) {
    var message = fallback;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final candidate = decoded['message'] ?? decoded['error'];
        if (candidate is String && candidate.trim().isNotEmpty) {
          message = candidate.trim();
        }
      } else if (decoded is String && decoded.trim().isNotEmpty) {
        message = decoded.trim();
      }
    } catch (_) {
      final body = response.body.trim();
      if (body.isNotEmpty && body.length < 300) message = body;
    }
    return ApiException(message, statusCode: response.statusCode);
  }

  @override
  String toString() => message;
}

/// Turns transport and API errors into short messages suitable for a mobile
/// snackbar or inline error state.
String friendlyApiError(
  Object error, {
  String fallback = 'Something went wrong',
}) {
  if (error is ApiException) {
    return error.message;
  }
  if (error is TimeoutException) {
    return 'The server took too long to respond. Please try again.';
  }
  final raw = error.toString();
  if (raw.startsWith('Exception: ')) {
    final trimmed = raw.substring('Exception: '.length).trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  if (raw.contains('SocketException') ||
      raw.contains('Connection refused') ||
      raw.contains('Failed host lookup')) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return fallback;
}
