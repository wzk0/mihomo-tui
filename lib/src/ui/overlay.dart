/// Modal overlays: confirmations, forms, help and scrollable text.
library;

import 'dart:async';
import 'dart:math' as math;

import '../term/keys.dart';
import '../term/style.dart';
import '../term/width.dart';
import '../service/core_updater.dart';
import '../util/clipboard.dart';
import 'painter.dart';

class KeyHint {
  const KeyHint(this.keys, this.label);
  final String keys;
  final String label;
}

class TextInput {
  TextInput({String value = ''}) : _value = value {
    _cursor = _runes.length;
  }

  String _value;
  int _cursor = 0;
  int? _anchor;

  String get value => _value;
  set value(String newValue) {
    _value = newValue;
    _cursor = _runes.length;
    _anchor = null;
  }

  int get cursor => _cursor;

  List<int> get _runes => _value.runes.toList();

  bool get hasSelection => _anchor != null && _anchor != _cursor;

  int get selectionStart =>
      hasSelection ? math.min(_anchor!, _cursor) : _cursor;

  int get selectionEnd => hasSelection ? math.max(_anchor!, _cursor) : _cursor;

  String get selectedText => hasSelection
      ? String.fromCharCodes(_runes.sublist(selectionStart, selectionEnd))
      : '';

  void selectAll() {
    _anchor = 0;
    _cursor = _runes.length;
  }

  void clearSelection() => _anchor = null;

  void deleteSelection() {
    if (!hasSelection) return;
    final runes = _runes;
    final start = selectionStart;
    final end = selectionEnd;
    _value = String.fromCharCodes([...runes.take(start), ...runes.skip(end)]);
    _cursor = start;
    _anchor = null;
  }

  void insert(String text) {
    deleteSelection();
    final runes = _runes;
    final inserted = text.runes.where((r) => r >= 0x20).toList();
    if (inserted.isEmpty) return;
    _value = String.fromCharCodes([
      ...runes.take(_cursor),
      ...inserted,
      ...runes.skip(_cursor),
    ]);
    _cursor += inserted.length;
    _anchor = null;
  }

  void backspace() {
    if (hasSelection) {
      deleteSelection();
      return;
    }
    if (_cursor == 0) return;
    final runes = _runes..removeAt(_cursor - 1);
    _value = String.fromCharCodes(runes);
    _cursor--;
  }

  void deleteWordBefore() {
    if (hasSelection) {
      deleteSelection();
      return;
    }
    final runes = _runes;
    var cursor = _cursor;
    while (cursor > 0 && runes[cursor - 1] == 0x20) {
      cursor--;
    }
    while (cursor > 0 && runes[cursor - 1] != 0x20) {
      cursor--;
    }
    _value = String.fromCharCodes([
      ...runes.take(cursor),
      ...runes.skip(_cursor),
    ]);
    _cursor = cursor;
  }

  void deleteToEnd() {
    if (hasSelection) {
      deleteSelection();
      return;
    }
    _value = String.fromCharCodes(_runes.take(_cursor));
  }

  void deleteForward() {
    if (hasSelection) {
      deleteSelection();
      return;
    }
    final runes = _runes;
    if (_cursor >= runes.length) return;
    runes.removeAt(_cursor);
    _value = String.fromCharCodes(runes);
  }

  void moveLeft({bool extend = false}) => _moveTo(_cursor - 1, extend: extend);

  void moveRight({bool extend = false}) => _moveTo(_cursor + 1, extend: extend);

  void moveHome({bool extend = false}) => _moveTo(0, extend: extend);

  void moveEnd({bool extend = false}) => _moveTo(_runes.length, extend: extend);

  void _moveTo(int index, {bool extend = false}) {
    final clamped = index.clamp(0, _runes.length);
    if (extend) {
      _anchor ??= _cursor;
    } else {
      _anchor = null;
    }
    _cursor = clamped;
  }

  void setCursorFromColumn(int column) {
    final runes = _runes;
    var width = 0;
    for (var i = 0; i < runes.length; i++) {
      final w = runeWidth(runes[i]);
      if (column < width + w) {
        _cursor = i;
        _anchor = null;
        return;
      }
      width += w;
    }
    _cursor = runes.length;
    _anchor = null;
  }

