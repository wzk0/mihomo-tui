import 'package:mihomo_tui/src/term/screen.dart';
import 'package:mihomo_tui/src/term/style.dart';
import 'package:test/test.dart';

void main() {
  group('Screen.putText', () {
    test('writes ascii cells', () {
      final screen = Screen(5, 2);
      screen.putText(1, 1, 'ab', Style.plain);
      expect(screen.cellAt(1, 1).rune, 'a'.codeUnitAt(0));
      expect(screen.cellAt(2, 1).rune, 'b'.codeUnitAt(0));
    });

    test('wide runes occupy two cells with a continuation', () {
      final screen = Screen(5, 1);
      screen.putText(0, 0, '中a', Style.plain);
      expect(screen.cellAt(0, 0).rune, '中'.runes.first);
      expect(screen.cellAt(1, 0).continuation, isTrue);
      expect(screen.cellAt(2, 0).rune, 'a'.codeUnitAt(0));
    });

    test('wide rune that does not fit is dropped', () {
      final screen = Screen(3, 1);
      final written = screen.putText(2, 0, '中', Style.plain);
      expect(written, 0);
      expect(screen.cellAt(2, 0).rune, 0x20);
    });

    test('respects maxWidth', () {
      final screen = Screen(10, 1);
      screen.putText(0, 0, 'abcdef', Style.plain, maxWidth: 3);
      expect(screen.cellAt(3, 0).rune, 0x20);
    });
  });

  group('ScreenRenderer', () {
    test('emits nothing when the frame did not change', () {
      final screen = Screen(20, 3);
      final renderer = ScreenRenderer()..trueColor = false;
      screen.putText(0, 0, 'hello', Style.plain);
      final first = renderer.render(screen);
      expect(first, contains('hello'));
      expect(renderer.render(screen), isEmpty);
    });

    test('only redraws changed rows', () {
      final screen = Screen(20, 3);
      final renderer = ScreenRenderer()..trueColor = false;
      screen.putText(0, 0, 'hello', Style.plain);
      renderer.render(screen);
      screen.putText(0, 2, 'bye', Style.plain);
      final second = renderer.render(screen);
      expect(second, contains('\x1b[3;'));
      expect(second, isNot(contains('hello')));
      expect(second, contains('bye'));
    });

    test('skips continuation cells of wide runes', () {
      final screen = Screen(6, 1);
      final renderer = ScreenRenderer()..trueColor = false;
      screen.putText(0, 0, '中', Style(fg: 0xff0000));
      final output = renderer.render(screen);
      expect(output.runes.where((rune) => rune == '中'.runes.first).length, 1);
    });

    test('produces working escapes for colours', () {
      final screen = Screen(4, 1);
      final renderer = ScreenRenderer()..trueColor = true;
      screen.putText(0, 0, 'x', Style(fg: 0x00ff00, bg: 0x000000));
      final output = renderer.render(screen);
      expect(output, contains('38;2;0;255;0'));
      expect(output, contains('48;2;0;0;0'));
    });
  });

  group('Style', () {
    test('equality and sgr', () {
      const a = Style(fg: 0x112233, bold: true);
      const b = Style(fg: 0x112233, bold: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.sgr(trueColor: true), contains('38;2;17;34;51'));
      expect(a.sgr(trueColor: false), contains('38;5;'));
    });

    test('256 colour fallback maps to the cube', () {
      expect(Style.to256(0, 0, 0), 16);
      expect(Style.to256(255, 255, 255), 231);
    });
  });
}
