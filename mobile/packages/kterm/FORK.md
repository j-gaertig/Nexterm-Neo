# Nexterm fork of kterm

Upstream: <https://github.com/lbp0200/kterm.dart> 1.6.0, MIT licensed (see
`LICENSE`).

This vendored copy fixes terminal graphics behaviour needed to render
fastfetch and other inline-image producers correctly:

- Preserve the first chunk's Kitty control data and merge continuation args
  (`m=1` chunks previously replaced `a`/`f`/`c`/`r` with an empty map).
- Accumulate base64 payload text across `m=1` chunks and decode it once at the
  final chunk, since chunk boundaries are not guaranteed to be 4-byte aligned.
- Decode raw RGB (`f=24`) images in addition to RGBA (`f=32`).
- Capture the cursor synchronously when a graphics command starts; image
  decoding is async, so reading the cursor later placed images after text.
- Notify listeners after asynchronous decoding and placement, so a final image
  at the end of a command's output appears without waiting for more output.
- Interpret Kitty `c`/`r` as cell dimensions and `s`/`v` as pixel dimensions.
  Use the render object's cell pixel size for pixel-sized images.
- Honour `C=1` (leave the cursor alone) and advance the cursor synchronously
  for the default `C=0` before subsequent text is parsed.
- Mark image cells at their real columns instead of always column zero.
- Translate image painting by the widget offset, padding, and scroll offset.

Keep patches small and upstream them where possible.
