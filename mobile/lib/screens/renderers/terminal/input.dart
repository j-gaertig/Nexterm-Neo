part of '../terminal_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TerminalInput on _TerminalRendererState {
  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted || !_terminalFocusNode.hasFocus || event is! KeyDownEvent) {
      return false;
    }

    // Inactive tabs stay alive in the IndexedStack: never consume keys for a
    // session that is not currently visible.
    if (widget.sessionManager.activeSessionId != null &&
        widget.sessionManager.activeSessionId != widget.session.sessionId) {
      return false;
    }

    // Mirrors web `attachCustomKeyEventHandler` while the password hint is
    // visible: Tab/Enter fills, Escape dismisses, Up/Down cycles identities.
    if (_passwordPromptVisible) {
      final logicalKey = event.logicalKey;
      final isTab = logicalKey == LogicalKeyboardKey.tab;
      final isEnter =
          logicalKey == LogicalKeyboardKey.enter ||
          logicalKey == LogicalKeyboardKey.numpadEnter;
      final isEscape = logicalKey == LogicalKeyboardKey.escape;
      final isUp = logicalKey == LogicalKeyboardKey.arrowUp;
      final isDown = logicalKey == LogicalKeyboardKey.arrowDown;
      if (isTab || isEnter) {
        final count = _passwordIdentities.length;
        final current = count > 0
            ? _passwordIdentities[_passwordHintIndex < 0
                  ? 0
                  : (_passwordHintIndex >= count
                        ? count - 1
                        : _passwordHintIndex)]
            : null;
        unawaited(_fillIdentityPassword(current?.id));
        return true;
      }
      if (isEscape) {
        _hidePasswordHint();
        return true;
      }
      if ((isUp || isDown) && _passwordIdentities.length > 1) {
        _cyclePasswordHint(isUp ? -1 : 1);
        return true;
      }
    }

    if (!_ctrlPressed && !_altPressed) {
      return false;
    }

    final key = _hardwareKeyName(event);
    if (key == null) return false;
    _sendTerminalKey(key);
    return true;
  }

  String? _hardwareKeyName(KeyDownEvent event) {
    final character = event.character;
    if (character != null && character.isNotEmpty) return character;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) return 'ESC';
    if (key == LogicalKeyboardKey.tab) return 'TAB';
    if (key == LogicalKeyboardKey.arrowUp) return 'UP';
    if (key == LogicalKeyboardKey.arrowDown) return 'DOWN';
    if (key == LogicalKeyboardKey.arrowLeft) return 'LEFT';
    if (key == LogicalKeyboardKey.arrowRight) return 'RIGHT';
    if (key == LogicalKeyboardKey.home) return 'HOME';
    if (key == LogicalKeyboardKey.end) return 'END';
    if (key == LogicalKeyboardKey.pageUp) return 'PGUP';
    if (key == LogicalKeyboardKey.pageDown) return 'PGDN';
    if (key == LogicalKeyboardKey.f1) return 'F1';
    if (key == LogicalKeyboardKey.f2) return 'F2';
    if (key == LogicalKeyboardKey.f3) return 'F3';
    if (key == LogicalKeyboardKey.f4) return 'F4';
    if (key == LogicalKeyboardKey.f5) return 'F5';
    if (key == LogicalKeyboardKey.f6) return 'F6';
    if (key == LogicalKeyboardKey.f7) return 'F7';
    if (key == LogicalKeyboardKey.f8) return 'F8';
    if (key == LogicalKeyboardKey.f9) return 'F9';
    if (key == LogicalKeyboardKey.f10) return 'F10';
    if (key == LogicalKeyboardKey.f11) return 'F11';
    if (key == LogicalKeyboardKey.f12) return 'F12';
    return null;
  }

  void _startArrowHold(String key) {
    _stopArrowRepeat(key);
    _sendSpecialKey(key);
    _arrowRepeatTimers[key] = Timer(
      _TerminalRendererState._arrowRepeatDelay,
      () => _repeatArrow(key),
    );
  }

  void _repeatArrow(String key) {
    if (!mounted || !_connected || !_terminalFocusNode.hasFocus) {
      _stopArrowRepeat(key);
      return;
    }

    _sendSpecialKey(key);
    _arrowRepeatTimers[key] = Timer(
      _TerminalRendererState._arrowRepeatInterval,
      () => _repeatArrow(key),
    );
  }

  void _stopArrowRepeat(String key) {
    _arrowRepeatTimers.remove(key)?.cancel();
  }

  void _stopAllArrowRepeats() {
    for (final timer in _arrowRepeatTimers.values) {
      timer.cancel();
    }
    _arrowRepeatTimers.clear();
  }

  void _sendSpecialKey(String key) {
    switch (key) {
      case 'CTRL':
        if (mounted) setState(() => _ctrlPressed = !_ctrlPressed);
        return;
      case 'ALT':
        if (mounted) setState(() => _altPressed = !_altPressed);
        return;
      default:
        _sendTerminalKey(key);
        return;
    }
  }

  void _sendFunctionKey(int n) {
    _sendTerminalKey('F$n');
  }

  void _sendTerminalText(String text) {
    // Mirrors web `term.onData`: any user input dismisses the hint first, so
    // a later fill cannot submit into a stale prompt.
    _hidePasswordHint();
    final ctrl = _ctrlPressed;
    final alt = _altPressed;
    _channel?.sink.add(TerminalKeyInput.applyText(text, ctrl: ctrl, alt: alt));
    _clearModifiers();
  }

  void _sendTerminalKey(String key, {bool forceCtrl = false}) {
    // Same as above: toolbar and hardware-key input dismiss the hint.
    _hidePasswordHint();
    final ctrl = forceCtrl || _ctrlPressed;
    final alt = _altPressed;
    final data = TerminalKeyInput.applyKey(key, ctrl: ctrl, alt: alt);
    if (data.isEmpty) return;
    _channel?.sink.add(data);
    _clearModifiers();
  }

  void _clearModifiers() {
    if (_ctrlPressed || _altPressed) {
      if (mounted) {
        setState(() {
          _ctrlPressed = false;
          _altPressed = false;
        });
      } else {
        _ctrlPressed = false;
        _altPressed = false;
      }
    }
  }
}
