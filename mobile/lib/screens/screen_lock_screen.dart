import 'dart:async';

import 'package:flutter/material.dart';

import '../services/screen_lock_service.dart';
import '../utils/app_icons.dart';

class ScreenLockScreen extends StatefulWidget {
  final ScreenLockService service;
  final VoidCallback onUnlocked;

  const ScreenLockScreen({
    super.key,
    required this.service,
    required this.onUnlocked,
  });

  @override
  State<ScreenLockScreen> createState() => _ScreenLockScreenState();
}

class _ScreenLockScreenState extends State<ScreenLockScreen>
    with WidgetsBindingObserver {
  bool _authenticating = false;
  bool _wasPaused = false;
  bool _suppressNextResume = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState == null ||
          lifecycleState == AppLifecycleState.resumed) {
        _authenticate();
      } else {
        _wasPaused = true;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_authenticating) {
        _suppressNextResume = true;
      } else {
        _wasPaused = true;
      }
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    if (_suppressNextResume) {
      _suppressNextResume = false;
      return;
    }

    if (_wasPaused && !_authenticating) {
      _wasPaused = false;
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating || !mounted) return;

    setState(() {
      _authenticating = true;
      _error = null;
    });

    final result = await widget.service.authenticate(
      reason: 'Authenticate to unlock Nexterm.',
    );

    if (!mounted) return;

    if (result == ScreenLockAuthResult.success) {
      setState(() => _authenticating = false);
      widget.onUnlocked();
      return;
    }

    setState(() {
      _authenticating = false;
      _error = result.message;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_authenticating) {
      unawaited(widget.service.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'favicon.png',
                          width: 88,
                          height: 88,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Nexterm is locked',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use your device screen lock to continue.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _authenticating ? null : _authenticate,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _authenticating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(AppIcons.lockOutline),
                      label: Text(
                        _authenticating
                            ? 'Waiting for authentication...'
                            : 'Unlock',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScreenLockStartupCover extends StatelessWidget {
  const ScreenLockStartupCover({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'favicon.png',
            width: 88,
            height: 88,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
