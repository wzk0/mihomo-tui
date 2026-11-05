/// Cell styling and SGR generation.
library;

class Style {
  const Style({
    this.fg,
    this.bg,
    this.bold = false,
    this.dim = false,
    this.italic = false,
    this.underline = false,
    this.reverse = false,
  });

  /// Foreground as 0xRRGGBB, or null for the terminal default.
  final int? fg;

  /// Background as 0xRRGGBB, or null for the terminal default.
  final int? bg;
  final bool bold;
  final bool dim;
  final bool italic;
  final bool underline;
  final bool reverse;

  static const Style plain = Style();

  Style copyWith({
    int? fg,
    int? bg,
    bool? bold,
    bool? dim,
    bool? italic,
    bool? underline,
    bool? reverse,
    bool clearFg = false,
    bool clearBg = false,
  }) {
    return Style(
      fg: clearFg ? null : (fg ?? this.fg),
      bg: clearBg ? null : (bg ?? this.bg),
      bold: bold ?? this.bold,
      dim: dim ?? this.dim,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      reverse: reverse ?? this.reverse,
    );
  }

  Style fgColor(int? color) => copyWith(fg: color, clearFg: color == null);
  Style bgColor(int? color) => copyWith(bg: color, clearBg: color == null);
  Style withBold(bool value) => copyWith(bold: value);
  Style withDim(bool value) => copyWith(dim: value);

  bool get isPlain =>
      fg == null &&
      bg == null &&
      !bold &&
      !dim &&
      !italic &&
      !underline &&
      !reverse;

  /// SGR sequence that switches the terminal from any state to this style.
  String sgr({required bool trueColor}) {
    final parts = <String>['0'];
    if (bold) parts.add('1');
    if (dim) parts.add('2');
    if (italic) parts.add('3');
    if (underline) parts.add('4');
    if (reverse) parts.add('7');
    if (fg != null) parts.add(_color(fg!, trueColor, foreground: true));
    if (bg != null) parts.add(_color(bg!, trueColor, foreground: false));
    return '\x1b[${parts.join(';')}m';
  }

  static String _color(int rgb, bool trueColor, {required bool foreground}) {
    final r = (rgb >> 16) & 0xff;
    final g = (rgb >> 8) & 0xff;
    final b = rgb & 0xff;
    if (trueColor) {
      return '${foreground ? 38 : 48};2;$r;$g;$b';
    }
    final index = to256(r, g, b);
    return '${foreground ? 38 : 48};5;$index';
  }

  /// Maps an RGB colour onto the xterm-256 palette.
  static int to256(int r, int g, int b) {
    if (r == g && g == b) {
      if (r < 8) return 16;
      if (r > 248) return 231;
      return 232 + ((r - 8) / 10).round();
    }
    int axis(int v) {
      if (v < 48) return 0;
      if (v < 115) return 1;
      return ((v - 35) / 40).round().clamp(0, 5);
    }

    return 16 + 36 * axis(r) + 6 * axis(g) + axis(b);
  }

  @override
  bool operator ==(Object other) =>
      other is Style &&
      other.fg == fg &&
      other.bg == bg &&
      other.bold == bold &&
      other.dim == dim &&
      other.italic == italic &&
      other.underline == underline &&
      other.reverse == reverse;

  @override
  int get hashCode =>
      Object.hash(fg, bg, bold, dim, italic, underline, reverse);

  @override
  String toString() =>
      'Style(fg: ${fg?.toRadixString(16)}, bg: ${bg?.toRadixString(16)}'
      '${bold ? ', bold' : ''}${dim ? ', dim' : ''})';
}