  /// Returns true when the key only affects the text buffer.
  bool handleKey(KeyEvent event) {
    switch (event.kind) {
      case KeyKind.backspace:
        backspace();
        return true;
      case KeyKind.delete:
        deleteForward();
        return true;
      case KeyKind.left:
        moveLeft(extend: event.shift);
        return true;
      case KeyKind.right:
        moveRight(extend: event.shift);
        return true;
      case KeyKind.home:
        moveHome(extend: event.shift);
        return true;
      case KeyKind.end:
        moveEnd(extend: event.shift);
        return true;
      case KeyKind.char:
        if (event.ctrl || event.alt) return false;
        final char = event.char;
        if (char == null) return false;
        insert(char);
        return true;
      default:
        return false;
    }
  }
}

abstract class Overlay {
  String get title;

  bool get isDismissed => _dismissed;
  bool _dismissed = false;

  void dismiss() => _dismissed = true;

  /// Implementations compute their own geometry from the screen size.
  void draw(Painter painter);

  bool handleKey(KeyEvent event);

  bool handleMouse(MouseEvent event);
}

Rect centeredRect(int screenWidth, int screenHeight, int width, int height) {
  final w = width > screenWidth - 2 ? screenWidth - 2 : width;
  final h = height > screenHeight - 2 ? screenHeight - 2 : height;
  return Rect(
    (screenWidth - w) ~/ 2,
    (screenHeight - h) ~/ 2,
    w,
    h,
  );
}

class ConfirmOverlay extends Overlay {
  ConfirmOverlay({
    required this.title,
    required this.message,
    this.detail = const [],
    this.confirmLabel = '确认',
    this.cancelLabel = '取消',
    required this.onConfirm,
    this.danger = false,
  });

  @override
  final String title;
  final String message;
  final List<String> detail;
  final String confirmLabel;
  final String cancelLabel;
  final void Function() onConfirm;
  final bool danger;

  Rect? _rect;
  Rect? _confirmRect;
  Rect? _cancelRect;

  @override
  void draw(Painter painter) {
    final theme = painter.theme;
    final bodyLines = wrapText(message, 60);
    final detailLines = <String>[];
    for (final line in detail) {
      detailLines.addAll(wrapText(line, 60));
    }
    final width = 64;
    final height = 5 +
        bodyLines.length +
        (detailLines.isEmpty ? 0 : 1 + detailLines.length);
    final rect = centeredRect(painter.width, painter.height, width, height);
    _rect = rect;
    painter.fill(rect, Style(bg: theme.panelAlt));
    painter.drawBox(
      rect,
      focused: true,
      title: title,
      borderStyle: Style(fg: danger ? theme.red : theme.borderFocus),
    );

    var y = rect.y + 2;
    for (final line in bodyLines) {
      painter.text(rect.x + 3, y++, line, Style(fg: theme.text));
    }
    if (detailLines.isNotEmpty) {
      y++;
      for (final line in detailLines) {
        painter.text(rect.x + 3, y++, line, Style(fg: theme.muted));
      }
    }

    final buttonsY = rect.bottom - 2;
    final confirmWidth = textWidth(confirmLabel) + 4;
    final cancelWidth = textWidth(cancelLabel) + 4;
    final total = confirmWidth + cancelWidth + 3;
    var x = rect.x + ((rect.width - total) ~/ 2);
    final confirmStyle = Style(
      fg: theme.chipText,
      bg: danger ? theme.red : theme.accent,
      bold: true,
    );
    final cancelStyle = Style(fg: theme.text, bg: theme.panel);
    _confirmRect = Rect(x, buttonsY, confirmWidth, 1);
    painter.fill(_confirmRect!, confirmStyle);
    painter.textAligned(_confirmRect!, confirmLabel, confirmStyle,
        center: true);
    painter.hit(_confirmRect!, id: 'confirm', onPress: _confirm);
    x += confirmWidth + 3;
    _cancelRect = Rect(x, buttonsY, cancelWidth, 1);
    painter.fill(_cancelRect!, cancelStyle);
    painter.textAligned(_cancelRect!, cancelLabel, cancelStyle, center: true);
    painter.hit(_cancelRect!, id: 'cancel', onPress: dismiss);

    painter.textAligned(
      Rect(rect.x, rect.bottom - 3, rect.width, 1),
      'Enter 确认 | Esc 取消',
      Style(fg: theme.muted),
      center: true,
    );
  }

