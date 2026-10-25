import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

typedef TerminalImageFetcher = Future<Uint8List?> Function(String path);

/// Current terminal geometry used to resolve iTerm2 percentage/pixel sizes.
typedef TerminalViewportMetrics = ({
  int columns,
  int rows,
  int cellWidth,
  int cellHeight,
});

/// Streaming graphics preprocessor for the mobile terminal.
///
/// kterm natively understands Kitty APC graphics. This processor rewrites the
/// two other common inline-image protocols into Kitty direct-data APCs and
/// resolves Kitty's remote-file transports through the authenticated SFTP API:
///
/// - Kitty `t=f`/`t=t` (path on the remote host) -> fetched `t=d`
/// - iTerm2 OSC 1337 `File=` -> Kitty `t=d`
/// - SIXEL DCS -> decoded PNG -> Kitty `t=d`
///
/// The processor is serialized: a slow image fetch cannot reorder the text
/// that follows it.
class TerminalGraphicsProcessor {
  TerminalGraphicsProcessor({
    this.fetchImage,
    this.onError,
    this.viewportMetrics,
    this.maxImageBytes = 12 * 1024 * 1024,
    this.maxSequenceBytes = 48 * 1024 * 1024,
  });

  final TerminalImageFetcher? fetchImage;
  final void Function(Object error)? onError;
  final TerminalViewportMetrics? Function()? viewportMetrics;
  final int maxImageBytes;
  final int maxSequenceBytes;

  String _pending = '';
  Future<void> _chain = Future<void>.value();
  _KittyFileGroup? _fileGroup;
  bool _disposed = false;

