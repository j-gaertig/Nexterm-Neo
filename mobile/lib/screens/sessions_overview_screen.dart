import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import '../utils/app_icons.dart';
import '../widgets/floating_navigation_bar.dart';
import 'widgets/session_grid_card.dart';

/// Full-screen overview of every open session.
///
/// This is the Sessions destination of the main navigation. It intentionally
/// mirrors the Servers, Monitoring, and Settings pages: a normal page header,
/// scrollable content, and the floating navigation bar. Selecting a card opens
/// that session; closing is handled per card or for all sessions at once
/// through the action next to the navigation bar.
class SessionsOverviewScreen extends StatelessWidget {
  final SessionManager sessionManager;
  final Map<String, Uint8List> previews;
  final ValueChanged<String> onOpenSession;
  final ValueChanged<String> onCloseSession;

  const SessionsOverviewScreen({
    super.key,
    required this.sessionManager,
    required this.previews,
    required this.onOpenSession,
    required this.onCloseSession,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessionManager,
      builder: (context, _) {
        final sessions = sessionManager.sessions;
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(sessions.length, cs, tt),
                Expanded(
                  child: sessions.isEmpty
                      ? _buildEmpty(cs, tt)
                      : _buildGrid(context, sessions),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(int count, ColorScheme cs, TextTheme tt) {
    final countLabel = count == 1
        ? '1 active session'
        : '$count active sessions';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sessions',
            style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              countLabel,
              style: tt.bodySmall?.copyWith(color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<AppSession> sessions) {
    final media = MediaQuery.of(context);
    final textScaler = media.textScaler;
    final bottomPadding =
        media.padding.bottom + FloatingNavigationBarInset.of(context) + 16;

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 16.0;
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - 2 * horizontalPadding - gap) / 2;
        final previewHeight = cardWidth * 10 / 16;
        // Name (13sp), protocol row (11sp), paddings, the small gap, and a
        // little slack for font metrics that differ between platforms.
        final labelHeight =
            textScaler.scale(13) * 1.35 +
            textScaler.scale(11) * 1.35 +
            3 +
            8 +
            10 +
            8;

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            4,
            horizontalPadding,
            bottomPadding,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: previewHeight + labelHeight,
          ),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index];
            return SessionGridCard(
              key: ValueKey('session-card-${session.sessionId}'),
              session: session,
              preview: previews[session.sessionId],
              onTap: () => onOpenSession(session.sessionId),
              onClose: () => onCloseSession(session.sessionId),
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty(ColorScheme cs, TextTheme tt) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(AppIcons.monitorOff, size: 32, color: cs.outline),
            ),
            const SizedBox(height: 20),
            Text(
              'No active sessions',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Sessions you open appear here.',
              style: tt.bodySmall?.copyWith(color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