  void _confirm() {
    dismiss();
    onConfirm();
  }

  @override
  bool handleKey(KeyEvent event) {
    if (event.kind == KeyKind.enter || event.isChar('y')) {
      _confirm();
      return true;
    }
    if (event.kind == KeyKind.escape ||
        event.isChar('n') ||
        event.isChar('q')) {
      dismiss();
      return true;
    }
    return true;
  }

  @override
  bool handleMouse(MouseEvent event) {
    if (event.kind == MouseKind.press && event.button == MouseButton.left) {
      if (_rect?.contains(event.x, event.y) ?? false) return true;
      dismiss();
      return true;
    }
    return false;
  }
}

enum FieldKind { text, toggle }

class FormFieldSpec {
  FormFieldSpec({
    required this.key,
    required this.label,
    this.hint = '',
    String initial = '',
    this.kind = FieldKind.text,
    this.initialToggle = false,
    this.required = false,
    this.validator,
    this.secret = false,
  })  : input = TextInput(value: initial),
        toggle = initialToggle;

  final String key;
  final String label;
  final String hint;
  final FieldKind kind;
  final bool initialToggle;
  final bool required;
  final String? Function(String value)? validator;
  final bool secret;
  final TextInput input;
  bool toggle;

  String get value => kind == FieldKind.toggle ? '$toggle' : input.value;
}

class FormOverlay extends Overlay {
  FormOverlay({
    required this.title,
    required this.fields,
    required this.onSubmit,
    this.submitLabel = '确定',
    this.description = const [],
    this.onChanged,
  });

  @override
  final String title;
  final List<FormFieldSpec> fields;
  final void Function(Map<String, String> values) onSubmit;
  final String submitLabel;
  final List<String> description;

  /// Called after any edit/selection change so the host can repaint.
  final void Function()? onChanged;

  int _focused = 0;
  String? _error;
  final _fieldRects = <int, Rect>{};

  FormFieldSpec get _current => fields[_focused];

  @override
  void draw(Painter painter) {
    final theme = painter.theme;
    final width = 70;
    final fieldsHeight = fields.fold<int>(
        0, (sum, f) => sum + (f.kind == FieldKind.toggle ? 2 : 3));
    final descHeight = description.length;
    final height = 5 + fieldsHeight + descHeight + (_error == null ? 0 : 2);
    final rect = centeredRect(painter.width, painter.height, width, height);
    painter.fill(rect, Style(bg: theme.panelAlt));
    painter.drawBox(rect, focused: true);

    var y = rect.y + 1;
    painter.text(rect.x + 3, y, title, Style(fg: theme.accent, bold: true));
    y++;
    for (final line in description) {
      painter.text(
        rect.x + 3,
        y++,
        truncate(line, rect.width - 6),
        Style(fg: theme.muted),
      );
    }

    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      final focused = index == _focused;
      if (field.kind == FieldKind.toggle) {
        y++;
        final mark = field.toggle ? '[x]' : '[ ]';
        final style = Style(
          fg: field.toggle ? theme.green : theme.muted,
          bg: theme.panelAlt,
          bold: true,
        );
        painter.text(rect.x + 3, y, mark, style);
        painter.text(
          rect.x + 7,
          y,
          truncate(field.label, rect.width - 10),
          Style(fg: focused ? theme.text : theme.muted, bold: focused),
        );
        painter.hit(
          Rect(rect.x + 2, y, rect.width - 4, 1),
          id: 'field$index',
          onPress: () {
            _focused = index;
            field.toggle = !field.toggle;
          },
        );
        y++;
        continue;
      }

      y++;
      painter.text(
        rect.x + 3,
        y,
        field.label +
            (field.required ? ' *' : '') +
            (field.secret ? '（下载时会忽略显示）' : ''),
        Style(fg: focused ? theme.text : theme.muted, bold: focused),
      );
      y++;
      final fieldRect = Rect(rect.x + 3, y, rect.width - 6, 1);
      _fieldRects[index] = fieldRect;
      painter.fill(
        fieldRect,
        Style(bg: focused ? theme.panel : theme.header),
      );
      final display = field.secret
          ? '*' * field.input.value.runes.length
          : field.input.value;
      final visibleWidth = fieldRect.width - 2;
      final valueWidth = textWidth(display);
      final cursorColumns =
          field.secret ? field.input.cursor : textWidth(_prefix(field.input));
      // Horizontal scroll: keep the caret in view so long values can still be
      // edited at the beginning (Ctrl+A / Home scroll back to the start).
      final maxOffset =
          valueWidth > visibleWidth ? valueWidth - visibleWidth : 0;
      final offset =
          (cursorColumns - visibleWidth + 1).clamp(0, maxOffset).toInt();
      final shown = _slice(display, offset, visibleWidth);
      painter.text(fieldRect.x + 1, y, shown, Style(fg: theme.text));
      if (field.input.hasSelection) {
        final selStart = textWidth(
          String.fromCharCodes(
            field.input.value.runes.take(field.input.selectionStart),
          ),
        );
        final selEnd = textWidth(
          String.fromCharCodes(
            field.input.value.runes.take(field.input.selectionEnd),
          ),
        );
        final from = math.max(selStart, offset);
        final to = math.min(selEnd, offset + visibleWidth);
        if (from < to) {
          painter.text(
            fieldRect.x + 1 + (from - offset),
            y,
            _slice(display, from, to - from),
            Style(reverse: true),
          );
        }
      }
      final empty = field.input.value.isEmpty;
      if (empty && field.hint.isNotEmpty) {
        painter.text(fieldRect.x + 1, y, truncate(field.hint, visibleWidth),
            Style(fg: theme.muted, dim: true));
      }
      if (focused) {
        final cursorColumn = cursorColumns - offset;
        if (cursorColumn >= 0 && cursorColumn < visibleWidth) {
          final charAt = empty
              ? _charAt(field.hint, 0)
              : _charAtCursor(display, field.input.cursor);
          painter.text(
            fieldRect.x + 1 + cursorColumn,
            y,
            charAt ?? ' ',
            Style(fg: theme.chipText, bg: theme.accent),
          );
        }
      }
      painter.hit(
        fieldRect,
        id: 'field$index',
        onPress: () {
          _focused = index;
          field.input.setCursorFromColumn(0);
        },
      );
      y++;
    }

