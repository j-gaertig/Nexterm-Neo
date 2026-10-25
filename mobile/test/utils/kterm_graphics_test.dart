import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kterm/kterm.dart';

const _st = '\x1b\\';

final _png = Uint8List.fromList(
  img.encodePng(
    img.Image(width: 2, height: 2)..clear(img.ColorRgba8(200, 40, 10, 255)),
  ),
);
final _pngBase64 = base64Encode(_png);

Future<void> _waitForPlacements(Terminal terminal, int count) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (terminal.graphicsManager.placementCount >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for $count image placements');
}

String _image({String control = 'a=T,f=100,t=d,C=1,c=2,r=2', String? payload}) {
  return '\x1b_G$control;${payload ?? _pngBase64}$_st';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fastfetch C=1 avatar stays on its line and does not move the cursor',
    () async {
      final terminal = Terminal(maxLines: 100);
      terminal.resize(80, 24, 8, 16);
      final prefix = ' ' * 59;
      final sequence = _image(control: 'a=T,f=100,t=d,q=2,C=1,c=6,r=3');

      terminal.write('$prefix$sequence\x1b[8C');

      await _waitForPlacements(terminal, 1);
      final placement = terminal.graphicsManager.placements.values.single;
      expect(placement.x, 59);
      expect(placement.y, 0);
      expect(placement.width, 6);
      expect(placement.height, 3);
      expect(terminal.buffer.cursorX, 59 + 8);
      expect(terminal.buffer.cursorY, 0);

      terminal.write('jgaertig');
      expect(terminal.buffer.cursorX, 59 + 8 + 8);
      expect(terminal.buffer.cursorY, 0);
    },
  );

  test('C=0 advances the cursor synchronously for following text', () async {
    final terminal = Terminal(maxLines: 100);
    terminal.resize(80, 24, 8, 16);

    terminal.write('12${_image(control: 'a=T,f=100,t=d,C=0,c=3,r=1')}Z');

    await _waitForPlacements(terminal, 1);
    final placement = terminal.graphicsManager.placements.values.single;
    expect(placement.x, 2);
    expect(placement.y, 0);
    expect(placement.width, 3);
    expect(terminal.buffer.cursorX, 6);
    expect(terminal.buffer.cursorY, 0);
  });

  test('places sequential images at their own cursor and size', () async {
    final terminal = Terminal(maxLines: 100);
    terminal.resize(80, 24, 8, 16);

    terminal.write(
      'AB${_image(control: 'a=T,f=100,t=d,C=1,c=2,r=1')}'
      '\r\n\x1b[4C${_image(control: 'a=T,f=100,t=d,C=1,c=3,r=1')}',
    );

    await _waitForPlacements(terminal, 2);
    final placements = terminal.graphicsManager.placements.values.toList()
      ..sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    expect(placements, hasLength(2));
    expect(placements.map((p) => (p.x, p.y, p.width, p.height)).toList(), [
      (2, 0, 2, 1),
      (4, 1, 3, 1),
    ]);
  });

  test('reassembles Kitty direct-data chunks before decoding', () async {
    final terminal = Terminal(maxLines: 100);
    terminal.resize(80, 24, 8, 16);
    final half = (_pngBase64.length / 2).floor();

    terminal.write(
      'AB'
      '\x1b_Ga=T,f=100,t=d,C=1,c=2,r=2,m=1;${_pngBase64.substring(0, half)}$_st'
      '\x1b_Gm=0;${_pngBase64.substring(half)}$_st',
    );

    await _waitForPlacements(terminal, 1);
    final placement = terminal.graphicsManager.placements.values.single;
    expect(placement.x, 2);
    expect(placement.y, 0);
    expect(placement.width, 2);
    expect(placement.height, 2);
    expect(terminal.graphicsManager.getImage(placement.imageId), isNotNull);
  });

  test('decodes raw RGB Kitty images', () async {
    final terminal = Terminal(maxLines: 100);
    terminal.resize(80, 24, 8, 16);
    final rgb = base64Encode(<int>[
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

    terminal.write('\x1b_Ga=T,f=24,t=d,C=1,c=2,r=2,s=2,v=2;$rgb$_st');

    await _waitForPlacements(terminal, 1);
    final placement = terminal.graphicsManager.placements.values.single;
    final image = terminal.graphicsManager.getImage(placement.imageId);
    expect(image, isNotNull);
    expect(image!.width, 2);
    expect(image.height, 2);
  });

  test('notifies listeners after an asynchronous image is placed', () async {
    final terminal = Terminal(maxLines: 100);
    terminal.resize(80, 24, 8, 16);
    var notifiedAfterPlacement = false;
    terminal.addListener(() {
      if (terminal.graphicsManager.placementCount > 0) {
        notifiedAfterPlacement = true;
      }
    });

    terminal.write(_image());

    await _waitForPlacements(terminal, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notifiedAfterPlacement, isTrue);
  });
}
