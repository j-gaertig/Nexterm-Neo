import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/nexterm_api.dart';
import '../auth/session_store.dart';
import '../widgets/qr_scanner_page.dart';

/// Login via device code (`POST /api/auth/device/*`, see `API.md` §2).
///
/// Flow: enter server URL → show code (or scan QR) →
/// approve code in the web interface / browser → polling detects approval.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoggedIn});

  final ValueChanged<SessionInfo> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { server, code }

class _LoginScreenState extends State<LoginScreen> {
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _totpController = TextEditingController();
  final _store = SessionStore();

  _Step _step = _Step.server;
  bool _isLoading = false;
  bool _usePassword = false;
  String? _error;
  String? _deviceCode;
  String? _deviceToken;
  String _baseUrl = '';
  Timer? _pollTimer;
  bool _polling = false;
  DateTime? _pollStartedAt;
  int _pollFailures = 0;

  /// Device codes expire after ~10 minutes; stop polling then instead
  /// of looping forever. Backs off after repeated transport errors.
  bool _pollExpired() {
    final started = _pollStartedAt;
    if (started == null) return false;
    return DateTime.now().difference(started) >
        const Duration(minutes: 10);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Please enter a server URL.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = NextermApi(baseUrl: raw);
    try {
      await api.checkServer();
    } on NextermApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
      return;
    }
    final ok = await _createCode(api);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (ok) {
        _baseUrl = api.baseUrl;
        _step = _Step.code;
      }
    });
  }

  /// Creates a device code and starts polling.
  /// Returns whether a code was created.
  Future<bool> _createCode(NextermApi api) async {
    try {
      final code = await api.createDeviceCode();
      if (mounted) {
        setState(() {
          _deviceCode = code.code;
          _deviceToken = code.token;
        });
      }
      _startPolling(api);
      return true;
    } on NextermApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    }
  }

  void _startPolling(NextermApi api) {
    _pollTimer?.cancel();
    _pollStartedAt = DateTime.now();
    _pollFailures = 0;
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _poll(api));
  }

  Future<void> _poll(NextermApi api) async {
    if (_polling) return;
    final pollToken = _deviceToken;
    if (pollToken == null) return;
    if (_pollExpired()) {
      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _error = 'Code expired. Please connect again.';
        _step = _Step.server;
        _deviceCode = null;
        _deviceToken = null;
      });
      return;
    }
    // Back off after repeated transport failures (status 'error').
    // Claim the slot before delaying so the next tick skips instead
    // of polling concurrently.
    if (_pollFailures >= 3) {
      _pollFailures = 0;
      _polling = true;
      try {
        await Future<void>.delayed(const Duration(seconds: 5));
      } finally {
        _polling = false;
      }
      if (!mounted || _deviceToken != pollToken) return;
    }
    _polling = true;
    try {
      final result = await api.pollDeviceCode(pollToken);
      if (!mounted) return;
      if (result.status == 'error') {
        _pollFailures++;
      } else {
        _pollFailures = 0;
      }
      if (result.isAuthorized && result.token != null) {
        final status = await api.checkSession(result.token!);
        if (!mounted) return;
        if (status == SessionStatus.unknown) {
          // Transient blip after approval — keep waiting instead of dead-ending.
          return;
        }
        _pollTimer?.cancel();
        if (status == SessionStatus.invalid) {
          setState(() {
            _error = 'Session was not confirmed. Please connect again.';
            _step = _Step.server;
            _deviceCode = null;
            _deviceToken = null;
          });
          return;
        }
        final label = _urlController.text
            .trim()
            .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
        final session = SessionInfo(
          token: result.token!,
          baseUrl: api.baseUrl,
          label: label.isEmpty ? api.baseUrl : label,
        );
        try {
          await _store.save(session);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _error = 'Session could not be saved.';
            _step = _Step.server;
            _deviceCode = null;
            _deviceToken = null;
          });
          return;
        }
        if (!mounted) return;
        widget.onLoggedIn(session);
      } else if (result.isInvalid) {
        _pollTimer?.cancel();
        setState(() {
          _error = 'Code expired. Please connect again.';
          _step = _Step.server;
          _deviceCode = null;
          _deviceToken = null;
        });
      }
      // pending/error → keep waiting.
    } finally {
      _polling = false;
    }
  }

  /// QR code from the web interface ("link device", `nexterm://devicelink`).
  Future<void> _scanQr() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => QrScannerPage(
          title: 'Scan QR code',
          hint:
              'Open "Link device" in your browser and scan the QR code.',
          onDetect: (raw) {
            try {
              final uri = Uri.parse(raw);
              if (uri.scheme == 'nexterm' && uri.host == 'devicelink') {
                final token = uri.queryParameters['token'];
                final server = uri.queryParameters['server'];
                if (token != null && server != null) {
                  // Guard: scanner may have been closed via back button
                  // in the meantime — then don't pop any route.
                  if (Navigator.canPop(context)) {
                    Navigator.pop(
                        context, {'token': token, 'server': server});
                    return true;
                  }
                }
              }
            } catch (_) {}
            return false;
          },
        ),
      ),
    );
    if (result == null || !mounted) return;
    final token = result['token'];
    final server = result['server'];
    if (token == null || server == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    // Uri.queryParameters is already percent-decoded — no decode needed.
    final api = NextermApi(baseUrl: server);
    try {
      await api.checkServer();
    } on NextermApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _baseUrl = api.baseUrl;
        _urlController.text = server;
        _deviceCode = null;
        _deviceToken = token;
        _step = _Step.code;
        _isLoading = false;
      });
    }
    _startPolling(api);
  }

  /// `$server/link?code=...` opened in the browser for approval.
  Future<void> _openInBrowser() async {
    final code = _deviceCode;
    if (code == null) return;
    // Basispfad erhalten (Server kann unter Subpfad laufen).
    final base = Uri.parse(NextermApi.webBaseUrl(_baseUrl));
    final path = '${base.path.replaceAll(RegExp(r'/+$'), '')}/link';
    final url = base.replace(path: path, queryParameters: {'code': code});
    try {
      final opened =
          await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not open the browser.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not open the browser.')),
        );
      }
    }
  }

  Future<void> _copyCode() async {
    final code = _deviceCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code copied')),
      );
    }
  }

  /// Username/password login (`POST /api/auth/login`, see `API.md` §2).
  Future<void> _loginWithPassword() async {
    final raw = _urlController.text.trim();
    final username = _userController.text.trim();
    final password = _passwordController.text;
    if (raw.isEmpty) {
      setState(() => _error = 'Please enter a server URL.');
      return;
    }
    if (username.isEmpty || password.isEmpty) {
      setState(
          () => _error = 'Please enter username and password.');
      return;
    }
    final totp = int.tryParse(_totpController.text.trim());
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = NextermApi(baseUrl: raw);
    try {
      await api.checkServer();
    } on NextermApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
      return;
    }
    late final String token;
    try {
      token = await api.login(username, password, totpCode: totp);
    } on NextermApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
      return;
    }
    if (!mounted) return;
    final status = await api.checkSession(token);
    if (!mounted) return;
    if (status != SessionStatus.valid) {
      setState(() {
        _error = status == SessionStatus.invalid
            ? 'Login was not accepted. Please try again.'
            : 'Could not verify the session. Please try again.';
        _isLoading = false;
      });
      return;
    }
    final label = raw.replaceFirst(
        RegExp(r'^https?://', caseSensitive: false), '');
    final session = SessionInfo(
      token: token,
      baseUrl: api.baseUrl,
      label: label.isEmpty ? api.baseUrl : label,
    );
    try {
      await _store.save(session);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Session could not be saved.';
          _isLoading = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
    widget.onLoggedIn(session);
  }

  void _back() {
    _pollTimer?.cancel();
    setState(() {
      _step = _Step.server;
      _deviceCode = null;
      _deviceToken = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.terminal,
                      size: 72,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nexterm',
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Server management on the go',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                if (_step == _Step.server) _buildServerStep(cs),
                if (_step == _Step.code) _buildCodeStep(cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerStep(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter your Nexterm server URL to connect.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: 'nexterm.example.com',
            prefixIcon: const Icon(Icons.dns),
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
          keyboardType: TextInputType.url,
          enabled: !_isLoading,
          onFieldSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _isLoading ? null : _connect,
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Connect'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _scanQr,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan QR code'),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => setState(() {
                    _usePassword = !_usePassword;
                    _error = null;
                  }),
          child: Text(_usePassword
              ? 'Use device code instead'
              : 'Use username & password instead'),
        ),
        if (_usePassword) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _userController,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            enabled: !_isLoading,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            enabled: !_isLoading,
            onFieldSubmitted: (_) => _loginWithPassword(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _totpController,
            decoration: const InputDecoration(
              labelText: 'Authenticator code (if enabled)',
              prefixIcon: Icon(Icons.pin_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            enabled: !_isLoading,
            onFieldSubmitted: (_) => _loginWithPassword(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isLoading ? null : _loginWithPassword,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign in'),
          ),
        ],
      ],
    );
  }

  Widget _buildCodeStep(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_deviceCode != null) ...[
          Text(
            'Enter this code in the Nexterm web interface.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _deviceCode!,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 4,
                        color: cs.primary,
                      ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.content_copy),
                  tooltip: 'Copy code',
                ),
              ],
            ),
          ),
        ] else ...[
          Text(
            'QR code detected — waiting for approval…',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Waiting for approval…',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          child: LinearProgressIndicator(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!,
                style: TextStyle(fontSize: 13, color: cs.error),
                textAlign: TextAlign.center),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _back,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _deviceCode == null ? null : _openInBrowser,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in browser'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
