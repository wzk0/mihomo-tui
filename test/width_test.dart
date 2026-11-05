import 'package:mihomo_tui/src/term/width.dart';
import 'package:test/test.dart';

void main() {
  group('runeWidth', () {
    test('ascii is one column', () {
      expect(runeWidth('a'.codeUnitAt(0)), 1);
      expect(runeWidth('~'.codeUnitAt(0)), 1);
    });

    test('CJK is two columns', () {
      expect(runeWidth('中'.runes.first), 2);
      expect(runeWidth('あ'.runes.first), 2);
      expect(runeWidth('한'.runes.first), 2);
      expect(runeWidth('Ａ'.runes.first), 2);
    });

    test('combining marks and control chars take no space', () {
      expect(runeWidth(0x0301), 0);
      expect(runeWidth(0x200b), 0);
      expect(runeWidth(0x0a), 0);
    });

    test('box drawing stays single width', () {
      expect(runeWidth('─'.runes.first), 1);
      expect(runeWidth('╭'.runes.first), 1);
    });
  });

  group('textWidth', () {
    test('mixes ascii and CJK', () {
      expect(textWidth('proxy 节点'), 6 + 4);
      expect(textWidth(''), 0);
    });
  });

  group('truncate', () {
    test('keeps short strings untouched', () {
      expect(truncate('abc', 5), 'abc');
    });

    test('adds an ellipsis and respects wide runes', () {
      expect(truncate('abcdef', 4), 'abc~');
      expect(textWidth(truncate('中文中文中文', 7)), 7);
      expect(truncate('中文中文', 1), '.');
    });

    test('handles zero width targets', () {
      expect(truncate('abc', 0), '');
    });
  });

  group('padding', () {
    test('padRight pads with spaces using display width', () {
      expect(padRight('中', 4), '中  ');
      expect(textWidth(padRight('中', 4)), 4);
    });

    test('padLeft pads on the left', () {
      expect(padLeft('12', 4), '  12');
      expect(textWidth(padLeft('中', 4)), 4);
    });

    test('padding truncates oversized content', () {
      expect(textWidth(padRight('abcdefgh', 4)), 4);
    });
  });

  group('wrapText', () {
    test('wraps on width', () {
      expect(wrapText('one two three', 7), ['one two', 'three']);
    });

    test('wraps CJK without spaces', () {
      final lines = wrapText('中文中文中文', 4);
      expect(lines.length, 3);
      for (final line in lines) {
        expect(textWidth(line) <= 4, isTrue);
      }
    });

    test('keeps paragraph breaks', () {
      expect(wrapText('a\n\nb', 10), ['a', '', 'b']);
    });
  });
}
