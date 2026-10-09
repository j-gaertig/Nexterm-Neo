import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR scanner. [onDetect] receives the raw value; `true` closes
/// the scanner, `false` shows "Invalid QR code" and keeps scanning.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage(
      {super.key,
      required this.title,
      required this.hint,
      required this.onDetect});

  final String title;
  final String hint;
  final bool Function(String value) onDetect;

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final _controller = MobileScannerController();
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    if (widget.onDetect(raw)) {
      _handled = true;
      _controller.stop();
    } else if (_error == null) {
      // Only rebuild on change (camera delivers many frames).
      setState(() => _error = 'Invalid QR code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Text(widget.title,
                      style: tt.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: _controller,
                    builder: (_, state, _) => IconButton(
                      icon: Icon(state.torchState == TorchState.on
                          ? Icons.flash_on
                          : Icons.flash_off),
                      tooltip: 'Toggle flashlight',
                      onPressed: () => _controller.toggleTorch(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_off,
                                    size: 48, color: cs.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(
                                  'Camera unavailable. Please allow camera access in the system settings and try again.',
                                  style: TextStyle(
                                      fontSize: 14, color: cs.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter:
                            _OverlayPainter(cs.primary, Colors.black54),
                        child: const SizedBox.expand(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                children: [
                  Text(widget.hint,
                      style: TextStyle(fontSize: 14, color: cs.outline),
                      textAlign: TextAlign.center),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(fontSize: 13, color: cs.error),
                          textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.borderColor, this.overlayColor);

  final Color borderColor;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width * 0.7;
    final l = (size.width - s) / 2;
    final t = (size.height - s) / 2.5;
    final rrect =
        RRect.fromRectAndRadius(Rect.fromLTWH(l, t, s, s), const Radius.circular(16));
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(rrect)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = overlayColor,
    );

    const cl = 28.0;
    const r = 16.0;
    final rect = rrect.outerRect;
    final p = Paint()
      ..color = borderColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final c in [
      [rect.left, rect.top + cl, rect.left, rect.top + r, rect.left, rect.top, rect.left + r, rect.top, rect.left + cl, rect.top],
      [rect.right - cl, rect.top, rect.right - r, rect.top, rect.right, rect.top, rect.right, rect.top + r, rect.right, rect.top + cl],
      [rect.left, rect.bottom - cl, rect.left, rect.bottom - r, rect.left, rect.bottom, rect.left + r, rect.bottom, rect.left + cl, rect.bottom],
      [rect.right - cl, rect.bottom, rect.right - r, rect.bottom, rect.right, rect.bottom, rect.right, rect.bottom - r, rect.right, rect.bottom - cl],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c[0], c[1])
          ..lineTo(c[2], c[3])
          ..quadraticBezierTo(c[4], c[5], c[6], c[7])
          ..lineTo(c[8], c[9]),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
