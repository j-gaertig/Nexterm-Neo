import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';
import '../../services/session_manager.dart';
import '../../utils/app_icons.dart';

/// Grid tile for the full-screen session overview.
///
/// The card is intentionally close to [ServerGridCard]: a rounded surface,
/// a compact preview at the top, and two lines of metadata underneath. The
/// preview is the last captured frame of the session renderer (or a protocol
/// placeholder before a session has been opened).
class SessionGridCard extends StatelessWidget {
  final AppSession session;
  final Uint8List? preview;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const SessionGridCard({
    super.key,
    required this.session,
    required this.preview,
    required this.onTap,
    required this.onClose,
  });

  String get _protocol {
    if (session.isScriptSession) return 'Script';
    switch (session.type) {
      case ConnectionType.guacamole:
        final protocol = session.server.protocol?.toUpperCase();
        return protocol?.isNotEmpty == true ? protocol! : 'Remote Desktop';
      case ConnectionType.terminal:
        final protocol = session.server.protocol?.toUpperCase();
        return protocol?.isNotEmpty == true ? protocol! : 'SSH';
      case ConnectionType.sftp:
        return 'SFTP';
    }
  }

  IconData get _icon {
    if (session.isScriptSession) return AppIcons.codeBracesBox;
    switch (session.type) {
      case ConnectionType.guacamole:
        return AppIcons.monitorSmall;
      case ConnectionType.terminal:
        return AppIcons.console;
      case ConnectionType.sftp:
        return AppIcons.folderOutline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: '${session.server.name}, $_protocol',
      child: Material(
        color: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: appBorderSide(cs),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPreview(context),
                    // Keeps the close button legible on bright previews.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 48,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.32),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton(
                        onPressed: onClose,
                        tooltip: 'Close session',
                        icon: const Icon(AppIcons.close, size: 16),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.55),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(30, 30),
                          maximumSize: const Size(30, 30),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _protocol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final bytes = preview;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }
    return _SessionPreviewPlaceholder(session: session, icon: _icon);
  }
}

class _SessionPreviewPlaceholder extends StatelessWidget {
  final AppSession session;
  final IconData icon;

  const _SessionPreviewPlaceholder({required this.session, required this.icon});

  ({Color start, Color end, Color foreground}) get _palette {
    if (session.isScriptSession) {
      return (
        start: const Color(0xFF2A2214),
        end: const Color(0xFF161008),
        foreground: const Color(0xFFFFC66D),
      );
    }
    switch (session.type) {
      case ConnectionType.guacamole:
        return (
          start: const Color(0xFF2A1B3D),
          end: const Color(0xFF120B1C),
          foreground: const Color(0xFFC7A0FF),
        );
      case ConnectionType.terminal:
        return (
          start: const Color(0xFF1B2430),
          end: const Color(0xFF0E1116),
          foreground: const Color(0xFF7EE787),
        );
      case ConnectionType.sftp:
        return (
          start: const Color(0xFF1B2A2F),
          end: const Color(0xFF0D1518),
          foreground: const Color(0xFF7FD1E8),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.start, palette.end],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 9,
            left: 10,
            child: Row(
              children: [
                for (final color in const [
                  Color(0xFFFF5F57),
                  Color(0xFFFEBC2E),
                  Color(0xFF28C840),
                ])
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          Center(
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Icon(icon, size: 22, color: palette.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