  Future<String> push(String chunk) {
    if (_disposed) return Future<String>.value('');
    final run = _chain.then((_) => _process(chunk));
    _chain = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  void dispose() {
    _disposed = true;
    _pending = '';
    _fileGroup = null;
  }

  Future<String> _process(String chunk) async {
    if (_disposed) return '';
    _pending += chunk;
    final output = StringBuffer();

    while (_pending.isNotEmpty) {
      final start = _findStart();
      if (start == null) {
        final hold = _trailingMarkerLength(_pending);
        final emitLength = _pending.length - hold;
        output.write(_pending.substring(0, emitLength));
        _pending = _pending.substring(emitLength);
        break;
      }

      if (start.index > 0) {
        output.write(_pending.substring(0, start.index));
        _pending = _pending.substring(start.index);
      }

      if (_pending.length > maxSequenceBytes) {
        _pending = '';
        _fileGroup = null;
        _report(
          Exception('Terminal graphics sequence exceeded the safety limit'),
        );
        break;
      }

      final terminator = _findTerminator(
        _pending,
        start.kind,
        start.introLength,
      );
      if (terminator == null) break;

      final end = terminator.index + terminator.length;
      final sequence = _pending.substring(0, end);
      _pending = _pending.substring(end);

      try {
        output.write(await _handleSequence(sequence, start, terminator.length));
      } catch (error) {
        _fileGroup = null;
        _report(error);
      }
    }

    return output.toString();
  }

  _Marker? _findStart() {
    _Marker? earliest;
    for (final marker in _markers) {
      final index = _pending.indexOf(marker.value);
      if (index < 0) continue;
      if (earliest == null || index < earliest.index) {
        earliest = _Marker(
          index: index,
          value: marker.value,
          kind: marker.kind,
        );
      }
    }
    return earliest;
  }

  _Terminator? _findTerminator(String value, _ProtocolKind kind, int from) {
    for (var i = from; i < value.length; i++) {
      if (value.codeUnitAt(i) == 0x1b &&
          i + 1 < value.length &&
          value.codeUnitAt(i + 1) == 0x5c) {
        return _Terminator(i, 2);
      }
      if (value.codeUnitAt(i) == 0x9c) return _Terminator(i, 1);
      if (kind != _ProtocolKind.dcs && value.codeUnitAt(i) == 0x07) {
        return _Terminator(i, 1);
      }
    }
    return null;
  }

  Future<String> _handleSequence(
    String sequence,
    _Marker start,
    int terminatorLength,
  ) async {
    final body = sequence.substring(
      start.introLength,
      sequence.length - terminatorLength,
    );

    switch (start.kind) {
      case _ProtocolKind.kitty:
        return _handleKitty(body);
      case _ProtocolKind.iterm:
        return _handleIterm(body);
      case _ProtocolKind.dcs:
        return _handleDcs(body);
    }
  }

  Future<String> _handleKitty(String body) async {
    final semicolon = body.indexOf(';');
    final control = semicolon < 0 ? body : body.substring(0, semicolon);
    final payload = semicolon < 0 ? '' : body.substring(semicolon + 1);
    final args = _parseControl(control);
    final transport = args['t'];

    final group = _fileGroup;
    if (group != null) {
      if (group.dropped) {
        if (args['m'] != '1') _fileGroup = null;
        return '';
      }
      group.payload.write(payload);
      if (group.payload.length > maxSequenceBytes) {
        group.dropped = true;
        group.payload.clear();
        if (args['m'] != '1') _fileGroup = null;
        return '';
      }
      if (args['m'] == '1') {
        if (args.isNotEmpty) group.controlArgs.addAll(args);
        return '';
      }
      _fileGroup = null;
      return _rewriteFileTransmission(
        group.controlArgs,
        group.payload.toString(),
      );
    }

    if (transport != 'f' && transport != 't') {
      // t=s lives in the terminal's shared-memory namespace and cannot be
      // resolved through SFTP. Drop it rather than displaying base64 garbage.
      if (transport == 's') return '';
      return _reassembleKitty(control, payload);
    }

    if (args['m'] == '1') {
      final buffered = _KittyFileGroup(
        controlArgs: Map<String, String>.from(args),
      )..payload.write(payload);
      _fileGroup = buffered;
      return '';
    }

    return _rewriteFileTransmission(args, payload);
  }

  String _reassembleKitty(String control, String payload) {
    if (payload.isEmpty) return '\x1b_G$control\x1b\\';
    return '\x1b_G$control;$payload\x1b\\';
  }

  Future<String> _rewriteFileTransmission(
    Map<String, String> args,
    String payload,
  ) async {
    final fetcher = fetchImage;
    if (fetcher == null) {
      throw StateError(
        'Remote terminal images are unavailable for this session',
      );
    }

    final path = _decodeBase64Utf8(payload);
    if (path.isEmpty) {
      throw const FormatException(
        'Kitty file transmission did not contain a path',
      );
    }
    if (path.length > _maxImagePathLength || path.contains('\u0000')) {
      throw const FormatException(
        'Kitty file transmission contains an invalid path',
      );
    }

    final bytes = await fetcher(path);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Remote terminal image is empty: $path');
    }
    if (bytes.length > maxImageBytes) {
      throw StateError('Remote terminal image exceeds the size limit: $path');
    }

    final requestedFormat = args['f'];
    final detected = _detectImageFormat(bytes);
    var format = detected?.format;
    if (requestedFormat == '24' || requestedFormat == '32') {
      // Raw RGB/RGBA has no magic bytes; the original s/v dimensions remain
      // valid and kterm can decode it directly.
      format = requestedFormat;
    }
    if (format == null) {
      throw FormatException('Unsupported remote terminal image format: $path');
    }

    final rewritten = Map<String, String>.from(args)
      ..remove('t')
      ..remove('m')
      ..remove('f')
      ..['f'] = format
      ..['t'] = 'd';

    // If the producer relied on natural pixel dimensions, expose them so
    // kterm can compute the cursor cell movement synchronously.
    if (!rewritten.containsKey('c') &&
        !rewritten.containsKey('r') &&
        !rewritten.containsKey('s') &&
        !rewritten.containsKey('v')) {
      final dimensions = _imageDimensions(bytes);
      if (dimensions != null) {
        rewritten['s'] = '${dimensions.width}';
        rewritten['v'] = '${dimensions.height}';
      }
    }

    return _formatKitty(rewritten, base64Encode(bytes));
  }

