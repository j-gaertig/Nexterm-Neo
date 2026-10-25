class EscapeEmitter {
  const EscapeEmitter();

  String primaryDeviceAttributes() {
    return '\x1b[?1;2c';
  }

  String secondaryDeviceAttributes() {
    const model = 0;
    const version = 0;
    return '\x1b[>$model;$version;0c';
  }

  String tertiaryDeviceAttributes() {
    return '\x1bP!|00000000\x1b\\';
  }

  String operatingStatus() {
    return '\x1b[0n';
  }

  /// Replies to a cursor position request (CPR, `CSI 6 n`).
  ///
  /// Both coordinates are 1-based, as ECMA-48 requires; `cursorPosition(1, 1)`
  /// reports the home position. Callers read them off
  /// [Buffer.reportedCursorX] / [Buffer.reportedCursorY] rather than the
  /// 0-based [Buffer.cursorX] / [Buffer.cursorY].
  String cursorPosition(int x, int y) {
    return '\x1b[$y;${x}R';
  }

  String bracketedPaste(String text) {
    return '\x1b[200~$text\x1b[201~';
  }

  String size(int rows, int cols) {
    return '\x1b[8;$rows;${cols}t';
  }
}
