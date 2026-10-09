import 'package:flutter/material.dart';

import 'api/nexterm_api.dart';
import 'auth/session_store.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = await _store.load();
    var keptSession = session;
    if (session != null) {
      // Gespeicherte Session prüfen. Nur bei expliziter Ablehnung (401)
      // verwerfen — bei Netzwerkfehlern (offline) behalten.
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
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final session = _session;
    if (session != null) {
      // Server-Session beenden (Fehler egal), dann lokal löschen.
      await NextermApi(baseUrl: session.baseUrl).logout(session.token);
      await _store.clear();
    }
    if (mounted) setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final light = ColorScheme.fromSeed(seedColor: Colors.indigo);
    final dark = ColorScheme.fromSeed(
        seedColor: Colors.indigo, brightness: Brightness.dark);
    return MaterialApp(
      title: 'Nexterm V2',
      theme: ThemeData(colorScheme: light, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
      home: _loading
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()))
          : _session == null
              ? LoginScreen(
                  onLoggedIn: (session) =>
                      setState(() => _session = session))
              : HomeShell(session: _session!, onLogout: _logout),
    );
  }
}
