part of '../terminal_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TerminalPassword on _TerminalRendererState {
  static bool _sameIdentityIds(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _onTerminalSettingsChanged() {
    // Mirrors web: disabling detection hides the hint and resets tracking.
    if (!widget.terminalSettings.passwordPromptDetection) {
      _promptLine = '';
      _hidePasswordHint();
    } else {
      // Reload so identities added while detection was off appear.
      unawaited(_loadPasswordIdentities());
    }
  }

  /// Loads the server's password identities (web `IdentityContext` equivalent).
  /// Filters the global identity list down to identities attached to this
  /// server whose type carries a password, prioritizing the session identity
  /// exactly like the web client.
  ///
  /// Identities load independently of the detection setting so the key
  /// button can appear immediately when a prompt is detected.
  Future<void> _loadPasswordIdentities() async {
    // Coalesce overlapping requests: at most one load in flight, at most one
    // queued. A queued request whose snapshot was discarded by the guard
    // below is retried from `finally` instead of being dropped silently.
    if (_identityLoadInFlight) {
      _identityLoadQueued = true;
      return;
    }
    _identityLoadInFlight = true;
    _lastIdentityLoadAttempt = DateTime.now();
    // Snapshot request state: discard the result if the session or token
    // changed while the request was in flight.
    final requestToken = widget.token;
    final requestSessionId = widget.session.sessionId;
    final requestServerIds = <int>[...?widget.session.server.identities];
    final requestIdentityId = widget.session.identityId;
    try {
      final all = await ServerEditorService.getIdentities(requestToken);
      if (!mounted) return;
      if (widget.session.sessionId != requestSessionId ||
          widget.token != requestToken) {
        _identityLoadQueued = true;
        return;
      }
      final serverIds = <int>[...requestServerIds];
      final sessionIdentityId = requestIdentityId;
      if (sessionIdentityId != null && !serverIds.contains(sessionIdentityId)) {
        serverIds.insert(0, sessionIdentityId);
      }
      final byId = <String, ManagedIdentity>{
        for (final identity in all) identity.id.toString(): identity,
      };
      final filtered = <PasswordIdentity>[];
      for (final id in serverIds) {
        final match = byId[id.toString()];
        if (match == null) continue;
        if (!passwordIdentityTypes.contains(match.authType)) continue;
        filtered.add(PasswordIdentity(id: match.id, username: match.username));
      }
      final hideHint = filtered.isEmpty && _passwordPromptVisible;
      // Prompt-race healing: the prompt may have arrived while identities
      // were still loading and the terminal may be idle since. Re-evaluate
      // once from the accumulated stream plus the live buffer.
      var showHint = false;
      if (filtered.isNotEmpty &&
          !_passwordPromptVisible &&
          widget.terminalSettings.passwordPromptDetection) {
        final term = widget.session.terminal;
        var candidate = _promptLine;
        if (term != null) {
          final bufferLine = readTerminalPromptLine(term);
          if (bufferLine.trim().isNotEmpty) candidate = bufferLine;
        }
        showHint = isPasswordPrompt(candidate);
      }
      setState(() {
        _passwordIdentities = filtered;
        if (hideHint) {
          _passwordPromptVisible = false;
          _passwordHintIndex = -1;
        } else if (showHint) {
          _passwordPromptVisible = true;
          _passwordHintIndex = 0;
        }
      });
    } catch (_) {
      // Best effort: without identities there is simply no hint. Backdate
      // the attempt so a failed load retries after ~15s, not 60s.
      _lastIdentityLoadAttempt = DateTime.now().subtract(
        const Duration(seconds: 45),
      );
      if (!mounted) return;
      if (widget.session.sessionId != requestSessionId ||
          widget.token != requestToken) {
        _identityLoadQueued = true;
        return;
      }
      final hideHint = _passwordPromptVisible;
      setState(() {
        _passwordIdentities = [];
        if (hideHint) {
          _passwordPromptVisible = false;
          _passwordHintIndex = -1;
        }
      });
    } finally {
      _identityLoadInFlight = false;
      if (_identityLoadQueued && mounted) {
        _identityLoadQueued = false;
        unawaited(_loadPasswordIdentities());
      }
    }
  }

  void _trackPasswordPrompt(String data) {
    // Always accumulate: the prompt may arrive while identities are still
    // loading (or detection is off); evaluation below decides visibility.
    // Bounded to the last 256 code points by `updatePromptLine`.
    _promptLine = updatePromptLine(_promptLine, data);
    if (_passwordIdentities.isEmpty) {
      // An identity may have been added while this terminal was open (the
      // web client reloads live via IdentityContext). Retry at most once a
      // minute instead of polling on every chunk. This runs independently of
      // the detection setting so the list is ready when detection is enabled.
      final last = _lastIdentityLoadAttempt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 60)) {
        unawaited(_loadPasswordIdentities());
      }
      return;
    }
    if (!widget.terminalSettings.passwordPromptDetection) return;
    var candidate = _promptLine;
    final bufferLine = readTerminalPromptLine(_terminal);
    if (bufferLine.trim().isNotEmpty) candidate = bufferLine;
    if (isPasswordPrompt(candidate)) {
      if (!_passwordPromptVisible && mounted) {
        setState(() {
          _passwordPromptVisible = true;
          _passwordHintIndex = 0;
        });
      }
    } else {
      _hidePasswordHint();
    }
  }

  void _hidePasswordHint() {
    if (!_passwordPromptVisible) return;
    if (mounted) {
      setState(() {
        _passwordPromptVisible = false;
        _passwordHintIndex = -1;
      });
    } else {
      _passwordPromptVisible = false;
      _passwordHintIndex = -1;
    }
  }

  void _cyclePasswordHint([int offset = 1]) {
    if (_passwordIdentities.length < 2 || !mounted) return;
    setState(() {
      final count = _passwordIdentities.length;
      _passwordHintIndex = (_passwordHintIndex + offset) % count;
    });
  }

  /// Fills the identity password via `POST /paste-password` (web
  /// `fillIdentityPassword`). `submit` is true while a prompt is visible,
  /// exactly like the web client.
  Future<void> _fillIdentityPassword([dynamic identityId]) async {
    // A double tap can race the hide animation; never send the password twice.
    if (_passwordFillInFlight) return;
    _passwordFillInFlight = true;
    final shouldSubmit = _passwordPromptVisible;
    _hidePasswordHint();
    try {
      await ConnectionService.pasteIdentityPassword(
        token: widget.token,
        sessionId: widget.session.sessionId,
        identityId: identityId == null
            ? null
            : (identityId is int
                  ? identityId
                  : int.tryParse(identityId.toString())),
        submit: shouldSubmit,
      );
    } catch (_) {
      // A failed fill likely means the identity changed server-side; reload
      // so the next prompt shows the current list (web heals via live push).
      unawaited(_loadPasswordIdentities());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to paste password'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      _passwordFillInFlight = false;
    }
    if (mounted) _terminalFocusNode.requestFocus();
  }

  void _onTerminalChanged() => _cursorRevision.value++;
}