    if (_error != null) {
      y++;
      painter.text(
        rect.x + 3,
        y,
        truncate(_error!, rect.width - 6),
        Style(fg: theme.red, bold: true),
      );
    }

    final footerY = rect.bottom - 2;
    final hintStyle = Style(fg: theme.muted);
    painter.text(
      rect.x + 3,
      footerY,
      'Tab 切换字段 | Enter $submitLabel | Esc 取消',
      hintStyle,
    );
    final buttonWidth = textWidth(submitLabel) + 4;
    final buttonRect =
        Rect(rect.right - buttonWidth - 3, footerY, buttonWidth, 1);
    final style = theme.buttonStyle(primary: true);
    painter.fill(buttonRect, style);
    painter.textAligned(buttonRect, submitLabel, style, center: true);
    painter.hit(buttonRect, id: 'submit', onPress: _submit);
  }

  String _prefix(TextInput input) {
    final runes = input.value.runes.toList();
    return String.fromCharCodes(runes.take(input.cursor));
  }

  String? _charAt(String display, int cursor) {
    final runes = display.runes.toList();
    if (cursor < runes.length) return String.fromCharCode(runes[cursor]);
    return null;
  }

  String? _charAtCursor(String display, int cursor) {
    final runes = display.runes.toList();
    if (cursor < runes.length) return String.fromCharCode(runes[cursor]);
    return null;
  }

  String _slice(String value, int skipColumns, int maxColumns) {
    final buffer = StringBuffer();
    var skipped = 0;
    var used = 0;
    for (final rune in value.runes) {
      final w = runeWidth(rune);
      if (skipped < skipColumns) {
        skipped += w;
        continue;
      }
      if (used + w > maxColumns) break;
      buffer.writeCharCode(rune);
      used += w;
    }
    return buffer.toString();
  }

  void _submit() {
    final values = <String, String>{};
    for (final field in fields) {
      values[field.key] = field.value;
      if (field.kind == FieldKind.text) {
        final value = field.input.value.trim();
        if (field.required && value.isEmpty) {
          _error = '「${field.label}」不能为空';
          _focused = fields.indexOf(field);
          return;
        }
        final message = field.validator?.call(value);
        if (message != null) {
          _error = message;
          _focused = fields.indexOf(field);
          return;
        }
      }
    }
    _error = null;
    dismiss();
    onSubmit(values);
  }

  @override
  bool handleKey(KeyEvent event) {
    final field = _current;
    if (event.kind == KeyKind.escape) {
      dismiss();
      return true;
    }
    if (event.kind == KeyKind.tab) {
      _focused = (event.shift ? _focused - 1 : _focused + 1) % fields.length;
      if (_focused < 0) _focused = fields.length - 1;
      return true;
    }
    if (event.kind == KeyKind.up || event.isCtrl('p')) {
      _focused = (_focused - 1) % fields.length;
      if (_focused < 0) _focused = fields.length - 1;
      return true;
    }
    if (event.kind == KeyKind.down || event.isCtrl('n')) {
      _focused = (_focused + 1) % fields.length;
      return true;
    }
    if (field.kind == FieldKind.toggle) {
      if (event.isChar(' ') || event.kind == KeyKind.enter) {
        if (event.kind == KeyKind.enter) {
          _submit();
        } else {
          field.toggle = !field.toggle;
        }
        return true;
      }
      if (event.kind == KeyKind.left || event.kind == KeyKind.right) {
        field.toggle = !field.toggle;
        return true;
      }
      return true;
    }
    if (event.kind == KeyKind.enter) {
      _submit();
      return true;
    }
    if (event.isCtrl('a')) {
      field.input.selectAll();
      onChanged?.call();
      return true;
    }
    if (event.isCtrl('c')) {
      _copySelection(field.input);
      return true;
    }
    if (event.isCtrl('x')) {
      _cutSelection(field.input);
      return true;
    }
    if (event.isCtrl('v')) {
      _pasteClipboard(field.input);
      return true;
    }
    if (event.isCtrl('u')) {
      field.input.value = '';
      onChanged?.call();
      return true;
    }
    if (event.isCtrl('e')) {
      field.input.moveEnd();
      onChanged?.call();
      return true;
    }
    if (event.isCtrl('w')) {
      field.input.deleteWordBefore();
      onChanged?.call();
      return true;
    }
    if (event.isCtrl('k')) {
      field.input.deleteToEnd();
      onChanged?.call();
      return true;
    }
    if (field.input.handleKey(event)) {
      _error = null;
      onChanged?.call();
      return true;
    }
    return true;
  }

  /// Ctrl+C: copies the selection, or the whole value when nothing is selected.
  void _copySelection(TextInput input) {
    final text = input.hasSelection ? input.selectedText : input.value;
    if (text.isEmpty) return;
    unawaited(Clipboard.write(text));
  }

  void _cutSelection(TextInput input) {
    if (!input.hasSelection) return;
    unawaited(Clipboard.write(input.selectedText));
    input.deleteSelection();
    onChanged?.call();
  }

  void _pasteClipboard(TextInput input) {
    unawaited(Clipboard.read().then((text) {
      if (text == null || text.isEmpty) return;
      // Single line fields: turn newlines/tabs into spaces.
      final cleaned = text
          .replaceAll('\r\n', '\n')
          .replaceAll(RegExp(r'[\r\n\t]'), ' ')
          .trimRight();
      if (cleaned.isEmpty) return;
      input.insert(cleaned);
      onChanged?.call();
    }));
  }

  @override
  bool handleMouse(MouseEvent event) {
    if (event.kind == MouseKind.press && event.button == MouseButton.left) {
      for (final entry in _fieldRects.entries) {
        if (entry.value.contains(event.x, event.y)) {
          _focused = entry.key;
          final field = fields[entry.key];
          field.input.setCursorFromColumn(event.x - entry.value.x - 1);
          return true;
        }
      }
    }
    return false;
  }
}

