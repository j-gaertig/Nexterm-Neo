import 'package:flutter/material.dart';

/// A server tag (`GET /api/tags/list` items `{id, name, color}`).
class TagItem {
  const TagItem({required this.id, required this.name, this.color});

  final int id;
  final String name;
  final String? color;

  factory TagItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse('$rawId');
    if (id == null) {
      throw FormatException('Tag without numeric id: $json');
    }
    return TagItem(
      id: id,
      name: json['name'] as String? ?? 'Tag',
      color: _normalizeColor(json['color']),
    );
  }

  /// Only 6/8-digit hex survives; anything else falls back to null
  /// (short/garbage values would render near-transparent).
  static String? _normalizeColor(Object? raw) {
    if (raw is! String) return null;
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length != 6 && hex.length != 8) return null;
    if (int.tryParse(hex, radix: 16) == null) return null;
    return '#$hex';
  }

  /// Parse the stored color (hex `#rrggbb`/`#aarrggbb` or int).
  Color resolveColor(ColorScheme scheme) {
    final c = color;
    if (c != null) {
      var hex = c.trim();
      if (hex.startsWith('#')) hex = hex.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(value);
    }
    return scheme.primary;
  }
}

/// Small tag chip for server rows/sheets: colored dot + onSurface
/// text (raw tag colors stay readable in both themes).
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.tag, this.dense = false});

  final TagItem tag;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = tag.resolveColor(cs);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(tag.name,
              style: TextStyle(
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
        ],
      ),
    );
  }
}

/// Preset colors for new tags (web TagDialog equivalent).
const List<String> tagColorPresets = [
  '#3F51B5',
  '#2196F3',
  '#009688',
  '#4CAF50',
  '#FF9800',
  '#F44336',
  '#9C27B0',
  '#607D8B',
];