  String _handleIterm(String body) {
    final colon = body.indexOf(':');
    if (colon < 0) return '';
    final header = body.substring(0, colon);
    final payload = body.substring(colon + 1);
    final fields = <String, String>{};
    for (final part in header.split(';')) {
      final equals = part.indexOf('=');
      if (equals > 0) {
        fields[part.substring(0, equals).trim()] = part
            .substring(equals + 1)
            .trim();
      }
    }
    // iTerm2 defaults to a download-only File message. Rendering must require
    // an explicit inline=1, just like the iTerm2 client and xterm.js addon.
    if (fields['inline'] != '1') return '';

    final bytes = _decodeBase64Bytes(payload);
    if (bytes.isEmpty) return '';
    if (bytes.length > maxImageBytes) {
      throw StateError('iTerm2 terminal image exceeds the size limit');
    }
    final detected = _detectImageFormat(bytes);
    if (detected == null) return '';

    final dimensions = _imageDimensions(bytes);
    final args = <String, String>{
      'a': 'T',
      'f': detected.format,
      't': 'd',
      'C': '0',
    };

    final metrics = viewportMetrics?.call();
    final widthCells = _itermCells(fields['width'], metrics, horizontal: true);
    final heightCells = _itermCells(
      fields['height'],
      metrics,
      horizontal: false,
    );
    final preserveAspect = fields['preserveAspectRatio'] != '0';
    if (widthCells != null) args['c'] = '$widthCells';
    if (heightCells != null && !(preserveAspect && widthCells != null)) {
      args['r'] = '$heightCells';
    }
    if (dimensions != null) {
      args['s'] = '${dimensions.width}';
      args['v'] = '${dimensions.height}';
    }

    return _formatKitty(args, base64Encode(bytes));
  }

  String _handleDcs(String body) {
    final match = RegExp(r'^([0-9;]*)q').firstMatch(body);
    if (match == null) {
      // Not SIXEL. Preserve other DCS sequences (terminal queries, tmux
      // passthrough) exactly as they arrived.
      return '\x1bP$body\x1b\\';
    }

    final params = match.group(1) ?? '';
    final p2 = params.split(';').length > 1
        ? int.tryParse(params.split(';')[1]) ?? 0
        : 0;
    final payload = body.substring(match.end);
    if (payload.length > maxImageBytes) {
      throw StateError('SIXEL terminal image exceeds the size limit');
    }
    final image = decodeSixelToImage(payload, transparentBackground: p2 == 1);
    if (image == null) return '';

    final png = img.encodePng(image);
    final args = <String, String>{
      'a': 'T',
      'f': '100',
      't': 'd',
      'C': '0',
      's': '${image.width}',
      'v': '${image.height}',
    };
    return _formatKitty(args, base64Encode(png));
  }

  String _formatKitty(Map<String, String> args, String payload) {
    if (payload.isEmpty) return '';
    final control = _serializeControl(args, remove: const {'m'});
    const chunkSize = 4096;
    if (payload.length <= chunkSize) {
      return '\x1b_G$control,m=0;$payload\x1b\\';
    }

    final output = StringBuffer();
    for (var offset = 0; offset < payload.length; offset += chunkSize) {
      final end = math.min(offset + chunkSize, payload.length);
      final part = payload.substring(offset, end);
      final more = end < payload.length;
      if (offset == 0) {
        output.write('\x1b_G$control,m=${more ? 1 : 0};$part\x1b\\');
      } else {
        output.write('\x1b_Gm=${more ? 1 : 0};$part\x1b\\');
      }
    }
    return output.toString();
  }

  void _report(Object error) {
    onError?.call(error);
  }
}

class _Marker {
  const _Marker({required this.index, required this.value, required this.kind});
  final int index;
  final String value;
  final _ProtocolKind kind;
  int get introLength => value.length;
}

class _Terminator {
  const _Terminator(this.index, this.length);
  final int index;
  final int length;
}

enum _ProtocolKind { kitty, iterm, dcs }

class _KittyFileGroup {
  _KittyFileGroup({required this.controlArgs});
  final Map<String, String> controlArgs;
  final StringBuffer payload = StringBuffer();
  bool dropped = false;
}

const _maxImagePathLength = 8192;

