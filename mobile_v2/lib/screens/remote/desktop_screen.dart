import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:guacamole_common_dart/guacamole_common_dart.dart';

import '../../api/nexterm_api.dart';
import '../../remote/session_opener.dart';

/// Pointer interaction mode for the remote desktop.
enum DesktopMouseMode {
  /// Taps and drags act directly at the touched position.
  touch,

  /// Drags move a virtual cursor; taps click at the cursor position.
  cursor,
}

/// Full-screen RDP/VNC desktop viewer backed by the Guacamole tunnel.
///
/// Opens `wss://<host>/api/ws/guac?sessionToken=...&sessionId=...`,
/// renders the remote framebuffer, maps touch to mouse, shows an
/// on-screen keyboard and special keys, and cleans up the tunnel on exit.
class DesktopScreen extends StatefulWidget {
  const DesktopScreen({
    super.key,
    required this.api,
    required this.sessionToken,
    required this.session,
  });

  final NextermApi api;
  final String sessionToken;
  final RemoteSession session;

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  GuacClient? _client;
  bool _connected = false;
  bool _connecting = true;
  bool _receivedFrame = false;
  String? _error;
  DesktopMouseMode _mouseMode = DesktopMouseMode.touch;

  double _mouseX = 0;
  double _mouseY = 0;
  double _displayScale = 1;
  double _displayOffsetX = 0;
  double _displayOffsetY = 0;
  int _displayWidth = 0;
  int _displayHeight = 0;
  double _userScale = 1;
  double _panOffsetX = 0;
  double _panOffsetY = 0;
  double _availableWidth = 0;
  double _availableHeight = 0;
  bool _sizeSent = false;

  final Map<int, Offset> _activePointers = {};
  bool _pinching = false;
  double _pinchBaseDistance = 0;
  double _pinchBaseScale = 1;
  Offset _pinchBaseCenter = Offset.zero;
  Offset _pinchBasePan = Offset.zero;

  static const double _moveThresholdPx = 16;
  static const Duration _clickHold = Duration(milliseconds: 250);
  static const Duration _longPressDelay = Duration(milliseconds: 500);

  Offset? _downPos;
  Timer? _releaseTimer;
  Timer? _longPressTimer;
  bool _moved = false;
  bool _buttonHeld = false;
  bool _userClosing = false;

  bool _ctrlHeld = false;
  bool _altHeld = false;
  bool _shiftHeld = false;
  final _repaint = _RepaintNotifier();

  final FocusNode _keyboardFocus = FocusNode();
  final TextEditingController _keyboardController = TextEditingController();
  bool _keyboardVisible = false;
  String _prevKeyboardText = '';

