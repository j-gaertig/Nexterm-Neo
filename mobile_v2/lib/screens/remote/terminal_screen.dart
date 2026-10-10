import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:xterm/xterm.dart';

import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/remote/session_opener.dart';
import 'package:nexterm_v2/settings/settings_scope.dart';
import 'package:nexterm_v2/snippets/snippet_models.dart';

import 'terminal_protocol.dart';

/// Map the device cursor preference onto xterm cursor types.
TerminalCursorType _cursorTypeFor(String cursor) {
  switch (cursor) {
    case 'underline':
      return TerminalCursorType.underline;
    case 'bar':
      return TerminalCursorType.verticalBar;
    case 'block':
    default:
      return TerminalCursorType.block;
  }
}

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
      required this.session,
      this.onSessionExpired});

  final NextermApi api;
  final String sessionToken;
  final RemoteSession session;

  /// Called on HTTP 401 so expired sessions return to login.
  final VoidCallback? onSessionExpired;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {  late final Terminal _terminal;
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
        // Second-factor prompt: surface a secure input instead of
        // leaving the code visible as plain terminal text.
        if (frame.isTotpPrompt) _askForTotpCode(generation);
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
    // Stay in "connecting" until the first frame arrives (or an error/
    // close fires) — never claim a live connection upfront.
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

  /// Secure prompt for a TOTP second-factor frame: the code is typed
  /// obscured and submitted with Enter. Guarded per connection
  /// generation so reconnects can't stack dialogs.
  bool _totpDialogOpen = false;

  Future<void> _askForTotpCode(int generation) async {
    if (_totpDialogOpen || !mounted || generation != _generation) return;
    _totpDialogOpen = true;
    final controller = TextEditingController();
    try {
      final code = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Two-factor code'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Authenticator code',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      if (code != null &&
          code.isNotEmpty &&
          mounted &&
          generation == _generation) {
        try {
          _channel?.sink.add('$code\n');
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Session is not connected.')),
            );
          }
        }
      }
    } finally {
      controller.dispose();
      _totpDialogOpen = false;
    }
  }

  /// Password fill (`POST /api/connections/:id/paste-password` with the
  /// session's default identity). Plain paste keeps the prompt open,
  /// paste + Enter submits (e.g. `sudo` prompts).
  Future<void> _pastePasswordMenu() async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste password'),
        content: const Text(
            'Type the session identity password into the terminal.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Paste'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Paste + Enter'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _pastePassword(submit: choice);
  }

  Future<void> _pastePassword({required bool submit}) async {
    try {
      await widget.api.pasteIdentityPassword(
        widget.sessionToken,
        widget.session.sessionId,
        submit: submit,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password pasted.')),
      );
    } on NextermApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } on SessionExpiredException {
      widget.onSessionExpired?.call();
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password fill failed.')),
      );
    }
  }

  /// Snippet picker (web SnippetsMenu equivalent): insert a library
  /// command into the live session, optionally submitting it.
  Future<void> _insertSnippetMenu() async {
    List<Snippet> snippets = [];
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator()),
    ).then((_) => dialogOpen = false);
    void closeProgress() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.pop(context);
      }
    }

    try {
      final raw = await widget.api.fetchSnippets(widget.sessionToken);
      for (final m in raw) {
        try {
          snippets.add(Snippet.fromJson(m));
        } catch (_) {}
      }
    } on SessionExpiredException {
      closeProgress();
      widget.onSessionExpired?.call();
      return;
    } on NextermApiException catch (e) {
      closeProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      closeProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load snippets.')),
      );
      return;
    }
    closeProgress();
    if (!mounted) return;
    if (snippets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No snippets in the library.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Snippet>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text('Insert snippet',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: snippets.length,
                itemBuilder: (_, i) {
                  final snippet = snippets[i];
                  return ListTile(
                    leading: const Icon(Icons.code),
                    title: Text(snippet.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(snippet.command,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, snippet),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(picked.name),
        content: Text(picked.command),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Paste'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Paste + Run'),
          ),
        ],
      ),
    );
    if (submit == null || !mounted) return;
    try {
      _channel?.sink.add(picked.command + (submit ? '\n' : ''));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session is not connected.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final disconnected = !_connected && !_connecting;
    final prefs = SettingsScope.of(context);
    final showPasswordFill = prefs?.terminalPasswordHint ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session.entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (showPasswordFill)
            IconButton(
              icon: const Icon(Icons.key_outlined),
              tooltip: 'Paste identity password',
              onPressed: _connected ? _pastePasswordMenu : null,
            ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Insert snippet',
            onPressed: _connected ? _insertSnippetMenu : null,
          ),
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
                      cursorType: _cursorTypeFor(
                          SettingsScope.of(context)
                                  ?.terminalCursor ??
                              'block'),
                      textStyle: TerminalStyle(
                        fontSize:
                            SettingsScope.of(context)
                                    ?.terminalFontSize ??
                                14,
                      ),
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