const _markers = <_MarkerSeed>[
  _MarkerSeed('\x1b_G', _ProtocolKind.kitty),
  _MarkerSeed('\u009dG', _ProtocolKind.kitty),
  _MarkerSeed('\x1b]1337;File=', _ProtocolKind.iterm),
  _MarkerSeed('\u009d1337;File=', _ProtocolKind.iterm),
  _MarkerSeed('\x1bP', _ProtocolKind.dcs),
  _MarkerSeed('\u009dP', _ProtocolKind.dcs),
];

class _MarkerSeed {
  const _MarkerSeed(this.value, this.kind);
  final String value;
  final _ProtocolKind kind;
}

int _trailingMarkerLength(String value) {
  var hold = 0;
  for (final marker in _markers) {
    final max = math.min(marker.value.length - 1, value.length);
    for (var length = 1; length <= max; length++) {
      if (value.endsWith(marker.value.substring(0, length))) {
        hold = math.max(hold, length);
      }
    }
  }
  return hold;
}

Map<String, String> _parseControl(String control) {
  final args = <String, String>{};
  for (final part in control.split(',')) {
    if (part.isEmpty) continue;
    final equals = part.indexOf('=');
    if (equals < 0) {
      args[part] = '';
    } else {
      args[part.substring(0, equals)] = part.substring(equals + 1);
    }
  }
  return args;
}

String _serializeControl(
  Map<String, String> args, {
  Set<String> remove = const {},
}) {
  final parts = <String>[];
  for (final entry in args.entries) {
    if (remove.contains(entry.key)) continue;
    parts.add('${entry.key}=${entry.value}');
  }
  return parts.join(',');
}

/// Resolve an iTerm2 `width`/`height` field to a cell count.
///
/// Plain numbers are cell counts, `Npx` is pixels, and `N%` is relative to the
/// terminal's pixel size. `auto`, missing values, and values we cannot resolve
/// without terminal metrics return null (natural size / aspect preserved).
int? _itermCells(
  String? value,
  TerminalViewportMetrics? metrics, {
  required bool horizontal,
}) {
  if (value == null) return null;
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty || trimmed == 'auto') return null;

  final match = RegExp(r'^(\d+)(px|%)?$').firstMatch(trimmed);
  if (match == null) return null;
  final amount = int.tryParse(match.group(1)!);
  if (amount == null || amount <= 0) return null;

  final cellPixels = horizontal ? metrics?.cellWidth : metrics?.cellHeight;
  if (cellPixels == null || cellPixels <= 0) {
    return match.group(2) == null ? amount.clamp(1, 10000) : null;
  }

  final terminalPixels = horizontal
      ? (metrics!.columns * metrics.cellWidth)
      : (metrics!.rows * metrics.cellHeight);
  final targetPixels = switch (match.group(2)) {
    'px' => amount,
    '%' => terminalPixels * amount / 100,
    _ => amount * cellPixels.toDouble(),
  };
  return (targetPixels / cellPixels).round().clamp(1, 10000);
}

Uint8List _decodeBase64Bytes(String payload) {
  final normalized = payload.replaceAll(RegExp(r'\s'), '');
  if (normalized.isEmpty) return Uint8List(0);
  final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
  try {
    return base64Decode(padded);
  } on FormatException {
    return Uint8List(0);
  }
}

String _decodeBase64Utf8(String payload) {
  final bytes = _decodeBase64Bytes(payload);
  if (bytes.isEmpty) return '';
  return utf8.decode(bytes, allowMalformed: true);
}

({String format, String mime})? _detectImageFormat(Uint8List bytes) {
  if (bytes.length < 4) return null;
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return (format: '100', mime: 'image/png');
  }
  if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
    return (format: '98', mime: 'image/jpeg');
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return (format: '50', mime: 'image/gif');
  }
  return null;
}

({int width, int height})? _imageDimensions(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return (width: decoded.width, height: decoded.height);
  } catch (_) {
    return null;
  }
}

