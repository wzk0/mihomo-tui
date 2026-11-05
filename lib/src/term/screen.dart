/// Double buffered cell grid plus an ANSI diff renderer.
library;

import 'dart:typed_data';

import 'style.dart';
import 'width.dart';

class Cell {
  int rune = 0x20;
  Style style = Style.plain;

  /// True when this cell is the right half of a wide rune.
  bool continuation = false;

  void set(int rune, Style style, {bool continuation = false}) {
    this.rune = rune;
    this.style = style;
    this.continuation = continuation;
  }
}

class Screen {
  Screen(this.width, this.height)
      : _cells = List<Cell>.generate(
          width * height,
          (_) => Cell(),
          growable: false,
        );

  int width;
  int height;
  List<Cell> _cells;

  Cell cellAt(int x, int y) => _cells[y * width + x];

  List<Cell> get cells => _cells;

  void resize(int newWidth, int newHeight) {
    if (newWidth == width && newHeight == height) return;
    width = newWidth;
    height = newHeight;
    _cells = List<Cell>.generate(
      width * height,
      (_) => Cell(),
      growable: false,
    );
  }

  void clear() {
    for (final cell in _cells) {
      cell.rune = 0x20;
      cell.style = Style.plain;
      cell.continuation = false;
    }
  }

  void fillRect(int x, int y, int w, int h, Style style) {
    for (var row = y; row < y + h; row++) {
      if (row < 0 || row >= height) continue;
      for (var col = x; col < x + w; col++) {
        if (col < 0 || col >= width) continue;
        _cells[row * width + col]
          ..rune = 0x20
          ..style = style
          ..continuation = false;
      }
    }
  }

  /// Writes [text] at ([x], [y]). Wide runes are split into two cells; a rune
  /// that would not fit into the remaining columns is dropped.
  int putText(int x, int y, String text, Style style, {int? maxWidth}) {
    if (y < 0 || y >= height) return 0;
    var col = x;
    final limit = maxWidth == null ? width : (x + maxWidth).clamp(0, width);
    var written = 0;
    for (final rune in text.runes) {
      final w = runeWidth(rune);
      if (w == 0) continue;
      if (col + w > limit) break;
      if (col >= 0) {
        _cells[y * width + col]
          ..rune = rune
          ..style = style
          ..continuation = false;
        if (w == 2) {
          _cells[y * width + col + 1]
            ..rune = 0
            ..style = style
            ..continuation = true;
        }
      }
      col += w;
      written += w;
    }
    return written;
  }
}

/// Escapes the cursor to ([row], [col]) (both zero based).
void _moveTo(StringBuffer out, int row, int col) {
  out.write('\x1b[${row + 1};${col + 1}H');
}

/// True for runes whose display width is stable across terminals: ASCII, box
/// drawing, CJK / fullwidth blocks. Everything else (emoji, symbols, arrows)
/// is drawn in isolated runs because terminals disagree on their width.
bool _safeWidth(int rune) {
  if (rune < 0x7f) return true;
  if (rune >= 0x2500 && rune <= 0x257f) return true;
  return (rune >= 0x1100 && rune <= 0x115f) ||
      (rune >= 0x2e80 && rune <= 0x303e) ||
      (rune >= 0x3041 && rune <= 0x33ff) ||
      (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0xa000 && rune <= 0xa4cf) ||
      (rune >= 0xac00 && rune <= 0xd7a3) ||
      (rune >= 0xf900 && rune <= 0xfaff) ||
      (rune >= 0xfe30 && rune <= 0xfe6f) ||
      (rune >= 0xff00 && rune <= 0xff60) ||
      (rune >= 0xffe0 && rune <= 0xffe6);
}

/// Emits the smallest escape sequence stream that turns the previously
/// rendered grid into the current one.
class ScreenRenderer {
  Int32List _prevRunes = Int32List(0);
  Int32List _prevStyles = Int32List(0);
  int _width = 0;
  int _height = 0;
  bool _forceFull = true;

  final Map<Style, int> _styleIds = {};
  final List<Style> _styles = [Style.plain];
  final List<String> _sgrCache = [''];
  bool trueColor = true;

  ScreenRenderer() {
    _styleIds[Style.plain] = 0;
  }

  void invalidate() => _forceFull = true;

