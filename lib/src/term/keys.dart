/// Key and pointer event model shared by every platform backend.
library;

enum KeyKind {
  char,
  enter,
  escape,
  tab,
  backspace,
  delete,
  insert,
  home,
  end,
  pageUp,
  pageDown,
  up,
  down,
  left,
  right,
  f1,
  f2,
  f3,
  f4,
  f5,
  f6,
  f7,
  f8,
  f9,
  f10,
  f11,
  f12,
}

enum MouseKind { press, release, move, wheel }

enum MouseButton { none, left, middle, right }

sealed class TermEvent {
  const TermEvent();
}

class KeyEvent extends TermEvent {
  const KeyEvent(
    this.kind, {
    this.char,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
  });

  final KeyKind kind;

  /// Lower-cased printable character for [KeyKind.char] (and for ctrl/alt combos).
  final String? char;
  final bool ctrl;
  final bool alt;
  final bool shift;

  /// Matches a plain (unmodified) character, case insensitively.
  bool isChar(String c) =>
      kind == KeyKind.char &&
      !ctrl &&
      char != null &&
      char!.toLowerCase() == c.toLowerCase();

  /// Matches a character case sensitively (for `Shift`-style bindings).
  bool isCharExact(String c) =>
      kind == KeyKind.char && !ctrl && !alt && char == c;

  /// Matches ctrl+`c`, case insensitively.
  bool isCtrl(String c) =>
      kind == KeyKind.char &&
      ctrl &&
      char != null &&
      char!.toLowerCase() == c.toLowerCase();

  bool get isMoveUp => kind == KeyKind.up || isChar('k') || isCtrl('p');
  bool get isMoveDown => kind == KeyKind.down || isChar('j') || isCtrl('n');
  bool get isConfirm =>
      kind == KeyKind.enter || kind == KeyKind.char && char == ' ';
  bool get isCancel => kind == KeyKind.escape;

  @override
  String toString() {
    final mods = [
      if (ctrl) 'ctrl',
      if (alt) 'alt',
      if (shift) 'shift',
    ];
    final base = kind == KeyKind.char ? char : kind.name;
    return mods.isEmpty ? '$base' : '${mods.join('+')}+$base';
  }
}

class MouseEvent extends TermEvent {
  const MouseEvent({
    required this.kind,
    required this.x,
    required this.y,
    this.button = MouseButton.none,
    this.wheelDelta = 0,
    this.shift = false,
    this.alt = false,
    this.ctrl = false,
  });

  /// Zero based column.
  final int x;

  /// Zero based row.
  final int y;
  final MouseKind kind;
  final MouseButton button;

  /// -1 for wheel up, 1 for wheel down, 0 otherwise.
  final int wheelDelta;
  final bool shift;
  final bool alt;
  final bool ctrl;

  @override
  String toString() => 'mouse(${kind.name} ${button.name} $x,$y)';
}

class ResizeEvent extends TermEvent {
  const ResizeEvent(this.columns, this.rows);
  final int columns;
  final int rows;
}

/// Response to an OSC 10/11 colour query (`\x1b]11;rgb:....`).
class ColorReportEvent extends TermEvent {
  const ColorReportEvent({
    required this.red,
    required this.green,
    required this.blue,
    this.isBackground = true,
  });

  final int red;
  final int green;
  final int blue;
  final bool isBackground;

  /// ITU-R BT.709 relative luminance in the 0..1 range.
  double get luminance =>
      (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0;

  bool get isLight => luminance > 0.55;

  @override
  String toString() =>
      'color(${isBackground ? 'bg' : 'fg'} #${red.toRadixString(16)}'
      '${green.toRadixString(16)}${blue.toRadixString(16)})';
}