/// Decode a SIXEL payload into a PNG-ready image.
///
/// The parser is intentionally self-contained (the `image` package does not
/// decode SIXEL). A first pass determines the canvas size, a second pass draws
/// into a preallocated RGBA image. Unset pixels stay transparent when the DCS
/// P2 parameter requests transparency; otherwise they are black.
img.Image? decodeSixelToImage(
  String payload, {
  bool transparentBackground = false,
  int maxDimension = 4096,
  int maxPixels = 16 * 1024 * 1024,
}) {
  final size = _runSixel(payload, null, maxDimension, maxPixels);
  if (size == null || size.width <= 0 || size.height <= 0) return null;
  if (size.width > maxDimension ||
      size.height > maxDimension ||
      size.width * size.height > maxPixels) {
    return null;
  }

  final image = img.Image(
    width: size.width,
    height: size.height,
    numChannels: 4,
  );
  img.fill(
    image,
    color: transparentBackground
        ? img.ColorRgba8(0, 0, 0, 0)
        : img.ColorRgba8(0, 0, 0, 255),
  );
  final drawn = _runSixel(payload, image, maxDimension, maxPixels);
  return drawn == null ? null : image;
}

({int width, int height})? _runSixel(
  String payload,
  img.Image? target,
  int maxDimension,
  int maxPixels,
) {
  final palette = List<int>.generate(256, _vt340Color);
  var currentColor = 0;
  var x = 0;
  var y = 0;
  var maxX = 0;
  var maxDrawnY = -1;
  int? rasterWidth;
  int? rasterHeight;
  var index = 0;

  bool inBounds(int px, int py) =>
      px >= 0 && py >= 0 && px < maxDimension && py < maxDimension;

  void plot(int px, int py, int color) {
    if (!inBounds(px, py)) return;
    maxX = math.max(maxX, px + 1);
    maxDrawnY = math.max(maxDrawnY, py);
    if (target != null && px < target.width && py < target.height) {
      target.setPixelRgba(
        px,
        py,
        (color >> 16) & 0xff,
        (color >> 8) & 0xff,
        color & 0xff,
        (color >> 24) & 0xff,
      );
    }
  }

  while (index < payload.length) {
    final code = payload.codeUnitAt(index);

    if (code == 0x22) {
      // Raster attributes: "Pan;Pad;Ph;Pv
      index++;
      final values = <int>[];
      var value = 0;
      var haveValue = false;
      while (index < payload.length) {
        final c = payload.codeUnitAt(index);
        if (c >= 0x30 && c <= 0x39) {
          value = value * 10 + (c - 0x30);
          haveValue = true;
          if (value > maxPixels) return null;
          index++;
        } else if (c == 0x3b) {
          values.add(haveValue ? value : 0);
          value = 0;
          haveValue = false;
          index++;
          if (values.length >= 4) break;
        } else {
          break;
        }
      }
      if (haveValue && values.length < 4) values.add(value);
      if (values.length >= 4) {
        rasterWidth = values[2];
        rasterHeight = values[3];
      }
      continue;
    }

    if (code == 0x23) {
      // Color introducer: #index[;2;r;g;b | ;1;h;l;s]
      index++;
      var colorIndex = 0;
      var haveIndex = false;
      while (index < payload.length) {
        final c = payload.codeUnitAt(index);
        if (c >= 0x30 && c <= 0x39) {
          colorIndex = colorIndex * 10 + (c - 0x30);
          haveIndex = true;
          index++;
        } else {
          break;
        }
      }
      if (haveIndex) currentColor = colorIndex.clamp(0, 255);
      if (index < payload.length && payload.codeUnitAt(index) == 0x3b) {
        index++;
        final values = <int>[];
        var value = 0;
        var haveValue = false;
        while (index < payload.length) {
          final c = payload.codeUnitAt(index);
          if (c >= 0x30 && c <= 0x39) {
            value = value * 10 + (c - 0x30);
            haveValue = true;
            index++;
          } else if (c == 0x3b) {
            values.add(haveValue ? value : 0);
            value = 0;
            haveValue = false;
            index++;
            if (values.length >= 4) break;
          } else {
            break;
          }
        }
        if (haveValue && values.length < 4) values.add(value);
        if (values.length >= 4) {
          final mode = values[0];
          if (mode == 2) {
            palette[currentColor] =
                0xff000000 |
                (_percent(values[1]) << 16) |
                (_percent(values[2]) << 8) |
                _percent(values[3]);
          } else if (mode == 1) {
            palette[currentColor] = _hlsToRgba(values[1], values[2], values[3]);
          }
        }
      }
      continue;
    }

    if (code == 0x21) {
      // Repeat introducer: !count<sixel char>
      index++;
      var count = 0;
      while (index < payload.length) {
        final c = payload.codeUnitAt(index);
        if (c >= 0x30 && c <= 0x39) {
          count = count * 10 + (c - 0x30);
          if (count > maxPixels) return null;
          index++;
        } else {
          break;
        }
      }
      if (index < payload.length) {
        final c = payload.codeUnitAt(index);
        index++;
        if (c >= 0x3f && c <= 0x7e) {
          final bits = c - 0x3f;
          final color = palette[currentColor];
          for (var repeat = 0; repeat < count; repeat++) {
            for (var bit = 0; bit < 6; bit++) {
              if (bits & (1 << bit) != 0) plot(x, y + bit, color);
            }
            x++;
            if (x >= maxDimension) return null;
          }
        }
      }
      continue;
    }

    if (code == 0x24) {
      // Carriage return
      x = 0;
      index++;
      continue;
    }

    if (code == 0x2d) {
      // Next sixel band
      x = 0;
      y += 6;
      if (y >= maxDimension) return null;
      index++;
      continue;
    }

    if (code >= 0x3f && code <= 0x7e) {
      final bits = code - 0x3f;
      final color = palette[currentColor];
      for (var bit = 0; bit < 6; bit++) {
        if (bits & (1 << bit) != 0) plot(x, y + bit, color);
      }
      x++;
      if (x >= maxDimension) return null;
      index++;
      continue;
    }

    // Whitespace, separators, and unsupported control characters.
    index++;
  }

  final width = rasterWidth != null && rasterWidth > 0 ? rasterWidth : maxX;
  final height = rasterHeight != null && rasterHeight > 0
      ? rasterHeight
      : (maxDrawnY >= 0 ? maxDrawnY + 1 : 0);
  if (width > maxDimension || height > maxDimension) return null;
  return (width: width, height: height);
}

