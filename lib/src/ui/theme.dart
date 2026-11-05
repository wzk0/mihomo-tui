/// Colour palette (dark/light) with selectable accent colours.
library;

import '../term/style.dart';

class Theme {
  const Theme({
    required this.background,
    required this.panel,
    required this.panelAlt,
    required this.border,
    required this.borderFocus,
    required this.text,
    required this.muted,
    required this.accent,
    required this.green,
    required this.red,
    required this.yellow,
    required this.purple,
    required this.cyan,
    required this.selection,
    required this.header,
    required this.isLight,
    this.transparent = false,
  });

  // Surfaces are nullable so that a "transparent" theme can leave the
  // terminal's own background visible.
  final int? background;
  final int? panel;
  final int? panelAlt;
  final int? border;
  final int borderFocus;
  final int text;
  final int muted;
  final int accent;
  final int green;
  final int red;
  final int yellow;
  final int purple;
  final int cyan;
  final int? selection;
  final int? header;
  final bool isLight;

  /// True when backgrounds are left to the terminal (no background colours).
  final bool transparent;

  /// A softer shade of [accent] used for values, paths and names.
  int get accentSoft => mix(accent, isLight ? 0x101010 : 0xffffff, 0.22);

  /// Text colour used on top of accent / muted chips.
  int get chipText => isLight ? 0xffffff : 0x0e1014;

  /// Linear blend of two 0xRRGGBB colours (`t` in 0..1).
  static int mix(int from, int to, double t) {
    final clamped = t.clamp(0.0, 1.0);
    int channel(int shift) {
      final a = (from >> shift) & 0xff;
      final b = (to >> shift) & 0xff;
      return (a + (b - a) * clamped).round().clamp(0, 255);
    }

    return (channel(16) << 16) | (channel(8) << 8) | channel(0);
  }

  /// Perceived luminance of a 0xRRGGBB colour (0..1).
  static double luminance(int rgb) {
    final r = (rgb >> 16) & 0xff;
    final g = (rgb >> 8) & 0xff;
    final b = rgb & 0xff;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
  }

  /// Accent presets: id -> (label, dark, light).
  static const Map<String, (String, int, int)> accents = {
    'blue': ('蓝', 0x6ea8fe, 0x2563eb),
    'violet': ('紫', 0xb98bdb, 0x7c3aed),
    'green': ('绿', 0x4ec9a0, 0x15803d),
    'orange': ('橙', 0xe3a15a, 0xc2660a),
    'cyan': ('青', 0x58c3d6, 0x0e7490),
    'rose': ('玫红', 0xff8fa3, 0xbe123c),
  };

  /// xterm's 16 base colours, used to interpret `COLORFGBG`.
  static const List<int> ansiPalette = [
    0x000000,
    0xcd0000,
    0x00cd00,
    0xcdcd00,
    0x0000ee,
    0xcd00cd,
    0x00cdcd,
    0xe5e5e5,
    0x7f7f7f,
    0xff0000,
    0x00ff00,
    0xffff00,
    0x5c5cff,
    0xff00ff,
    0x00ffff,
    0xffffff,
  ];

  static const List<String> accentOrder = [
    'blue',
    'violet',
    'green',
    'orange',
    'cyan',
    'rose',
  ];

  static const Theme dark = Theme(
    background: 0x0e1014,
    panel: 0x14171f,
    panelAlt: 0x1a1e28,
    border: 0x272d3a,
    borderFocus: 0x5a8cff,
    text: 0xdde3f0,
    muted: 0x8a93a8,
    accent: 0x6ea8fe,
    green: 0x4ec9a0,
    red: 0xf07178,
    yellow: 0xe6b450,
    purple: 0xb98bdb,
    cyan: 0x58c3d6,
    selection: 0x212a3d,
    header: 0x171b24,
    isLight: false,
  );

  static const Theme light = Theme(
    background: 0xf4f6fa,
    panel: 0xffffff,
    panelAlt: 0xf0f3f8,
    border: 0xd2d8e3,
    borderFocus: 0x2563eb,
    text: 0x1c2230,
    muted: 0x6a7383,
    accent: 0x2563eb,
    green: 0x15803d,
    red: 0xc62828,
    yellow: 0xa16207,
    purple: 0x7c3aed,
    cyan: 0x0e7490,
    selection: 0xdbe6fb,
    header: 0xe8edf5,
    isLight: true,
  );

  /// Builds a palette from a light/dark flag and an accent id.
  ///
  /// Backgrounds are intentionally left to the terminal (transparent mode):
  /// only text, borders and accents are painted, so the UI follows whatever
  /// colour scheme the terminal itself uses.
  factory Theme.build({
    required bool light,
    String accent = 'blue',
  }) {
    final preset = accents[accent] ?? accents['blue']!;
    final base = light ? Theme.light : Theme.dark;
    final accentColor = light ? preset.$3 : preset.$2;
    return Theme(
      background: null,
      panel: null,
      panelAlt: null,
      border: base.border,
      borderFocus: accentColor,
      text: base.text,
      muted: base.muted,
      accent: accentColor,
      green: base.green,
      red: base.red,
      yellow: base.yellow,
      purple: base.purple,
      cyan: base.cyan,
      selection: null,
      header: null,
      isLight: light,
      transparent: true,
    );
  }

  static String accentLabel(String id) => accents[id]?.$1 ?? id;

  Style get base => Style(fg: text, bg: panel);
  Style get onBackground => Style(fg: text, bg: background);
  Style get mutedStyle => Style(fg: muted, bg: panel);
  Style get panelStyle => Style(bg: panelAlt);
  Style get headerStyle => Style(fg: text, bg: header, bold: true);
  Style get titleStyle => Style(fg: accent, bold: true);
  Style get dimStyle => Style(fg: muted, bg: panel, dim: true);
  Style get errorStyle => Style(fg: red, bg: panel);
  Style get successStyle => Style(fg: green, bg: panel);
  Style get warnStyle => Style(fg: yellow, bg: panel);

  /// Cursor row: only the `>` marker and weight change - no background is
  /// painted, so highlights never disturb borders or terminal backgrounds.
  Style selectionStyle({bool focused = true}) => Style(fg: text, bold: focused);

  /// Mouse hover highlight, used by the sidebar (which does not move the
  /// cursor on hover): just a brighter foreground.
  Style hoverStyle() => Style(fg: text);

  Style chip(int color) => Style(fg: color, bold: true);

  Style buttonStyle({bool primary = false, bool focused = false}) => Style(
        fg: primary ? chipText : text,
        bg: primary ? accent : panelAlt,
        bold: true,
      );
}