class InfoOverlay extends Overlay {
  InfoOverlay({required this.title, required this.lines});

  @override
  final String title;
  final List<String> lines;

  int _scroll = 0;

  @override
  void draw(Painter painter) {
    final theme = painter.theme;
    final width =
        painter.width - 8 < 40 ? painter.width - 2 : painter.width - 8;
    final height =
        painter.height - 4 < 12 ? painter.height - 2 : painter.height - 4;
    final rect = centeredRect(painter.width, painter.height, width, height);
    painter.fill(rect, Style(bg: theme.panelAlt));
    painter.drawBox(rect, focused: true, title: title);

    final inner = Rect(rect.x + 2, rect.y + 1, rect.width - 4, rect.height - 4);
    final maxScroll =
        lines.length > inner.height ? lines.length - inner.height : 0;
    if (_scroll > maxScroll) _scroll = maxScroll;
    if (_scroll < 0) _scroll = 0;
    for (var row = 0; row < inner.height; row++) {
      final index = _scroll + row;
      if (index >= lines.length) break;
      painter.text(
        inner.x,
        inner.y + row,
        truncate(lines[index], inner.width),
        Style(fg: theme.text),
      );
    }
    painter.text(
      inner.x,
      rect.bottom - 2,
      '上下 滚动 | PgUp/PgDn 翻页 | Esc 关闭',
      Style(fg: theme.muted),
    );
    painter.hit(inner, id: 'info', onWheel: (delta) {
      _scroll += delta * 3;
    });
  }

