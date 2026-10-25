import 'dart:typed_data';

import '../utils/api_client.dart';

const int maxTerminalImageBytes = 12 * 1024 * 1024;

/// Read a Kitty `t=f`/`t=t` path from the *remote* host through Nexterm's
/// authenticated SFTP API. Returns null for missing sessions and failed
/// requests; the graphics processor then drops the image without disturbing
/// surrounding terminal output.
Future<Uint8List?> fetchRemoteTerminalImage({
  required String token,
  required String sessionId,
  required String path,
}) async {
  if (token.isEmpty || sessionId.isEmpty || path.isEmpty) return null;
  final query = <String, String>{
    'sessionToken': token,
    'sessionId': sessionId,
    'path': path,
    'preview': 'true',
    'graphics': 'true',
    'maxSize': '$maxTerminalImageBytes',
  };
  final encoded = query.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');

  try {
    final response = await ApiClient.get(
      '/entries/sftp?$encoded',
      token: token,
      timeout: const Duration(seconds: 15),
    );
    if (response.statusCode != 200) return null;
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > maxTerminalImageBytes) {
      return null;
    }
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}
