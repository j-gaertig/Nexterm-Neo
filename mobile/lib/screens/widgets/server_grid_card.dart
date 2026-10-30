import 'package:flutter/material.dart';

import '../../models/server.dart';
import '../../utils/tag_color.dart';

/// Grid tile that keeps the existing server card language.
///
/// The visual building blocks (icon tile, surface color, radius, tag pill)
/// match the rest of the app. Only the layout is different: cards size to
/// their content and show one tag instead of a clipped tag strip.
class ServerGridCard extends StatelessWidget {
  final Server server;
  final IconData icon;
  final bool dense;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<Tag> onTagTap;

  const ServerGridCard({
    super.key,
    required this.server,
    required this.icon,
    required this.dense,
    required this.onTap,
    required this.onLongPress,
    required this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final offline = !server.isRunning || server.disabled;
    final pve = server.isPve;
    final (bg, fg) = offline
        ? (cs.surfaceContainerHighest, cs.outline)
        : pve
        ? (cs.tertiaryContainer, cs.onTertiaryContainer)
        : (cs.primaryContainer, cs.onPrimaryContainer);

    String? sub;
    final ip = server.ip.trim();
    if (server.disabled) {
      sub = ip.isNotEmpty && ip != 'N/A' ? 'Disabled · $ip' : 'Disabled';
    } else if (pve && server.status != null) {
      sub = ip.isNotEmpty && ip != 'N/A'
          ? '${server.status} · $ip'
          : server.status;
    } else if (ip.isNotEmpty && ip != 'N/A') {
      sub = ip;
    }

    final tags = server.tags ?? const <Tag>[];
    final tag = tags.isNotEmpty ? tags.first : null;
    final extraTags = tags.length - (tag == null ? 0 : 1);
    final statusLabel = server.disabled
        ? 'Disabled'
        : (offline ? 'Offline' : 'Online');

    return Semantics(
      button: true,
      label: '${server.name}, $statusLabel${sub != null ? ', $sub' : ''}',
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: dense ? 32 : 40,
                      height: dense ? 32 : 40,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(dense ? 10 : 12),
                      ),
                      child: Center(
                        child: Icon(icon, color: fg, size: dense ? 17 : 20),
                      ),
                    ),
                    SizedBox(height: dense ? 8 : 10),
                    Text(
                      server.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: offline ? cs.outline : cs.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          sub,
                          style: TextStyle(fontSize: 11, color: cs.outline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                if (tag != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Flexible(
                          child: _TagPill(tag: tag, onTap: () => onTagTap(tag)),
                        ),
                        if (extraTags > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '+$extraTags',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  final Tag tag;
  final VoidCallback onTap;

  const _TagPill({required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = parseTagColor(tag.color, fallback: cs.outline);
    return Semantics(
      button: true,
      label: 'Filter by ${tag.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            tag.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}
