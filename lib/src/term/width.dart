/// Minimal East-Asian aware column width helpers.
///
/// Terminals render CJK / fullwidth runes two cells wide and combining marks
/// zero cells wide; everything else (including box drawing) is treated as one
/// cell, which is what mainstream terminals do.
library;

const List<List<int>> _wide = [
  [0x1100, 0x115F], // Hangul Jamo init.
  [0x231A, 0x231B],
  [0x2329, 0x232A],
  [0x23E9, 0x23EC],
  [0x23F0, 0x23F0],
  [0x23F3, 0x23F3],
  [0x25FD, 0x25FE],
  [0x2614, 0x2615],
  [0x2648, 0x2653],
  [0x267F, 0x267F],
  [0x2693, 0x2693],
  [0x26A1, 0x26A1],
  [0x26AA, 0x26AB],
  [0x26BD, 0x26BE],
  [0x26C4, 0x26C5],
  [0x26CE, 0x26CE],
  [0x26D4, 0x26D4],
  [0x26EA, 0x26EA],
  [0x26F2, 0x26F3],
  [0x26F5, 0x26F5],
  [0x26FA, 0x26FA],
  [0x26FD, 0x26FD],
  [0x2705, 0x2705],
  [0x270A, 0x270B],
  [0x2728, 0x2728],
  [0x274C, 0x274C],
  [0x274E, 0x274E],
  [0x2753, 0x2755],
  [0x2757, 0x2757],
  [0x2795, 0x2797],
  [0x27B0, 0x27B0],
  [0x27BF, 0x27BF],
  [0x2B1B, 0x2B1C],
  [0x2B50, 0x2B50],
  [0x2B55, 0x2B55],
  [0x2E80, 0x303E],
  [0x3041, 0x33FF],
  [0x3400, 0x4DBF],
  [0x4E00, 0x9FFF],
  [0xA000, 0xA4CF],
  [0xA960, 0xA97F],
  [0xAC00, 0xD7A3],
  [0xF900, 0xFAFF],
  [0xFE10, 0xFE19],
  [0xFE30, 0xFE6F],
  [0xFF00, 0xFF60],
  [0xFFE0, 0xFFE6],
  [0x16FE0, 0x16FE4],
  [0x17000, 0x18CFF],
  [0x1B000, 0x1B2FF],
  [0x1F004, 0x1F004],
  [0x1F0CF, 0x1F0CF],
  [0x1F18E, 0x1F18E],
  [0x1F191, 0x1F19A],
  [0x1F1E6, 0x1F1FF],
  [0x1F200, 0x1F320],
  [0x1F32D, 0x1F335],
  [0x1F337, 0x1F37C],
  [0x1F37E, 0x1F393],
  [0x1F3A0, 0x1F3CA],
  [0x1F3CF, 0x1F3D3],
  [0x1F3E0, 0x1F3F0],
  [0x1F3F4, 0x1F3F4],
  [0x1F3F8, 0x1F43E],
  [0x1F440, 0x1F440],
  [0x1F442, 0x1F4FC],
  [0x1F4FF, 0x1F53D],
  [0x1F54B, 0x1F54E],
  [0x1F550, 0x1F567],
  [0x1F57A, 0x1F57A],
  [0x1F595, 0x1F596],
  [0x1F5A4, 0x1F5A4],
  [0x1F5FB, 0x1F64F],
  [0x1F680, 0x1F6C5],
  [0x1F6CC, 0x1F6CC],
  [0x1F6D0, 0x1F6D2],
  [0x1F6D5, 0x1F6D7],
  [0x1F6EB, 0x1F6EC],
  [0x1F6F4, 0x1F6FC],
  [0x1F7E0, 0x1F7EB],
  [0x1F90C, 0x1F93A],
  [0x1F93C, 0x1F945],
  [0x1F947, 0x1F9FF],
  [0x1FA70, 0x1FAFF],
  [0x20000, 0x2FFFD],
  [0x30000, 0x3FFFD],
];

