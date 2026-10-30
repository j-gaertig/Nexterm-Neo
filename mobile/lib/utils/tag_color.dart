import 'package:flutter/material.dart';

/// Parses the hex color stored on a server tag.
///
/// Tag colors are user supplied, so invalid values fall back to [fallback]
/// instead of breaking the surrounding list or grid.
Color parseTagColor(String raw, {required Color fallback}) {
  final value = raw.trim();
  if (value.startsWith('#')) {
    final hex = value.substring(1);
    try {
      if (hex.length == 3) {
        final r = hex[0] + hex[0];
        final g = hex[1] + hex[1];
        final b = hex[2] + hex[2];
        return Color(int.parse('FF$r$g$b', radix: 16));
      }
      if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
      if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    } on FormatException {
      return fallback;
    }
  }
  return fallback;
}