  int _styleId(Style style) {
    final cached = _styleIds[style];
    if (cached != null) return cached;
    final id = _styles.length;
    _styles.add(style);
    _styleIds[style] = id;
    _sgrCache.add(style.sgr(trueColor: trueColor));
    return id;
  }

  /// Rebuilds the SGR cache after the colour capability changed.
  void refreshColorMode() {
    _sgrCache
      ..clear()
      ..addAll(_styles.map((s) => s.sgr(trueColor: trueColor)));
  }

  String render(Screen screen) {
    final cells = screen.cells;
    if (screen.width != _width ||
        screen.height != _height ||
        _prevRunes.length != cells.length) {
      _width = screen.width;
      _height = screen.height;
      _prevRunes = Int32List(cells.length);
      _prevStyles = Int32List(cells.length)..fillRange(0, cells.length, -1);
      _forceFull = true;
    }

    final out = StringBuffer();
    var needSgrReset = false;
    var lastStyleId = -1;

    // Pack rune + style id into the buffers up front.
    final runes = Int32List(cells.length);
    final styleIds = Int32List(cells.length);
    for (var i = 0; i < cells.length; i++) {
      runes[i] = cells[i].continuation ? -1 : cells[i].rune;
      styleIds[i] = _styleId(cells[i].style);
    }

    for (var row = 0; row < _height; row++) {
      final rowStart = row * _width;
      var first = -1;
      var last = -1;
      if (_forceFull) {
        first = 0;
        last = _width - 1;
      } else {
        for (var col = 0; col < _width; col++) {
          final i = rowStart + col;
          if (runes[i] != _prevRunes[i] || styleIds[i] != _prevStyles[i]) {
            first = col;
            break;
          }
        }
        if (first < 0) continue;
        for (var col = _width - 1; col >= first; col--) {
          final i = rowStart + col;
          if (runes[i] != _prevRunes[i] || styleIds[i] != _prevStyles[i]) {
            last = col;
            break;
          }
        }
      }
      if (first < 0 || last < 0) continue;

      // Never start in the middle of a wide rune.
      while (first > 0 && cells[rowStart + first].continuation) {
        first--;
      }
      // Never stop in the middle of a wide rune.
      while (last + 1 < _width && cells[rowStart + last + 1].continuation) {
        last++;
      }

      // Text is emitted in absolute-positioned chunks: terminals disagree
      // about the width of non-ASCII glyphs (emoji, flags, ...), so those are
      // drawn as isolated runs with a pre-cleared footprint. ASCII, CJK and
      // box drawing keep the fast contiguous path.
      var expectedCol = -1;
      for (var col = first; col <= last; col++) {
        final cell = cells[rowStart + col];
        if (cell.continuation) continue;
        final styleId = styleIds[rowStart + col];
        if (styleId != lastStyleId) {
          if (lastStyleId != 0) {
            out.write('\x1b[0m');
            needSgrReset = false;
          }
          if (styleId != 0) {
            out.write(_sgrCache[styleId]);
            needSgrReset = true;
          }
          lastStyleId = styleId;
        }
        final rune = cell.rune;
        if (rune < 0x20) continue;

        if (_safeWidth(rune)) {
          if (col != expectedCol) _moveTo(out, row, col);
          out.writeCharCode(rune);
          expectedCol = col + runeWidth(rune);
          continue;
        }

        // Collect the contiguous run of "risky" cells (same style).
        final start = col;
        final buffer = StringBuffer();
        var end = col;
        while (col <= last) {
          final current = cells[rowStart + col];
          if (current.continuation) {
            col++;
            continue;
          }
          if (current.rune < 0x20 ||
              _safeWidth(current.rune) ||
              styleIds[rowStart + col] != styleId) {
            break;
          }
          buffer.writeCharCode(current.rune);
          end = col + runeWidth(current.rune);
          col++;
        }
        col--;
        _moveTo(out, row, start);
        if (end > start) out.write(' ' * (end - start));
        _moveTo(out, row, start);
        out.write(buffer.toString());
        expectedCol = -1;
      }
    }

    if (needSgrReset) out.write('\x1b[0m');

    _prevRunes.setAll(0, runes);
    _prevStyles.setAll(0, styleIds);
    _forceFull = false;
    return out.toString();
  }
}