  static const int _ksEscape = 0xFF1B;
  static const int _ksTab = 0xFF09;
  static const int _ksEnter = 0xFF0D;
  static const int _ksBackspace = 0xFF08;
  static const int _ksDelete = 0xFFFF;
  static const int _ksUp = 0xFF52;
  static const int _ksDown = 0xFF54;
  static const int _ksLeft = 0xFF51;
  static const int _ksRight = 0xFF53;
  static const int _ksHome = 0xFF50;
  static const int _ksEnd = 0xFF57;
  static const int _ksPageUp = 0xFF55;
  static const int _ksPageDown = 0xFF56;
  static const int _ksCtrl = 0xFFE3;
  static const int _ksAlt = 0xFFE9;
  static const int _ksShift = 0xFFE1;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _userClosing = true;
    _releaseTimer?.cancel();
    _longPressTimer?.cancel();
    _keyboardFocus.dispose();
    _keyboardController.dispose();
    _repaint.dispose();
    _client?.disconnect();
    _client?.dispose();
    _client = null;
    // Best-effort hibernate so the session stays reopenable.
    unawaited(() async {
      try {
        await widget.api.hibernateConnection(
            widget.sessionToken, widget.session.sessionId);
      } catch (_) {}
    }());
    super.dispose();
  }

  void _connect() {
    _client?.disconnect();
    _client?.dispose();
    setState(() {
      _error = null;
      _connecting = true;
    });

    final url = NextermApi.wsUrl(widget.api.baseUrl, '/ws/guac', {
      'sessionToken': widget.sessionToken,
      'sessionId': widget.session.sessionId,
    });
    final client = GuacClient(GuacWebSocketTunnel(url));
    _client = client;

    client.display.onflush = () {
      if (!mounted) return;
      if (!_receivedFrame) setState(() => _receivedFrame = true);
      _repaint.notify();
    };
    client.display.onresize = (w, h) {
      if (!mounted) return;
      setState(() {
        _displayWidth = w;
        _displayHeight = h;
      });
      _updateScaling();
    };
    client.onstatechange = (state) {
      if (!mounted || _userClosing) return;
      final connected = state == ClientState.connected ||
          state == ClientState.waiting;
      setState(() {
        _connected = connected;
        if (connected) _connecting = false;
      });
      if (state == ClientState.connected) {
        _sizeSent = false;
        _sendDisplaySize();
      }
      if (state == ClientState.disconnected) {
        if (mounted) {
          setState(() {
            _connected = false;
            _connecting = false;
          });
          _showStatus('Connection lost.', showReconnect: true);
        }
      }
    };
    client.onerror = (status) {
      if (!mounted || _userClosing) return;
      setState(() {
        _error = 'Remote error: ${status.message}';
        _connecting = false;
      });
      _showStatus('Remote error: ${status.message}',
          showReconnect: true);
    };
    // Clipboard sync (web GuacamoleRenderer equivalent): remote copies
    // land on the device clipboard; the tools sheet pastes back.
    client.onclipboard = _onRemoteClipboard;

    try {
      client.connect('');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not connect: $e';
        _connecting = false;
      });
    }
  }

  /// Remote → device clipboard (text only, 256 KB cap).
  void _onRemoteClipboard(GuacInputStream stream, String mimetype) {
    final client = _client;
    if (client == null || !mimetype.startsWith('text/')) {
      client?.sendAck(
          stream.index, 'Unsupported', GuacStatus.unsupported);
      return;
    }
    final buffer = StringBuffer();
    stream.onblob = (data) {
      if (buffer.length < _maxClipboardChars) buffer.write(data);
      client.sendAck(stream.index, 'OK', GuacStatus.success);
    };
    stream.onend = () {
      client.sendAck(stream.index, 'OK', GuacStatus.success);
      if (buffer.isEmpty || !mounted) return;
      try {
        final text = utf8.decode(base64.decode(buffer.toString()));
        if (text.isEmpty) return;
        Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Remote clipboard copied.'),
                duration: Duration(seconds: 2)),
          );
        }
      } catch (_) {}
    };
  }

  static const _maxClipboardChars = 350000; // ~256 KB base64

  /// Device → remote clipboard (tools sheet action).
  Future<void> _pasteClipboardToRemote() async {
    final client = _client;
    if (client == null || !_connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not connected.')),
        );
      }
      return;
    }
    String? text;
    try {
      final data =
          await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    } catch (_) {
      text = null;
    }
    if ((text ?? '').isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty.')),
        );
      }
      return;
    }
    try {
      final stream = client.createClipboardStream('text/plain');
      final encoded = base64.encode(utf8.encode(text!));
      const chunk = 2048;
      for (var i = 0; i < encoded.length; i += chunk) {
        client.sendBlob(stream.index,
            encoded.substring(i, min(i + chunk, encoded.length)));
      }
      client.endStream(stream.index);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Pasted to remote.'),
              duration: Duration(seconds: 2)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paste failed.')),
        );
      }
    }
  }

  void _reconnect() {
    if (_userClosing) return;
    setState(() {
      _error = null;
      _receivedFrame = false;
    });
    _connect();
  }

  void _showStatus(String message, {required bool showReconnect}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: showReconnect
            ? SnackBarAction(label: 'Reconnect', onPressed: _reconnect)
            : null,
      ),
    );
  }

  Future<void> _disconnect() async {
    _userClosing = true;
    _releaseTimer?.cancel();
    _longPressTimer?.cancel();
    if (_buttonHeld) _sendMouseUp();
    _client?.disconnect();
    try {
      // Hibernate (not delete) so the session stays reopenable.
      await widget.api.hibernateConnection(
          widget.sessionToken, widget.session.sessionId);
    } catch (_) {
      // Best effort: the local screen closes regardless.
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _sendDisplaySize() {
    final client = _client;
    if (client == null || _availableWidth <= 0 || _availableHeight <= 0) {
      return;
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    client.sendSize(
      (_availableWidth * dpr).round(),
      (_availableHeight * dpr).round(),
    );
    _sizeSent = true;
  }

  void _onLayoutChanged(double w, double h) {
    final changed = w != _availableWidth || h != _availableHeight;
    _availableWidth = w;
    _availableHeight = h;
    if (changed) _updateScaling();
    if (_connected && w > 0 && h > 0 && (!_sizeSent || changed)) {
      _sendDisplaySize();
    }
  }

  void _updateScaling() {
    if (_displayWidth <= 0 ||
        _displayHeight <= 0 ||
        _availableWidth <= 0 ||
        _availableHeight <= 0) {
      return;
    }
    final fit = (_availableWidth / _displayWidth)
        .clamp(0.0, _availableHeight / _displayHeight)
        .toDouble();
    _displayScale = fit;
    _displayOffsetX =
        (_availableWidth - _displayWidth * fit * _userScale) / 2 +
            _panOffsetX;
    _displayOffsetY =
        (_availableHeight - _displayHeight * fit * _userScale) / 2 +
            _panOffsetY;
  }

  Offset _screenToRemote(Offset pos) {
    final scale = _displayScale * _userScale;
    if (scale <= 0 || _displayWidth <= 0 || _displayHeight <= 0) {
      return Offset.zero;
    }
    return Offset(
      ((pos.dx - _displayOffsetX) / scale)
          .clamp(0, _displayWidth.toDouble()),
      ((pos.dy - _displayOffsetY) / scale)
          .clamp(0, _displayHeight.toDouble()),
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    _activePointers[e.pointer] = e.localPosition;
    if (_activePointers.length == 2) {
      _releaseTimer?.cancel();
      _longPressTimer?.cancel();
      if (_buttonHeld) _sendMouseUp();
      _startPinch();
      return;
    }
    if (_activePointers.length > 2) return;

    _downPos = e.localPosition;
    _moved = false;
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _longPressTimer?.cancel();
    final pos = e.localPosition;
    _longPressTimer = Timer(_longPressDelay, () {
      if (!_moved && _activePointers.length == 1) _rightClick(pos);
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    final prev = _activePointers[e.pointer];
    _activePointers[e.pointer] = e.localPosition;

    if (_pinching && _activePointers.length >= 2) {
      _updatePinch();
      return;
    }
    if (_activePointers.length != 1 || _client == null) return;

    if (!_moved && _downPos != null) {
      final d = e.localPosition - _downPos!;
      if (d.dx * d.dx + d.dy * d.dy > _moveThresholdPx) {
        _moved = true;
        _longPressTimer?.cancel();
      }
    }
    if (!_moved) return;

    if (_mouseMode == DesktopMouseMode.touch) {
      final remote = _screenToRemote(e.localPosition);
      _mouseX = remote.dx;
      _mouseY = remote.dy;
      if (!_buttonHeld) _buttonHeld = true;
      _client!.sendMouseState(
        GuacMouseState(x: _mouseX, y: _mouseY, left: true),
      );
    } else {
      final delta = e.localPosition - (prev ?? e.localPosition);
      final scale = _displayScale * _userScale;
      if (scale > 0) {
        _mouseX = (_mouseX + delta.dx / scale)
            .clamp(0, _displayWidth.toDouble());
        _mouseY = (_mouseY + delta.dy / scale)
            .clamp(0, _displayHeight.toDouble());
      }
      _client!.sendMouseState(
        GuacMouseState(x: _mouseX, y: _mouseY, left: _buttonHeld),
      );
      setState(() {});
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _activePointers.remove(e.pointer);
    _longPressTimer?.cancel();
    if (_pinching) {
      if (_activePointers.isEmpty) _pinching = false;
      return;
    }
    final client = _client;
    if (client == null) return;

    if (_moved) {
      if (_buttonHeld) _sendMouseUp();
      return;
    }

    if (_mouseMode == DesktopMouseMode.touch) {
      final remote = _screenToRemote(e.localPosition);
      _mouseX = remote.dx;
      _mouseY = remote.dy;
    }
    if (!_buttonHeld) {
      _buttonHeld = true;
      client.sendMouseState(
        GuacMouseState(x: _mouseX, y: _mouseY, left: true),
      );
    }
    _releaseTimer?.cancel();
    _releaseTimer = Timer(_clickHold, () {
      if (_buttonHeld) _sendMouseUp();
    });
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _activePointers.remove(e.pointer);
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _longPressTimer?.cancel();
    if (_buttonHeld) _sendMouseUp();
    if (_activePointers.isEmpty) _pinching = false;
  }

  void _sendMouseUp() {
    _buttonHeld = false;
    _client?.sendMouseState(
      GuacMouseState(x: _mouseX, y: _mouseY, left: false),
    );
  }

  void _rightClick(Offset pos) {
    final client = _client;
    if (client == null) return;
    if (_mouseMode == DesktopMouseMode.touch) {
      final remote = _screenToRemote(pos);
      _mouseX = remote.dx;
      _mouseY = remote.dy;
    }
    if (_buttonHeld) _sendMouseUp();
    client.sendMouseState(
      GuacMouseState(x: _mouseX, y: _mouseY, right: true),
    );
    Timer(const Duration(milliseconds: 60), () {
      _client?.sendMouseState(
        GuacMouseState(x: _mouseX, y: _mouseY, right: false),
      );
    });
  }

  void _startPinch() {
    _pinching = true;
    final points = _activePointers.values.toList();
    _pinchBaseCenter = (points[0] + points[1]) / 2;
    _pinchBaseDistance = (points[0] - points[1]).distance;
    _pinchBaseScale = _userScale;
    _pinchBasePan = Offset(_panOffsetX, _panOffsetY);
  }

  void _updatePinch() {
    final points = _activePointers.values.toList();
    if (points.length < 2 || _pinchBaseDistance <= 0) return;
    final center = (points[0] + points[1]) / 2;
    setState(() {
      _userScale = (_pinchBaseScale *
              (points[0] - points[1]).distance / _pinchBaseDistance)
          .clamp(0.5, 4.0);
      _panOffsetX = _pinchBasePan.dx + (center.dx - _pinchBaseCenter.dx);
      _panOffsetY = _pinchBasePan.dy + (center.dy - _pinchBaseCenter.dy);
      _updateScaling();
    });
  }

  void _sendKey(int keysym, {bool pressed = true}) =>
      _client?.sendKeyEvent(pressed ? 1 : 0, keysym);

  void _tapKey(int keysym) {
    _sendKey(keysym);
    Timer(const Duration(milliseconds: 60),
        () => _sendKey(keysym, pressed: false));
  }

  void _toggleModifier(int keysym, bool held, void Function(bool) set) {
    setState(() {
      set(!held);
      _sendKey(keysym, pressed: !held);
    });
  }

  void _releaseModifiers() {
    if (_ctrlHeld) {
      _ctrlHeld = false;
      _sendKey(_ksCtrl, pressed: false);
    }
    if (_altHeld) {
      _altHeld = false;
      _sendKey(_ksAlt, pressed: false);
    }
    if (_shiftHeld) {
      _shiftHeld = false;
      _sendKey(_ksShift, pressed: false);
    }
  }

  void _fitScreen() {
    setState(() {
      _userScale = 1;
      _panOffsetX = 0;
      _panOffsetY = 0;
      _updateScaling();
    });
  }

  void _sendCtrlAltDel() {
    _sendKey(_ksCtrl);
    _sendKey(_ksAlt);
    _tapKey(_ksDelete);
    Timer(const Duration(milliseconds: 120), () {
      _sendKey(_ksAlt, pressed: false);
      _sendKey(_ksCtrl, pressed: false);
      if (mounted) setState(() {});
    });
  }

  void _toggleKeyboard() {
    if (_keyboardVisible) {
      _keyboardFocus.unfocus();
      setState(() => _keyboardVisible = false);
    } else {
      _keyboardFocus.requestFocus();
      setState(() => _keyboardVisible = true);
    }
  }

  void _onKeyboardText() {
    final text = _keyboardController.text;
    if (text.length < _prevKeyboardText.length) {
      final deleted = _prevKeyboardText.length - text.length;
      for (var i = 0; i < deleted; i++) {
        _tapKey(_ksBackspace);
      }
    } else if (text.length > _prevKeyboardText.length) {
      final added = text.substring(_prevKeyboardText.length);
      for (final rune in added.runes) {
        _tapKey(rune < 128 ? rune : rune + 0x01000000);
      }
      _releaseModifiers();
    }
    _prevKeyboardText = text;
  }

  void _showToolsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cs = Theme.of(ctx).colorScheme;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(children: [
                      _sheetAction(
                        icon: Icons.fit_screen,
                        label: 'Fit',
                        cs: cs,
                        onTap: () {
                          Navigator.pop(ctx);
                          _fitScreen();
                        },
                      ),
                      const SizedBox(width: 8),
                      _sheetAction(
                        icon: _keyboardVisible
                            ? Icons.keyboard
                            : Icons.keyboard_outlined,
                        label: 'Keyboard',
                        cs: cs,
                        onTap: () {
                          _toggleKeyboard();
                          setSheetState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      _sheetAction(
                        icon: Icons.content_paste_outlined,
                        label: 'Paste',
                        cs: cs,
                        onTap: () {
                          Navigator.pop(ctx);
                          _pasteClipboardToRemote();
                        },
                      ),
                      const SizedBox(width: 8),
                      _sheetAction(
                        icon: Icons.keyboard,
                        label: 'Ctrl+Alt+Del',
                        cs: cs,
                        onTap: () {
                          Navigator.pop(ctx);
                          _sendCtrlAltDel();
                        },
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      _sheetModifier('CTRL', _ctrlHeld, cs, () {
                        _toggleModifier(
                            _ksCtrl, _ctrlHeld, (v) => _ctrlHeld = v);
                        setSheetState(() {});
                      }),
                      const SizedBox(width: 6),
                      _sheetModifier('ALT', _altHeld, cs, () {
                        _toggleModifier(
                            _ksAlt, _altHeld, (v) => _altHeld = v);
                        setSheetState(() {});
                      }),
                      const SizedBox(width: 6),
                      _sheetModifier('SHIFT', _shiftHeld, cs, () {
                        _toggleModifier(
                            _ksShift, _shiftHeld, (v) => _shiftHeld = v);
                        setSheetState(() {});
                      }),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _sheetKey('ESC', _ksEscape, cs),
                        _sheetKey('TAB', _ksTab, cs),
                        _sheetKey('Enter', _ksEnter, cs),
                        _sheetKey('Back', _ksBackspace, cs),
                        _sheetKey('DEL', _ksDelete, cs),
                        _sheetKey('Up', _ksUp, cs),
                        _sheetKey('Down', _ksDown, cs),
                        _sheetKey('Left', _ksLeft, cs),
                        _sheetKey('Right', _ksRight, cs),
                        _sheetKey('HOME', _ksHome, cs),
                        _sheetKey('END', _ksEnd, cs),
                        _sheetKey('PGUP', _ksPageUp, cs),
                        _sheetKey('PGDN', _ksPageDown, cs),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetAction({
    required IconData icon,
    required String label,
    required ColorScheme cs,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetModifier(
      String label, bool active, ColorScheme cs, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? cs.onPrimary : cs.onSurface,
                )),
          ),
        ),
      ),
    );
  }

  Widget _sheetKey(String label, int keysym, ColorScheme cs) {
    return GestureDetector(
      onTap: () => _tapKey(keysym),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
      ),
    );
  }

  Color _statusColor() {
    final cs = Theme.of(context).colorScheme;
    if (_error != null) return cs.error;
    if (_connected) return cs.tertiary;
    if (_connecting) return cs.primary;
    return cs.outline;
  }

  String _statusLabel() {
    if (_error != null) return 'Error';
    if (_connected) return _receivedFrame ? 'Connected' : 'Loading';
    if (_connecting) return 'Connecting';
    return 'Disconnected';
  }

  @override
  Widget build(BuildContext context) {
    _updateScaling();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.session.entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16)),
            Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(_statusLabel(), style: const TextStyle(fontSize: 12)),
            ]),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _mouseMode == DesktopMouseMode.touch
                ? 'Touch mode'
                : 'Cursor mode',
            icon: Icon(_mouseMode == DesktopMouseMode.touch
                ? Icons.touch_app
                : Icons.mouse),
            onPressed: () => setState(() {
              _mouseMode = _mouseMode == DesktopMouseMode.touch
                  ? DesktopMouseMode.cursor
                  : DesktopMouseMode.touch;
            }),
          ),
          IconButton(
            tooltip: 'Special keys',
            icon: const Icon(Icons.more_vert),
            onPressed: _showToolsSheet,
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.close),
            onPressed: _disconnect,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(builder: (_, constraints) {
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _onLayoutChanged(
                      constraints.maxWidth, constraints.maxHeight));
              return Container(
                color: Colors.black,
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  behavior: HitTestBehavior.opaque,
                  child: ClipRect(
                    child: CustomPaint(
                      painter: _DesktopPainter(
                        client: _client,
                        displayScale: _displayScale,
                        userScale: _userScale,
                        offsetX: _displayOffsetX,
                        offsetY: _displayOffsetY,
                        mouseMode: _mouseMode,
                        mouseX: _mouseX,
                        mouseY: _mouseY,
                        repaint: _repaint,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              );
            }),
          ),
          if (_connecting && !_receivedFrame && _error == null)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Connecting to desktop…',
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: -100,
            top: -100,
            width: 1,
            height: 1,
            child: EditableText(
              controller: _keyboardController,
              focusNode: _keyboardFocus,
              style: const TextStyle(fontSize: 1, color: Colors.transparent),
              cursorColor: Colors.transparent,
              backgroundCursorColor: Colors.transparent,
              onChanged: (_) => _onKeyboardText(),
              onSubmitted: (_) {
                _tapKey(_ksEnter);
                // Reset the baseline first: clearing the controller fires
                // onChanged(''), which would otherwise emit spurious
                // backspaces for the already-sent text.
                _prevKeyboardText = '';
                _keyboardController.value = TextEditingValue.empty;
                _keyboardFocus.requestFocus();
              },
            ),
          ),
          if (_error != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _errorBanner(),
            ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: cs.errorContainer,
      child: Row(children: [
        Icon(Icons.error_outline, color: cs.onErrorContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_error!,
              style: TextStyle(color: cs.onErrorContainer)),
        ),
        TextButton(
          onPressed: _reconnect,
          child: const Text('Reconnect'),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Dismiss',
          onPressed: () => setState(() => _error = null),
          color: cs.onErrorContainer,
        ),
      ]),
    );
  }
}

