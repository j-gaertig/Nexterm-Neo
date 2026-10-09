import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:xterm/xterm.dart';

import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/remote/session_opener.dart';

import 'terminal_protocol.dart';

/// Full-screen SSH terminal for an opened [RemoteSession].
///
/// Opens `/ws/term` with `sessionToken` + `sessionId`, streams plain-text
/// frames into an xterm [Terminal] and sends user input plus
/// `\x01<cols>,<rows>` resize frames back. A `\x02` marker prefix flags a
/// TOTP second-factor prompt and is stripped before rendering.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen(
      {super.key,
      required this.api,
      required this.sessionToken,
      required this.session});

  final NextermApi api;
  final String sessionToken;
  final RemoteSession session;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  late final TerminalController _controller;
  final FocusNode _focusNode = FocusNode();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  bool _connecting = true;
  bool _connected = false;
  bool _receivedData = false;
  bool _ctrlHeld = false;
  bool _leaving = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _controller = TerminalController();
    _terminal.onOutput = _handleUserInput;
    _terminal.onResize = _handleResize;
    _connect();
  }

  void _handleUserInput(String data) {
    final out = _ctrlHeld ? applyControlModifier(data) : data;
    if (_ctrlHeld && mounted) setState(() => _ctrlHeld = false);
    try {
      _channel?.sink.add(out);
    } catch (_) {
      // Channel already gone; the done handler reports the state.
    }
  }

  void _handleResize(int width, int height, int pixelWidth, int pixelHeight) {
    if (!_connected) return;
    try {
      _channel?.sink.add(encodeTerminalResize(width, height));
    } catch (_) {
      // Best effort; a dead channel is reported via onDone/onError.
    }
  }

  void _connect() {
    final generation = ++_generation;
    unawaited(_subscription?.cancel());
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    setState(() {
      _connecting = true;
      _connected = false;
      _error = null;
    });

    late final IOWebSocketChannel channel;
    try {
      final url = NextermApi.wsUrl(widget.api.baseUrl, '/ws/term', {
        'sessionToken': widget.sessionToken,
        'sessionId': widget.session.sessionId,
      });
      channel = IOWebSocketChannel.connect(Uri.parse(url));
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _connecting = false;
        _connected = false;
        _error = 'Could not open the terminal connection.';
      });
      _notifyError('Could not open the terminal connection.');
      return;
    }
    if (!mounted || generation != _generation) {
      try {
        channel.sink.close();
      } catch (_) {}
      return;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      (event) {
        if (!mounted || generation != _generation) return;
        if (event is! String) return;
        final frame = decodeTerminalFrame(event);
        _terminal.write(frame.text);
        setState(() {
          _connected = true;
          _connecting = false;
          _receivedData = true;
        });
      },
      onError: (Object error) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _connected = false;
          _connecting = false;
          _error = 'Connection error: $error';
        });
        _notifyError('Connection error: $error');
      },
      onDone: () {
        if (!mounted || generation != _generation || _leaving) return;
        final message =
            terminalCloseMessage(channel.closeCode, channel.closeReason);
        setState(() {
          _connected = false;
          _connecting = false;
          _error = message;
        });
        _notifyError(message);
      },
      cancelOnError: false,
    );

    setState(() {
      _connecting = false;
      _connected = true;
    });
    // Initial size handshake so the server can size the pty before the
    // first automatic resize arrives from the layout.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || generation != _generation) return;
      final width = _terminal.viewWidth;
      final height = _terminal.viewHeight;
      try {
        _channel?.sink.add(width > 0 && height > 0
            ? encodeTerminalResize(width, height)
            : encodeTerminalResize(80, 30));
      } catch (_) {}
    });
  }

  void _notifyError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _sendRaw(String data) {
    if (_ctrlHeld && mounted) setState(() => _ctrlHeld = false);
    try {
      _channel?.sink.add(data);
    } catch (_) {}
    _focusNode.requestFocus();
  }

  Future<void> _disconnect() async {
    if (_leaving) return;
    _leaving = true;
    _generation++;
    try {
      // Hibernate (not delete) so the session stays reopenable.
      await widget.api.hibernateConnection(
          widget.sessionToken, widget.session.sessionId);
    } catch (_) {
      // Best effort cleanup; the screen closes either way.
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _leaving = true;
    _generation++;
    unawaited(_subscription?.cancel());
    try {
      _channel?.sink.close();
    } catch (_) {}
    // Best-effort hibernate so the session stays reopenable.
    unawaited(() async {
      try {
        await widget.api.hibernateConnection(
            widget.sessionToken, widget.session.sessionId);
      } catch (_) {}
    }());
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disconnected = !_connected && !_connecting;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session.entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Disconnect',
            onPressed: _disconnect,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_connecting && !_receivedData)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Theme.of(context)
                          .colorScheme
                          .onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onErrorContainer),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Dismiss',
                    color: Theme.of(context)
                        .colorScheme
                        .onErrorContainer,
                    onPressed: () =>
                        setState(() => _error = null),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _focusNode.requestFocus(),
                    child: TerminalView(
                      _terminal,
                      controller: _controller,
                      keyboardType: TextInputType.visiblePassword,
                      focusNode: _focusNode,
                      autofocus: true,
                      deleteDetection: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                  ),
                ),
                if (disconnected)
                  Positioned.fill(
                    child: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.85),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off, size: 48),
                            const SizedBox(height: 12),
                            const Text('Connection lost.'),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reconnect'),
                              onPressed: _connect,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _SpecialKeyBar(
            ctrlHeld: _ctrlHeld,
            connected: _connected,
            onToggleCtrl: () =>
                setState(() => _ctrlHeld = !_ctrlHeld),
            onSend: _sendRaw,
          ),
        ],
      ),
    );
  }
}