  @override
  bool handleKey(KeyEvent event) {
    if (event.kind == KeyKind.escape ||
        event.kind == KeyKind.enter ||
        event.isChar('q')) {
      dismiss();
      return true;
    }
    if (event.kind == KeyKind.up || event.isChar('k')) {
      _scroll--;
      return true;
    }
    if (event.kind == KeyKind.down || event.isChar('j')) {
      _scroll++;
      return true;
    }
    if (event.kind == KeyKind.pageUp) {
      _scroll -= 10;
      return true;
    }
    if (event.kind == KeyKind.pageDown) {
      _scroll += 10;
      return true;
    }
    if (event.kind == KeyKind.home) {
      _scroll = 0;
      return true;
    }
    if (event.kind == KeyKind.end) {
      _scroll = lines.length;
      return true;
    }
    return true;
  }

  @override
  bool handleMouse(MouseEvent event) {
    if (event.kind == MouseKind.press && event.button == MouseButton.left) {
      dismiss();
      return true;
    }
    return false;
  }
}

class HelpOverlay extends Overlay {
  HelpOverlay(this.sections);

  final List<(String, List<KeyHint>)> sections;
  int _scroll = 0;

  @override
  String get title => '快捷键';

  @override
  void draw(Painter painter) {
    final theme = painter.theme;
    final width = 74;
    final rows = <(String?, String, String)>[];
    for (final section in sections) {
      rows.add((null, section.$1, ''));
      for (final hint in section.$2) {
        rows.add((hint.keys, hint.label, ''));
      }
    }
    final height = rows.length + 5 > painter.height - 2
        ? painter.height - 2
        : rows.length + 5;
    final rect = centeredRect(painter.width, painter.height, width, height);
    painter.fill(rect, Style(bg: theme.panelAlt));
    painter.drawBox(rect, focused: true, title: '快捷键帮助');
    final inner = Rect(rect.x + 2, rect.y + 1, rect.width - 4, rect.height - 4);
    final maxScroll =
        rows.length > inner.height ? rows.length - inner.height : 0;
    if (_scroll > maxScroll) _scroll = maxScroll;
    if (_scroll < 0) _scroll = 0;
    for (var row = 0; row < inner.height; row++) {
      final index = _scroll + row;
      if (index >= rows.length) break;
      final entry = rows[index];
      final y = inner.y + row;
      if (entry.$1 == null) {
        painter.text(
            inner.x, y, '│ ${entry.$2}', Style(fg: theme.accent, bold: true));
      } else {
        painter.text(
            inner.x + 2, y, truncate(entry.$1!, 22), Style(fg: theme.yellow));
        painter.text(inner.x + 25, y, truncate(entry.$2, inner.width - 25),
            Style(fg: theme.text));
      }
    }
    painter.text(
      inner.x,
      rect.bottom - 2,
      '上下 滚动 | Esc / ? 关闭',
      Style(fg: theme.muted),
    );
    painter.hit(inner, id: 'help', onWheel: (delta) => _scroll += delta * 3);
  }

  @override
  bool handleKey(KeyEvent event) {
    if (event.kind == KeyKind.escape ||
        event.isChar('?') ||
        event.isChar('q') ||
        event.kind == KeyKind.enter) {
      dismiss();
      return true;
    }
    if (event.kind == KeyKind.up || event.isChar('k')) {
      _scroll--;
      return true;
    }
    if (event.kind == KeyKind.down || event.isChar('j')) {
      _scroll++;
      return true;
    }
    if (event.kind == KeyKind.pageUp) {
      _scroll -= 8;
      return true;
    }
    if (event.kind == KeyKind.pageDown) {
      _scroll += 8;
      return true;
    }
    return true;
  }

