import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kterm/kterm.dart';
import 'package:nexterm/utils/terminal_graphics.dart';

const _st = '\x1b\\';

final _png = Uint8List.fromList(
  img.encodePng(
    img.Image(width: 4, height: 3)..clear(img.ColorRgba8(10, 20, 30, 255)),
  ),
);
final _pngBase64 = base64Encode(_png);

// A noise image that compresses poorly, so its Kitty payload spans several
// 4096-byte chunks just like the real 460x460 fastfetch avatar.
final _largePng = () {
  final image = img.Image(width: 80, height: 80);
  final random = math.Random(42);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(
        x,
        y,
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
        255,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}();

const _avatarPath = '/home/user/.config/fastfetch/avatar.png';

List<String> _splitEvery(String value, int size) {
  final parts = <String>[];
  for (var offset = 0; offset < value.length; offset += size) {
    parts.add(value.substring(offset, math.min(offset + size, value.length)));
  }
  return parts;
}

Future<String> _pushAll(
  TerminalGraphicsProcessor processor,
  Iterable<String> chunks,
) async {
  final output = StringBuffer();
  for (final chunk in chunks) {
    output.write(await processor.push(chunk));
  }
  return output.toString();
}

Future<void> _waitForPlacements(Terminal terminal, int count) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (terminal.graphicsManager.placementCount >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for $count image placements');
}

List<({String control, String payload})> _kittyChunks(String value) {
  return RegExp(r'\x1b_G([^;]*);([^\x1b]*)\x1b\\')
      .allMatches(value)
      .map((match) => (control: match.group(1)!, payload: match.group(2)!))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalGraphicsProcessor Kitty file transport', () {
    test(
      'rewrites the exact fastfetch avatar sequence with one fetch',
      () async {
        final paths = <String>[];
        final processor = TerminalGraphicsProcessor(
          fetchImage: (path) async {
            paths.add(path);
            return _largePng;
          },
        );

        final sequence =
            '\x1b_Ga=T,f=100,t=f,q=2,C=1,c=6,r=3;'
            '${base64Encode(utf8.encode(_avatarPath))}$_st';
        final output = await _pushAll(
          processor,
          _splitEvery('before$sequence\x1b[8Cname', 5),
        );

        expect(paths, [_avatarPath]);
        expect(output, startsWith('before'));
        expect(output, endsWith('\x1b[8Cname'));
        expect(output, isNot(contains('t=f')));
        expect(output, isNot(contains(_avatarPath)));

        final chunks = _kittyChunks(output);
        expect(chunks.length, greaterThan(1));
        expect(chunks.first.control, contains('a=T'));
        expect(chunks.first.control, contains('f=100'));
        expect(chunks.first.control, contains('t=d'));
        expect(chunks.first.control, contains('q=2'));
        expect(chunks.first.control, contains('C=1'));
        expect(chunks.first.control, contains('c=6'));
        expect(chunks.first.control, contains('r=3'));
        expect(chunks.first.control, contains('m=1'));
        expect(chunks[1].control, 'm=1');
        expect(chunks.last.control, 'm=0');
        expect(
          base64Decode(chunks.map((chunk) => chunk.payload).join()),
          _largePng,
        );
      },
    );

    test('coalesces chunked t=f transmissions', () async {
      final paths = <String>[];
      final processor = TerminalGraphicsProcessor(
        fetchImage: (path) async {
          paths.add(path);
          return _png;
        },
      );
      final pathPayload = base64Encode(utf8.encode(_avatarPath));

      final output = await _pushAll(processor, [
        '\x1b_Ga=T,f=100,t=f,m=1,C=1,c=4,r=2;${pathPayload.substring(0, 8)}'
            '$_st',
        '\x1b_Gm=1;${pathPayload.substring(8)}$_st',
        '\x1b_Gm=0;$_st',
        'after',
      ]);

      expect(paths, [_avatarPath]);
      expect(output, endsWith('after'));
      expect(_kittyChunks(output), isNotEmpty);
    });

    test('reassembles direct-data Kitty chunks unchanged', () async {
      final processor = TerminalGraphicsProcessor();
      final half = (_pngBase64.length / 2).floor();
      final input =
          'a'
          '\x1b_Ga=T,f=100,t=d,C=1,c=2,r=1,m=1;${_pngBase64.substring(0, half)}$_st'
          '\x1b_Gm=0;${_pngBase64.substring(half)}$_st'
          'b';

      expect(await _pushAll(processor, _splitEvery(input, 3)), input);
    });

    test('drops t=s and reports fetch failures without leaking text', () async {
      final errors = <Object>[];
      final processor = TerminalGraphicsProcessor(
        fetchImage: (path) async => throw StateError('offline: $path'),
        onError: errors.add,
      );

      final output = await _pushAll(processor, [
        'left\x1b_Ga=T,t=s;c2hhcmVk$_st',
        '\x1b_Ga=T,f=100,t=f,C=1,c=1,r=1;${base64Encode(utf8.encode(_avatarPath))}$_st',
        'right',
      ]);

      expect(output, 'leftright');
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('offline'));
    });
  });

  group('TerminalGraphicsProcessor iTerm2 and SIXEL', () {
    test('rejects invalid Kitty image paths without fetching', () async {
      final paths = <String>[];
      final errors = <Object>[];
      final processor = TerminalGraphicsProcessor(
        fetchImage: (path) async {
          paths.add(path);
          return _png;
        },
        onError: errors.add,
      );
      final withNul = base64Encode(utf8.encode('$_avatarPath\u0000suffix'));
      final tooLong = base64Encode(utf8.encode('/${'a' * 8192}'));
      final output = await _pushAll(processor, [
        'a'
            '\x1b_Ga=T,f=100,t=f,C=1,c=1,r=1;$withNul$_st'
            'b'
            '\x1b_Ga=T,f=100,t=f,C=1,c=1,r=1;$tooLong$_st'
            'c',
      ]);

      expect(output, 'abc');
      expect(paths, isEmpty);
      expect(errors, hasLength(2));
      expect(errors.first.toString(), contains('invalid path'));
    });

    test('converts iTerm2 inline images to Kitty with dimensions', () async {
      final processor = TerminalGraphicsProcessor();
      final input =
          '\x1b]1337;File=inline=1;width=4;height=2;preserveAspectRatio=0:'
          '$_pngBase64\x07';

      final output = await _pushAll(processor, _splitEvery(input, 1));
      final chunks = _kittyChunks(output);

      expect(chunks, hasLength(1));
      expect(chunks.single.control, contains('a=T'));
      expect(chunks.single.control, contains('f=100'));
      expect(chunks.single.control, contains('t=d'));
      expect(chunks.single.control, contains('C=0'));
      expect(chunks.single.control, contains('c=4'));
      expect(chunks.single.control, contains('r=2'));
      expect(chunks.single.control, contains('s=4'));
      expect(chunks.single.control, contains('v=3'));
      expect(base64Decode(chunks.single.payload), _png);
    });

    test('ignores iTerm download-only images and non-image OSC 1337', () async {
      final processor = TerminalGraphicsProcessor();
      final input =
          'a'
          '\x1b]1337;File=inline=0:$_pngBase64\x07'
          '\x1b]1337;CurrentDir=/tmp\x07'
          'b';

      expect(
        await _pushAll(processor, [input]),
        input.replaceFirst(RegExp(r'\x1b\]1337;File=[^\x07]*\x07'), ''),
      );
    });

    test(
      'iTerm2 File defaults to download-only when inline is missing',
      () async {
        final processor = TerminalGraphicsProcessor();
        final input = 'a\x1b]1337;File=width=4:$_pngBase64\x07b';

        expect(await _pushAll(processor, [input]), 'ab');
      },
    );

    test(
      'resolves iTerm2 cell, pixel, percentage, and auto dimensions',
      () async {
        TerminalGraphicsProcessor newProcessor() => TerminalGraphicsProcessor(
          viewportMetrics: () =>
              (columns: 10, rows: 5, cellWidth: 8, cellHeight: 16),
        );

        Future<({String control, String payload})> convert(
          String sizeFields,
        ) async {
          final processor = newProcessor();
          final output = await _pushAll(processor, [
            '\x1b]1337;File=inline=1;$sizeFields:$_pngBase64\x07',
          ]);
          return _kittyChunks(output).single;
        }

        final cells = await convert('preserveAspectRatio=0;width=4;height=2');
        expect(cells.control, contains('c=4'));
        expect(cells.control, contains('r=2'));

        final pixels = await convert('width=32px');
        expect(pixels.control, contains('c=4'));
        expect(pixels.control, isNot(matches(RegExp(r'(^|,)r='))));

        final percent = await convert('width=50%');
        expect(percent.control, contains('c=5'));

        final autoWidth = await convert('width=auto;height=2');
        expect(autoWidth.control, isNot(matches(RegExp(r'(^|,)c='))));
        expect(autoWidth.control, contains('r=2'));

        final aspect = await convert('preserveAspectRatio=1;width=4;height=2');
        expect(aspect.control, contains('c=4'));
        expect(aspect.control, isNot(matches(RegExp(r'(^|,)r='))));

        final stretched = await convert(
          'preserveAspectRatio=0;width=4;height=2',
        );
        expect(stretched.control, contains('c=4'));
        expect(stretched.control, contains('r=2'));
      },
    );

    test('preserves raw RGB Kitty file transmissions for f=24', () async {
      final raw = Uint8List.fromList(<int>[
        255,
        0,
        0,
        0,
        255,
        0,
        0,
        0,
        255,
        255,
        255,
        255,
      ]);
      final processor = TerminalGraphicsProcessor(fetchImage: (_) async => raw);
      final output = await _pushAll(processor, [
        '\x1b_Ga=T,f=24,t=f,C=1,c=2,r=2,s=2,v=2;'
            '${base64Encode(utf8.encode(_avatarPath))}$_st',
      ]);
      final chunk = _kittyChunks(output).single;
      expect(chunk.control, contains('f=24'));
      expect(chunk.control, contains('s=2'));
      expect(chunk.control, contains('v=2'));
      expect(base64Decode(chunk.payload), raw);
    });

    test('decodes SIXEL pixels and converts to PNG', () async {
      final decoded = decodeSixelToImage(
        '#0;2;100;0;0#0~~',
        transparentBackground: true,
      );
      expect(decoded, isNotNull);
      expect(decoded!.width, 2);
      expect(decoded.height, 6);
      final pixel = decoded.getPixel(0, 0);
      expect(pixel.r, 255);
      expect(pixel.g, 0);
      expect(pixel.b, 0);
      expect(pixel.a, 255);

      final processor = TerminalGraphicsProcessor();
      final output = await _pushAll(
        processor,
        _splitEvery('\x1bP0;1;0q#0;2;100;0;0#0~~$_st', 2),
      );
      final chunks = _kittyChunks(output);
      expect(chunks, hasLength(1));
      expect(chunks.single.control, contains('C=0'));
      expect(chunks.single.control, contains('s=2'));
      expect(chunks.single.control, contains('v=6'));
      final converted = img.decodePng(base64Decode(chunks.single.payload));
      expect(converted, isNotNull);
      expect(converted!.width, 2);
      expect(converted.height, 6);
    });

    test('preserves non-SIXEL DCS sequences', () async {
      final processor = TerminalGraphicsProcessor();
      const input = 'a\x1bP\$q544e\x1b\\b';
      expect(await _pushAll(processor, [input]), input);
    });
  });

  group('TerminalGraphicsProcessor output ordering', () {
    test(
      'writes multi-chunk fastfetch output in source order after a slow image',
      () async {
        final terminal = Terminal(maxLines: 1000);
        terminal.resize(80, 24, 8, 16);
        final writes = <String>[];

        final sequence =
            '\x1b_Ga=T,f=100,t=f,q=2,C=1,c=6,r=3;'
            '${base64Encode(utf8.encode(_avatarPath))}$_st';
        const logo1 = '             .-------------------------:';
        const logo2 = '            .+=========================.';
        final source =
            '\r\n'
            '$logo1\r\n'
            '$logo2\r\n'
            '$sequence\x1b[8Cjgaertig\r\n'
            '\r\n'
            '\r\n'
            '╭─ Host test\r\n'
            '├─ CPU test\r\n'
            '╰─ IP 192.0.2.1\r\n';

        final processor = TerminalGraphicsProcessor(
          fetchImage: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return _png;
          },
          onOutput: (text) {
            writes.add(text);
            terminal.write(text);
          },
        );
        addTearDown(processor.dispose);

        final pushes = [
          for (final chunk in _splitEvery(source, 7)) processor.push(chunk),
        ];
        await Future.wait(pushes);
        await _waitForPlacements(terminal, 1);

        final output = writes.join();
        final outputLogo = output.indexOf(logo1);
        final outputHost = output.indexOf('Host test');
        final outputCpu = output.indexOf('CPU test');
        final outputIp = output.indexOf('IP 192.0.2.1');
        expect(outputLogo, greaterThanOrEqualTo(0));
        expect(outputHost, greaterThan(outputLogo));
        expect(outputCpu, greaterThan(outputHost));
        expect(outputIp, greaterThan(outputCpu));

        final lines = [
          for (var i = 0; i < terminal.buffer.lines.length; i++)
            terminal.buffer.lines[i].toString().trimRight(),
        ];
        final logo = lines.indexOf(logo1);
        final host = lines.indexOf('╭─ Host test');
        final cpu = lines.indexOf('├─ CPU test');
        final ip = lines.indexOf('╰─ IP 192.0.2.1');
        expect(logo, greaterThanOrEqualTo(0));
        expect(host, greaterThan(logo));
        expect(cpu, greaterThan(host));
        expect(ip, greaterThan(cpu));
      },
    );
  });
}