/// Toolbar with keys missing from soft keyboards: Esc, Tab, Ctrl modifier,
/// Ctrl+C and the arrow keys.
class _SpecialKeyBar extends StatelessWidget {
  const _SpecialKeyBar({
    required this.ctrlHeld,
    required this.connected,
    required this.onToggleCtrl,
    required this.onSend,
  });

  final bool ctrlHeld;
  final bool connected;
  final VoidCallback onToggleCtrl;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _keyButton(context, 'ESC',
                    onPressed:
                        connected ? () => onSend('\x1b') : null),
                const SizedBox(width: 8),
                _keyButton(context, 'TAB',
                    onPressed:
                        connected ? () => onSend('\t') : null),
                const SizedBox(width: 8),
                _keyButton(
                  context,
                  'CTRL',
                  active: ctrlHeld,
                  onPressed: connected ? onToggleCtrl : null,
                ),
                const SizedBox(width: 8),
                _keyButton(context, '^C',
                    onPressed:
                        connected ? () => onSend('\x03') : null),
                const SizedBox(width: 8),
                _iconKeyButton(context, Icons.arrow_upward, 'Arrow up',
                    onPressed: connected
                        ? () => onSend('\x1b[A')
                        : null),
                const SizedBox(width: 8),
                _iconKeyButton(context, Icons.arrow_downward, 'Arrow down',
                    onPressed: connected
                        ? () => onSend('\x1b[B')
                        : null),
                const SizedBox(width: 8),
                _iconKeyButton(context, Icons.arrow_back, 'Arrow left',
                    onPressed: connected
                        ? () => onSend('\x1b[D')
                        : null),
                const SizedBox(width: 8),
                _iconKeyButton(
                    context, Icons.arrow_forward, 'Arrow right',
                    onPressed: connected
                        ? () => onSend('\x1b[C')
                        : null),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyButton(BuildContext context, String label,
      {bool active = false, VoidCallback? onPressed}) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: active ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          constraints:
              const BoxConstraints(minWidth: 56, minHeight: 44),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? cs.onPrimary : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconKeyButton(
      BuildContext context, IconData icon, String tooltip,
      {VoidCallback? onPressed}) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          constraints:
              const BoxConstraints(minWidth: 48, minHeight: 44),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          child: Center(
            child: Icon(icon,
                size: 18, color: cs.onSurface, semanticLabel: tooltip),
          ),
        ),
      ),
    );
  }
}
