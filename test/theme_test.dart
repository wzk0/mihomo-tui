import 'package:mihomo_tui/src/term/style.dart';
import 'package:mihomo_tui/src/ui/theme.dart';
import 'package:test/test.dart';

void main() {
  test('light and dark palettes differ', () {
    final dark = Theme.build(light: false);
    final light = Theme.build(light: true);
    expect(dark.isLight, isFalse);
    expect(light.isLight, isTrue);
    expect(dark.text, isNot(light.text));
    expect(dark.border, isNot(light.border));
  });

  test('accent presets are applied per mode', () {
    for (final id in Theme.accentOrder) {
      final preset = Theme.accents[id]!;
      expect(Theme.build(light: false, accent: id).accent, preset.$2);
      expect(Theme.build(light: true, accent: id).accent, preset.$3);
    }
    // Unknown ids fall back to blue.
    expect(
      Theme.build(light: false, accent: 'nope').accent,
      Theme.accents['blue']!.$2,
    );
  });

  test('accent list covers all presets', () {
    expect(Theme.accentOrder.toSet(), Theme.accents.keys.toSet());
    expect(Theme.accentLabel('violet'), '紫');
  });

  test('cursor and hover styles never paint a background', () {
    final theme = Theme.build(light: false);
    expect(theme.selectionStyle().underline, isFalse);
    expect(theme.selectionStyle().bg, isNull);
    expect(theme.selectionStyle().reverse, isFalse);
    expect(theme.selectionStyle().bold, isTrue);
    expect(theme.hoverStyle().bg, isNull);
    expect(theme.hoverStyle().reverse, isFalse);
    expect(theme.hoverStyle().fg, theme.text);
  });

  test('backgrounds are always transparent', () {
    for (final theme in [
      Theme.build(light: false),
      Theme.build(light: true),
      Theme.build(light: false, accent: 'green'),
    ]) {
      expect(theme.background, isNull);
      expect(theme.panel, isNull);
      expect(theme.panelAlt, isNull);
      expect(theme.header, isNull);
      expect(theme.selection, isNull);
      expect(theme.transparent, isTrue);
      // Text colours and borders still come from the light/dark palette.
      expect(theme.text, isNotNull);
      expect(theme.border, isNotNull);
    }
  });

  test('accentSoft keeps the accent hue', () {
    final theme = Theme.build(light: false, accent: 'violet');
    expect(theme.accentSoft, isNot(theme.accent));
    expect(theme.accentSoft, isNot(theme.cyan));
    int r(int c) => (c >> 16) & 0xff;
    int b(int c) => c & 0xff;
    expect(b(theme.accentSoft) > r(theme.accentSoft),
        b(theme.accent) > r(theme.accent));
    expect(Theme.mix(0x000000, 0xffffff, 0.5), 0x808080);
  });

  test('chip text contrasts with the palette', () {
    expect(Theme.build(light: false).chipText, 0x0e1014);
    expect(Theme.build(light: true).chipText, 0xffffff);
  });

  test('primary button uses accent background', () {
    final theme = Theme.build(light: false, accent: 'green');
    final style = theme.buttonStyle(primary: true);
    expect(style.bg, theme.accent);
    expect(style.bold, isTrue);
  });

  test('styles keep panel background for text', () {
    final theme = Theme.build(light: true);
    expect(theme.base.bg, theme.panel);
    expect(theme.base.fg, theme.text);
    expect(theme.base, isA<Style>());
  });
}
