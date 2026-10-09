import 'package:flutter/material.dart';

import 'api/nexterm_api.dart';
import 'auth/session_store.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'settings/app_settings.dart';

void main() {
  runApp(const NextermApp());
}

class NextermApp extends StatefulWidget {
  const NextermApp({super.key});

  @override
  State<NextermApp> createState() => _NextermAppState();
}

class _NextermAppState extends State<NextermApp> {
  final _store = SessionStore();
  SessionInfo? _session;
  AppSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final results = await Future.wait([
      _store.load(),
      AppSettings.load(),
    ]);
    final session = results[0] as SessionInfo?;
    final settings = results[1] as AppSettings;
    var keptSession = session;
    if (session != null) {
      // Verify the stored session. Only discard on explicit rejection (401)
      // — keep it on network errors (offline start).
      final status = await NextermApi(baseUrl: session.baseUrl).checkSession(
        session.token,
        timeout: const Duration(seconds: 10),
      );
      if (status == SessionStatus.invalid) {
        await _store.clear();
        keptSession = null;
      }
    }
    if (mounted) {
      setState(() {
        _session = keptSession;
        _settings = settings;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final session = _session;
    if (session != null) {
      // End the server session (errors don't matter), then clear locally.
      await NextermApi(baseUrl: session.baseUrl).logout(session.token);
      await _store.clear();
    }
    if (mounted) setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return AnimatedBuilder(
      animation: settings ?? ChangeNotifier(),
      builder: (context, _) {
        final seed =
            Color(settings?.accentSeed ?? 0xFF3F51B5);
        final light = ColorScheme.fromSeed(seedColor: seed);
        final dark = ColorScheme.fromSeed(
            seedColor: seed, brightness: Brightness.dark);
        return MaterialApp(
          title: 'Nexterm V2',
          theme: ThemeData(colorScheme: light, useMaterial3: true),
          darkTheme:
              ThemeData(colorScheme: dark, useMaterial3: true),
          themeMode: settings?.themeMode ?? ThemeMode.system,
          home: _loading || settings == null
              ? const Scaffold(
                  body:
                      Center(child: CircularProgressIndicator()))
              : _session == null
                  ? LoginScreen(
                      onLoggedIn: (session) => setState(
                          () => _session = session))
                  : HomeShell(
                      session: _session!,
                      onLogout: _logout,
                      settings: settings,
                    ),
        );
      },
    );
  }
}