  @override
  bool handleMouse(MouseEvent event) {
    if (event.kind == MouseKind.press && event.button == MouseButton.left) {
      dismiss();
      return true;
    }
    return false;
  }
}

/// Mirror picker with reachability results.
class MirrorOverlay extends Overlay {
  MirrorOverlay({
    required this.current,
    required this.probes,
    required this.probing,
    required this.onSelect,
    required this.onRefresh,
  });

  final String current;
  final Map<String, MirrorProbe> probes;
  final bool Function(String id) probing;
  final void Function(String id) onSelect;
  final void Function() onRefresh;

  int _selected = 0;

  @override
  String get title => '下载镜像';

  @override
  void draw(Painter painter) {
    final theme = painter.theme;
    final width = 62;
    final height = coreMirrors.length + 6;
    final rect = centeredRect(painter.width, painter.height, width, height);
    painter.fill(rect, Style(bg: theme.panelAlt));

    var y = rect.y + 1;
    painter.text(
      rect.x + 3,
      y++,
      '选择更新内核时使用的下载源',
      Style(fg: theme.muted),
    );
    y++;
    for (var index = 0; index < coreMirrors.length; index++) {
      final mirror = coreMirrors[index];
      final selected = index == _selected;
      final rowRect = Rect(rect.x + 2, y + index, rect.width - 4, 1);
      final style = selected
          ? theme.selectionStyle()
          : Style(fg: theme.text, bg: theme.panelAlt);
      painter.text(
        rowRect.x,
        rowRect.y,
        selected ? '>' : ' ',
        Style(fg: theme.accent, bg: theme.panelAlt),
      );
      painter.text(
        rowRect.x + 2,
        rowRect.y,
        padRight(mirror.label, 22),
        Style(
          fg: mirror.id == current ? theme.green : style.fg,
          bg: theme.panelAlt,
          bold: mirror.id == current || selected,
        ),
      );
      final probe = probes[mirror.id];
      final status = probing(mirror.id)
          ? '检测中~'
          : probe == null
              ? '未检测'
              : probe.label;
      final color = probing(mirror.id)
          ? theme.yellow
          : probe == null
              ? theme.muted
              : probe.available
                  ? theme.green
                  : theme.red;
      painter.text(
        rowRect.x + 26,
        rowRect.y,
        truncate(status, rowRect.width - 28),
        Style(fg: color, bg: theme.panelAlt),
      );
      painter.hit(
        rowRect,
        id: 'mirror${mirror.id}',
        onHover: () => _selected = index,
        onPress: () {
          _selected = index;
          onSelect(mirror.id);
          dismiss();
        },
      );
    }
    final footerY = rect.bottom - 2;
    painter.text(
      rect.x + 3,
      footerY,
      'Enter 选择 | r 重新检测 | Esc 关闭',
      Style(fg: theme.muted),
    );
    // Blue accent for "github.com" hint line.
    painter.text(
      rect.x + 3,
      rect.bottom - 3,
      truncate('镜像只影响内核下载，不会改动订阅下载代理', rect.width - 6),
      Style(fg: theme.muted, dim: true),
    );
    painter.drawBox(rect, focused: true, title: title);
  }

  @override
  bool handleKey(KeyEvent event) {
    if (event.kind == KeyKind.escape || event.isChar('q')) {
      dismiss();
      return true;
    }
    if (event.kind == KeyKind.up || event.isChar('k')) {
      _selected = (_selected - 1 + coreMirrors.length) % coreMirrors.length;
      return true;
    }
    if (event.kind == KeyKind.down || event.isChar('j')) {
      _selected = (_selected + 1) % coreMirrors.length;
      return true;
    }
    if (event.isChar('r')) {
      onRefresh();
      return true;
    }
    if (event.kind == KeyKind.enter) {
      onSelect(coreMirrors[_selected].id);
      dismiss();
      return true;
    }
    return true;
  }

  @override
  bool handleMouse(MouseEvent event) {
    if (event.kind == MouseKind.press && event.button == MouseButton.left) {
      // Rows are hit-testable; clicks outside the dialog close it.
      dismiss();
      return true;
    }
    return false;
  }
}