class _DesktopPainter extends CustomPainter {
  _DesktopPainter({
    required this.client,
    required this.displayScale,
    required this.userScale,
    required this.offsetX,
    required this.offsetY,
    required this.mouseMode,
    required this.mouseX,
    required this.mouseY,
    required _RepaintNotifier repaint,
  }) : super(repaint: repaint);

  final GuacClient? client;
  final double displayScale;
  final double userScale;
  final double offsetX;
  final double offsetY;
  final DesktopMouseMode mouseMode;
  final double mouseX;
  final double mouseY;

  @override
  void paint(Canvas canvas, Size size) {
    final display = client?.display;
    if (display == null) return;
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(displayScale * userScale);

    for (final layer in display.visibleLayers) {
      final image = layer.image;
      if (image == null) continue;
      canvas.save();
      if (layer.index > 0) {
        canvas.translate(layer.x.toDouble(), layer.y.toDouble());
      }
      final paint = layer.opacity < 255
          ? (Paint()
            ..color = Color.fromARGB(layer.opacity, 255, 255, 255))
          : Paint();
      canvas.drawImage(image, Offset.zero, paint);
      canvas.restore();
    }

    if (mouseMode == DesktopMouseMode.cursor) {
      final path = ui.Path()
        ..moveTo(mouseX, mouseY)
        ..lineTo(mouseX, mouseY + 18)
        ..lineTo(mouseX + 5, mouseY + 14)
        ..lineTo(mouseX + 9, mouseY + 22)
        ..lineTo(mouseX + 12, mouseY + 21)
        ..lineTo(mouseX + 8, mouseY + 13)
        ..lineTo(mouseX + 13, mouseY + 12)
        ..close();
      canvas.drawPath(
          path, Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DesktopPainter old) =>
      old.displayScale != displayScale ||
      old.userScale != userScale ||
      old.offsetX != offsetX ||
      old.offsetY != offsetY ||
      old.mouseMode != mouseMode ||
      old.mouseX != mouseX ||
      old.mouseY != mouseY;
}

class _RepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
