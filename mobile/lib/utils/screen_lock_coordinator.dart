import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/screen_lock_screen.dart';
import '../services/screen_lock_service.dart';
import '../utils/auth_manager.dart';
import '../utils/screen_lock_settings.dart';

class ScreenLockCoordinator with WidgetsBindingObserver {
  ScreenLockCoordinator({
    required this.navigatorKey,
    required this.settings,
    required this.authManager,
    required this.service,
    this.onLockShown,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final ScreenLockSettings settings;
  final AuthManager authManager;
  final ScreenLockService service;
  final VoidCallback? onLockShown;

  bool _started = false;
  bool _wasAuthenticated = false;
  bool _backgrounded = false;
  Route<bool>? _lockRoute;

  bool get shouldLock => settings.enabled && authManager.isAuthenticated;

  void start() {
    if (_started) return;
    _started = true;
    _wasAuthenticated = authManager.isAuthenticated;

    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_onSettingsChanged);
    authManager.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLockIfNeeded(initial: true);
    });
  }

  void _onSettingsChanged() {
    if (!shouldLock && _lockRoute != null) {
      _dismissLock();
    }
  }

  void _onAuthChanged() {
    final authenticated = authManager.isAuthenticated;
    if (authenticated == _wasAuthenticated) return;
    _wasAuthenticated = authenticated;

    if (!authenticated) {
      if (_lockRoute != null) _dismissLock();
      return;
    }

    if (settings.enabled) {
      _showLockIfNeeded(initial: true);
    }
  }

  void _dismissLock() {
    final route = _lockRoute;
    _lockRoute = null;
    if (route != null) {
      navigatorKey.currentState?.removeRoute(route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgrounded = true;
      _showLockIfNeeded();
      return;
    }

    if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      _showLockIfNeeded();
    }
  }

  Future<void> _showLockIfNeeded({bool initial = false}) async {
    if (!_started || !shouldLock || _lockRoute != null) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      if (initial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showLockIfNeeded(initial: true);
        });
      }
      return;
    }

    var authenticated = false;
    late final PageRouteBuilder<bool> route;
    route = PageRouteBuilder<bool>(
      opaque: true,
      fullscreenDialog: true,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => ScreenLockScreen(
        service: service,
        onUnlocked: () {
          authenticated = true;
          final currentNavigator = navigatorKey.currentState;
          if (currentNavigator != null) {
            currentNavigator.removeRoute(route);
          }
        },
      ),
      transitionsBuilder: (_, __, ___, child) => child,
    );

    _lockRoute = route;
    onLockShown?.call();
    await navigator.push(route);
    if (identical(_lockRoute, route)) _lockRoute = null;

    if (authenticated || !_started || !shouldLock) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLockIfNeeded();
    });
  }

  void dispose() {
    if (!_started) return;
    _started = false;

    WidgetsBinding.instance.removeObserver(this);
    settings.removeListener(_onSettingsChanged);
    authManager.removeListener(_onAuthChanged);
    unawaited(service.cancel());
  }
}
