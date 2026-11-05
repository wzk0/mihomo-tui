/// Drawing surface: cell helpers, box drawing and mouse hit registration.
library;

import '../term/screen.dart';
import '../term/style.dart';
import '../term/width.dart';
import 'theme.dart';

class Rect {
  const Rect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;
  int get centerY => y + height ~/ 2;

  bool contains(int px, int py) =>
      px >= x && px < x + width && py >= y && py < y + height;

  Rect inset(int dx, int dy) =>
      Rect(x + dx, y + dy, width - dx * 2, height - dy * 2);

  Rect translate(int dx, int dy) => Rect(x + dx, y + dy, width, height);

  static Rect fromEdges(int left, int top, int right, int bottom) =>
      Rect(left, top, right - left, bottom - top);

  @override
  String toString() => 'Rect($x,$y ${width}x$height)';
}

class Hit {
  Hit({
    required this.rect,
    required this.id,
    this.onPress,
    this.onWheel,
    this.onHover,
    this.tooltip,
  });

  final Rect rect;
  final String id;
  final void Function()? onPress;
  final void Function(int delta)? onWheel;

  /// Called when the pointer enters this region (cursor follows the mouse).
  final void Function()? onHover;
  final String? tooltip;
}

class Painter {
  Painter(this.screen, this.theme);

  final Screen screen;
  final Theme theme;
  final List<Hit> hits = [];

  int get width => screen.width;
  int get height => screen.height;

  void fill(Rect rect, Style style) {
    final clamped = _clamp(rect);
    if (clamped == null) return;
    screen.fillRect(clamped.x, clamped.y, clamped.width, clamped.height, style);
  }

  /// Draws [text] and returns the number of columns written.
  int text(int x, int y, String text, Style style, {int? maxWidth}) {
    if (y < 0 || y >= height || x >= width) return 0;
    final available = width - x;
    final limit = maxWidth == null
        ? available
        : (maxWidth < available ? maxWidth : available);
    if (limit <= 0) return 0;
    return screen.putText(x, y, text, style, maxWidth: limit);
  }

  void textAligned(
    Rect rect,
    String text,
    Style style, {
    bool right = false,
    bool center = false,
    int padding = 0,
  }) {
    final inner = Rect(
      rect.x + padding,
      rect.y,
      rect.width - padding * 2,
      rect.height,
    );
    if (inner.width <= 0) return;
    final clipped = truncate(text, inner.width);
    final textLen = textWidth(clipped);
    final offset = right
        ? inner.width - textLen
        : center
            ? (inner.width - textLen) ~/ 2
            : 0;
    this.text(inner.x + (offset < 0 ? 0 : offset), inner.y, clipped, style);
  }

  void drawBox(
    Rect rect, {
    bool focused = false,
    String? title,
    Style? titleStyle,
    Style? borderStyle,
  }) {
    if (rect.width < 2 || rect.height < 2) return;
    final style = borderStyle ??
        Style(fg: focused ? theme.borderFocus : theme.border, bg: theme.panel);
    final left = rect.x;
    final top = rect.y;
    final right = rect.right - 1;
    final bottom = rect.bottom - 1;
    text(left, top, '╭${'─' * (rect.width - 2)}╮', style);
    for (var row = top + 1; row < bottom; row++) {
      text(left, row, '│', style);
      text(right, row, '│', style);
    }
    text(left, bottom, '╰${'─' * (rect.width - 2)}╯', style);
    if (title != null && title.isNotEmpty) {
      final styleToUse = titleStyle ?? theme.titleStyle;
      final maxWidth = rect.width - 4;
      if (maxWidth > 1) {
        final label = truncate(' $title ', maxWidth);
        text(left + 2, top, label, styleToUse);
      }
    }
  }

  void hit(
    Rect rect, {
    String id = '',
    void Function()? onPress,
    void Function(int delta)? onWheel,
    void Function()? onHover,
    String? tooltip,
  }) {
    final clamped = _clamp(rect);
    if (clamped == null) return;
    hits.add(Hit(
      rect: clamped,
      id: id,
      onPress: onPress,
      onWheel: onWheel,
      onHover: onHover,
      tooltip: tooltip,
    ));
  }

  /// Key hint chip: [key] on an accent background followed by a muted label.
  int keyHint(int x, int y, String key, String label) {
    var cursor = x;
    final keyStyle = Style(fg: theme.chipText, bg: theme.muted, bold: true);
    final labelStyle = Style(fg: theme.muted, bg: theme.header);
    cursor += text(cursor, y, ' $key ', keyStyle);
    cursor += text(cursor + 1, y, label, labelStyle);
    return cursor + 2 - x;
  }

  int tag(int x, int y, String label, Style style) {
    return text(x, y, ' $label ', style);
  }

  int button(
    Rect rect,
    String label, {
    bool primary = false,
    bool focused = false,
  }) {
    final style = theme.buttonStyle(primary: primary);
    fill(rect, style);
    textAligned(rect, label, style, center: true);
    return rect.width;
  }

  Rect? _clamp(Rect rect) {
    final left = rect.x < 0 ? 0 : rect.x;
    final top = rect.y < 0 ? 0 : rect.y;
    final right = rect.right > width ? width : rect.right;
    final bottom = rect.bottom > height ? height : rect.bottom;
    if (right <= left || bottom <= top) return null;
    return Rect.fromEdges(left, top, right, bottom);
  }
}