int _percent(int value) {
  final clamped = value.clamp(0, 100);
  return (clamped * 255 / 100).round().clamp(0, 255);
}

int _hlsToRgba(int hue, int lightness, int saturation) {
  final l = lightness.clamp(0, 100) / 100.0;
  final s = saturation.clamp(0, 100) / 100.0;
  final h = (hue % 360) / 360.0;

  double hueToRgb(double p, double q, double t) {
    var value = t;
    if (value < 0) value += 1;
    if (value > 1) value -= 1;
    if (value < 1 / 6) return p + (q - p) * 6 * value;
    if (value < 1 / 2) return q;
    if (value < 2 / 3) return p + (q - p) * (2 / 3 - value) * 6;
    return p;
  }

  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  final r = (hueToRgb(p, q, h + 1 / 3) * 255).round().clamp(0, 255);
  final g = (hueToRgb(p, q, h) * 255).round().clamp(0, 255);
  final b = (hueToRgb(p, q, h - 1 / 3) * 255).round().clamp(0, 255);
  return 0xff000000 | (r << 16) | (g << 8) | b;
}

int _vt340Color(int index) {
  const colors = <int>[
    0xff000000, // black
    0xff0000ff, // blue
    0xffff0000, // red
    0xff00ff00, // green
    0xffff00ff, // magenta
    0xff00ffff, // cyan
    0xffffff00, // yellow
    0xff808080, // grey 50%
    0xff404040, // grey 25%
    0xff8080ff, // light blue
    0xffff8080, // light red
    0xff80ff80, // light green
    0xffff80ff, // light magenta
    0xff80ffff, // light cyan
    0xffffff80, // light yellow
    0xffffffff, // white
  ];
  if (index < colors.length) return colors[index];
  return 0xff000000;
}
