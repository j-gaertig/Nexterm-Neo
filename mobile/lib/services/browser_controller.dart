import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:guacamole_common_dart/guacamole_common_dart.dart';

/// State reported by the remote browser (web client `BrowserRenderer`).
class BrowserState {
  final String uri;
  final String title;
  final bool loading;
  final bool canBack;
  final bool canForward;

  const BrowserState({
    this.uri = '',
    this.title = '',
    this.loading = false,
    this.canBack = false,
    this.canForward = false,
  });
}

/// Talks to the remote browser of a "web" session through the Guacamole named
/// pipe `nexterm-browser`: the server reports page state, the app sends
/// commands such as `navigate <url>`, `back`, `forward`, `reload`, `stop`.
class BrowserController extends ChangeNotifier {
  static const String pipeName = 'nexterm-browser';

  GuacClient? _client;
  BrowserState _state = const BrowserState();

  BrowserState get state => _state;

  /// Binds the controller to a (re)connected client.
  void attach(GuacClient client) {
    _client = client;
    client.onpipe = (stream, mimetype, name) {
      if (name != pipeName) return;
      final bytes = <int>[];
      stream.onblob = (data) => bytes.addAll(base64Decode(data));
      stream.onend = () =>
          _handleEvent(utf8.decode(bytes, allowMalformed: true));
    };
  }

  void _handleEvent(String payload) {
    Object? message;
    try {
      message = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (message is! Map || message['event'] != 'state') return;
    _state = BrowserState(
      uri: (message['uri'] as String?) ?? '',
      title: (message['title'] as String?) ?? '',
      loading: message['loading'] == true,
      canBack: message['canBack'] == true,
      canForward: message['canForward'] == true,
    );
    notifyListeners();
  }

  /// Sends a browser command. Returns false when no client is attached.
  bool send(String command) {
    final client = _client;
    if (client == null) return false;
    final stream = client.createPipeStream('application/json', pipeName);
    client.sendBlob(stream.index, base64Encode(utf8.encode(command)));
    client.endStream(stream.index);
    return true;
  }

  void navigate(String address) {
    final value = address.trim();
    if (value.isEmpty) return;
    send('navigate $value');
  }

  void back() => send('back');
  void forward() => send('forward');
  void reload() => send(_state.loading ? 'stop' : 'reload');
}