const List<List<int>> _zero = [
  [0x0300, 0x036F],
  [0x0483, 0x0489],
  [0x0591, 0x05BD],
  [0x0610, 0x061A],
  [0x064B, 0x065F],
  [0x0670, 0x0670],
  [0x06D6, 0x06DC],
  [0x0E31, 0x0E31],
  [0x0E34, 0x0E3A],
  [0x0E47, 0x0E4E],
  [0x1AB0, 0x1AFF],
  [0x1DC0, 0x1DFF],
  [0x200B, 0x200F],
  [0x202A, 0x202E],
  [0x2060, 0x2064],
  [0x20D0, 0x20F0],
  [0xE0100, 0xE01EF],
  [0xFE00, 0xFE0F],
  [0xFE20, 0xFE2F],
  [0xFEFF, 0xFEFF],
];

bool _inTable(List<List<int>> table, int rune) {
  var lo = 0;
  var hi = table.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final entry = table[mid];
    if (rune < entry[0]) {
      hi = mid - 1;
    } else if (rune > entry[1]) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// Number of terminal columns [rune] occupies (0, 1 or 2).
int runeWidth(int rune) {
  if (rune == 0) return 0;
  if (rune < 0x20 || (rune >= 0x7f && rune < 0xa0)) return 0;
  if (_inTable(_zero, rune)) return 0;
  if (_inTable(_wide, rune)) return 2;
  return 1;
}

/// Number of terminal columns [text] occupies.
int textWidth(String text) {
  var width = 0;
  for (final rune in text.runes) {
    width += runeWidth(rune);
  }
  return width;
}

/// Truncates [text] so that it fits in [maxWidth] columns, appending an
/// ellipsis when content is dropped.
String truncate(String text, int maxWidth, {String ellipsis = '~'}) {
  if (maxWidth <= 0) return '';
  if (textWidth(text) <= maxWidth) return text;
  final ellipsisWidth = textWidth(ellipsis);
  if (maxWidth <= ellipsisWidth) return '.' * maxWidth;
  final limit = maxWidth - ellipsisWidth;
  final buffer = StringBuffer();
  var width = 0;
  for (final rune in text.runes) {
    final w = runeWidth(rune);
    if (width + w > limit) break;
    buffer.writeCharCode(rune);
    width += w;
  }
  buffer.write(ellipsis);
  return buffer.toString();
}

/// Pads [text] with spaces up to [width] columns (truncating if needed).
String padRight(String text, int width) {
  final t = truncate(text, width);
  return t + ' ' * (width - textWidth(t));
}

/// Pads [text] on the left with spaces up to [width] columns.
String padLeft(String text, int width) {
  final t = truncate(text, width);
  return ' ' * (width - textWidth(t)) + t;
}

/// Hard-wraps [text] on whitespace / CJK boundaries to [width] columns.
List<String> wrapText(String text, int width) {
  if (width <= 0) return const [];
  final lines = <String>[];
  for (final paragraph in text.split('\n')) {
    if (paragraph.trim().isEmpty) {
      lines.add('');
      continue;
    }
    // Split into chunks: whitespace, single wide runes, or runs of narrow
    // characters. This keeps latin words together and lets CJK break anywhere.
    final chunks = <String>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      chunks.add(buffer.toString());
      buffer.clear();
    }

    for (final rune in paragraph.runes) {
      if (rune == 0x20) {
        flush();
        chunks.add(' ');
      } else if (runeWidth(rune) == 2) {
        flush();
        chunks.add(String.fromCharCode(rune));
      } else {
        buffer.writeCharCode(rune);
      }
    }
    flush();

    var line = StringBuffer();
    var used = 0;
    for (final chunk in chunks) {
      final chunkWidth = textWidth(chunk);
      if (chunk == ' ' && line.isEmpty) continue;
      if (used + chunkWidth <= width) {
        line.write(chunk);
        used += chunkWidth;
        continue;
      }
      if (chunk == ' ') {
        lines.add(line.toString().trimRight());
        line = StringBuffer();
        used = 0;
        continue;
      }
      if (chunkWidth <= width) {
        lines.add(line.toString().trimRight());
        line = StringBuffer(chunk);
        used = chunkWidth;
        continue;
      }
      // Chunk itself is wider than the target: hard split.
      lines.add(line.toString().trimRight());
      line = StringBuffer();
      used = 0;
      for (final rune in chunk.runes) {
        final runeCols = runeWidth(rune);
        if (used + runeCols > width) {
          lines.add(line.toString());
          line = StringBuffer();
          used = 0;
        }
        line.writeCharCode(rune);
        used += runeCols;
      }
    }
    lines.add(line.toString().trimRight());
  }
  return lines;
}
