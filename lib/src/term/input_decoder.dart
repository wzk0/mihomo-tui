/// Decodes raw POSIX terminal bytes (UTF-8 + ANSI/xterm mouse) into events.
library;

import 'dart:convert';

import 'keys.dart';

class AnsiInputDecoder {
  AnsiInputDecoder(this.emit);

  final void Function(TermEvent event) emit;
  final List<int> _buffer = [];

  bool get hasPendingBytes => _buffer.isNotEmpty;
  bool get hasOnlyEscape => _buffer.length == 1 && _buffer.first == 0x1b;

  void add(List<int> bytes) {
    _buffer.addAll(bytes);
    _drain();
  }

  /// Called when a lone ESC byte has been idle longer than the escape timeout.
  void flushPendingEscape() {
    if (_buffer.length == 1 && _buffer.first == 0x1b) {
      _buffer.clear();
      emit(const KeyEvent(KeyKind.escape));
    }
  }

  void _drain() {
    while (_buffer.isNotEmpty) {
      final byte = _buffer.first;
      if (byte == 0x1b) {
        if (!_parseEscape()) return;
        continue;
      }
      if (byte == 0x0d) {
        _buffer.removeAt(0);
        emit(const KeyEvent(KeyKind.enter));
        continue;
      }
      if (byte == 0x0a) {
        _buffer.removeAt(0);
        emit(const KeyEvent(KeyKind.enter));
        continue;
      }
      if (byte == 0x09) {
        _buffer.removeAt(0);
        emit(const KeyEvent(KeyKind.tab));
        continue;
      }
      if (byte == 0x7f || byte == 0x08) {
        _buffer.removeAt(0);
        emit(const KeyEvent(KeyKind.backspace));
        continue;
      }
      if (byte == 0x00) {
        _buffer.removeAt(0);
        emit(const KeyEvent(KeyKind.char, char: ' ', ctrl: true));
        continue;
      }
      if (byte < 0x20) {
        _buffer.removeAt(0);
        final letter = String.fromCharCode(byte + 0x60);
        emit(KeyEvent(KeyKind.char, char: letter, ctrl: true));
        continue;
      }
      if (!_parseUtf8Rune()) return;
    }
  }

  bool _parseUtf8Rune() {
    final byte = _buffer.first;
    var length = 1;
    if (byte & 0xe0 == 0xc0) {
      length = 2;
    } else if (byte & 0xf0 == 0xe0) {
      length = 3;
    } else if (byte & 0xf8 == 0xf0) {
      length = 4;
    }
    if (_buffer.length < length) return false;
    final bytes = _buffer.sublist(0, length);
    _buffer.removeRange(0, length);
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.isEmpty) return true;
    for (final rune in text.runes) {
      emit(KeyEvent(KeyKind.char, char: String.fromCharCode(rune)));
    }
    return true;
  }

  /// Returns false when more bytes are required.
  bool _parseEscape() {
    if (_buffer.length == 1) return false;
    final second = _buffer[1];

    if (second == 0x5b) return _parseCsi();
    if (second == 0x4f) return _parseSs3();
    if (second == 0x5d) return _parseOsc();
    if (second == 0x1b) {
      _buffer.removeAt(0);
      emit(const KeyEvent(KeyKind.escape));
      return true;
    }
    // ESC + printable => alt+char
    if (second >= 0x20) {
      _buffer.removeAt(0);
      if (_buffer.isNotEmpty) {
        final lead = _buffer.first;
        var length = 1;
        if (lead & 0xe0 == 0xc0) {
          length = 2;
        } else if (lead & 0xf0 == 0xe0) {
          length = 3;
        } else if (lead & 0xf8 == 0xf0) {
          length = 4;
        }
        if (_buffer.length < length) return false;
        final bytes = _buffer.sublist(0, length);
        _buffer.removeRange(0, length);
        final text = utf8.decode(bytes, allowMalformed: true);
        for (final rune in text.runes) {
          emit(KeyEvent(
            KeyKind.char,
            char: String.fromCharCode(rune),
            alt: true,
          ));
        }
        return true;
      }
      return false;
    }
    _buffer.removeAt(0);
    emit(const KeyEvent(KeyKind.escape));
    return true;
  }

  /// OSC: ESC ] ... (BEL | ESC \\) - used for the terminal colour reports.
  bool _parseOsc() {
    var end = -1;
    var terminatorLength = 0;
    for (var i = 2; i < _buffer.length; i++) {
      if (_buffer[i] == 0x07) {
        end = i;
        terminatorLength = 1;
        break;
      }
      if (_buffer[i] == 0x1b &&
          i + 1 < _buffer.length &&
          _buffer[i + 1] == 0x5c) {
        end = i;
        terminatorLength = 2;
        break;
      }
    }
    if (end < 0) return false;
    final body = String.fromCharCodes(_buffer.sublist(2, end));
    _buffer.removeRange(0, end + terminatorLength);
    _emitOsc(body);
    return true;
  }

  void _emitOsc(String body) {
    final separator = body.indexOf(';');
    if (separator <= 0) return;
    final code = body.substring(0, separator);
    if (code != '10' && code != '11') return;
    final colour = _parseColorSpec(body.substring(separator + 1));
    if (colour == null) return;
    emit(ColorReportEvent(
      red: colour.$1,
      green: colour.$2,
      blue: colour.$3,
      isBackground: code == '11',
    ));
  }

  /// Parses `rgb:RRRR/GGGG/BBBB` (xterm) and `#RRGGBB` styles.
  (int, int, int)? _parseColorSpec(String spec) {
    final value = spec.trim();
    if (value.startsWith('rgb:')) {
      final parts = value.substring(4).split('/');
      if (parts.length != 3) return null;
      int? channel(String hex) {
        if (hex.isEmpty) return null;
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed == null) return null;
        // xterm replies with 4 hex digits per channel.
        return hex.length <= 2 ? parsed : (parsed >> 8).clamp(0, 255);
      }

      final red = channel(parts[0]);
      final green = channel(parts[1]);
      final blue = channel(parts[2]);
      if (red == null || green == null || blue == null) return null;
      return (red, green, blue);
    }
    if (value.startsWith('#') && value.length >= 7) {
      final parsed = int.tryParse(value.substring(1, 7), radix: 16);
      if (parsed == null) return null;
      return ((parsed >> 16) & 0xff, (parsed >> 8) & 0xff, parsed & 0xff);
    }
    return null;
  }

  bool _parseSs3() {
    if (_buffer.length < 3) return false;
    final finalByte = _buffer[2];
    _buffer.removeRange(0, 3);
    const map = {
      0x41: KeyKind.up,
      0x42: KeyKind.down,
      0x43: KeyKind.right,
      0x44: KeyKind.left,
      0x48: KeyKind.home,
      0x46: KeyKind.end,
      0x50: KeyKind.f1,
      0x51: KeyKind.f2,
      0x52: KeyKind.f3,
      0x53: KeyKind.f4,
    };
    final kind = map[finalByte];
    if (kind != null) emit(KeyEvent(kind));
    return true;
  }

  bool _parseCsi() {
    // CSI: ESC [ params final
    var index = 2;
    while (index < _buffer.length) {
      final byte = _buffer[index];
      if (byte >= 0x40 && byte <= 0x7e) break;
      index++;
    }
    if (index >= _buffer.length) return false;
    final finalByte = _buffer[index];
    final body = String.fromCharCodes(_buffer.sublist(2, index));

    if (finalByte == 0x4d && body.isEmpty) {
      // X10 mouse: ESC [ M b x y
      if (_buffer.length < index + 4) return false;
      final cb = _buffer[index + 1] - 32;
      final cx = _buffer[index + 2] - 32;
      final cy = _buffer[index + 3] - 32;
      _buffer.removeRange(0, index + 4);
      _emitMouse(cb, cx, cy, pressOnly: true);
      return true;
    }
    if (body.startsWith('<')) {
      // SGR mouse: ESC [ < b ; x ; y M/m
      final coords = body.substring(1).split(';');
      if (coords.length != 3) {
        _buffer.removeRange(0, index + 1);
        return true;
      }
      final cb = int.tryParse(coords[0]) ?? 0;
      final cx = (int.tryParse(coords[1]) ?? 1) - 1;
      final cy = (int.tryParse(coords[2]) ?? 1) - 1;
      _buffer.removeRange(0, index + 1);
      _emitMouse(cb, cx, cy, pressOnly: finalByte == 0x4d);
      return true;
    }

    _buffer.removeRange(0, index + 1);
    _emitCsi(finalByte, body);
    return true;
  }

  void _emitCsi(int finalByte, String body) {
    final params =
        body.isEmpty ? <int>[] : body.split(';').map(int.tryParse).toList();
    var modifier = 1;
    if (params.length >= 2 && params.last != null) {
      modifier = params.last ?? 1;
    }
    final shift = (modifier - 1) & 1 != 0;
    final alt = (modifier - 1) & 2 != 0;
    final ctrl = (modifier - 1) & 4 != 0;

    KeyEvent? key(KeyKind kind) => KeyEvent(
          kind,
          shift: shift,
          alt: alt,
          ctrl: ctrl,
        );

    switch (finalByte) {
      case 0x41:
        emit(key(KeyKind.up)!);
      case 0x42:
        emit(key(KeyKind.down)!);
      case 0x43:
        emit(key(KeyKind.right)!);
      case 0x44:
        emit(key(KeyKind.left)!);
      case 0x48:
        emit(key(KeyKind.home)!);
      case 0x46:
        emit(key(KeyKind.end)!);
      case 0x5a:
        emit(const KeyEvent(KeyKind.tab, shift: true));
      case 0x7e:
        final code = params.isEmpty ? 0 : (params.first ?? 0);
        const map = {
          1: KeyKind.home,
          2: KeyKind.insert,
          3: KeyKind.delete,
          4: KeyKind.end,
          5: KeyKind.pageUp,
          6: KeyKind.pageDown,
          7: KeyKind.home,
          8: KeyKind.end,
          11: KeyKind.f1,
          12: KeyKind.f2,
          13: KeyKind.f3,
          14: KeyKind.f4,
          15: KeyKind.f5,
          17: KeyKind.f6,
          18: KeyKind.f7,
          19: KeyKind.f8,
          20: KeyKind.f9,
          21: KeyKind.f10,
          23: KeyKind.f11,
          24: KeyKind.f12,
        };
        final kind = map[code];
        if (kind != null) emit(key(kind)!);
    }
  }

  void _emitMouse(int cb, int x, int y, {required bool pressOnly}) {
    final shift = cb & 4 != 0;
    final alt = cb & 8 != 0;
    final ctrl = cb & 16 != 0;
    final motion = cb & 32 != 0;
    final wheel = cb & 64 != 0;
    final raw = cb & 3;

    if (wheel) {
      emit(MouseEvent(
        kind: MouseKind.wheel,
        x: x,
        y: y,
        wheelDelta: raw == 0 ? -1 : 1,
        shift: shift,
        alt: alt,
        ctrl: ctrl,
      ));
      return;
    }
    if (motion) {
      emit(MouseEvent(
        kind: MouseKind.move,
        x: x,
        y: y,
        button: _button(raw),
        shift: shift,
        alt: alt,
        ctrl: ctrl,
      ));
      return;
    }
    emit(MouseEvent(
      kind: pressOnly ? MouseKind.press : MouseKind.release,
      x: x,
      y: y,
      button: raw == 3 ? MouseButton.none : _button(raw),
      shift: shift,
      alt: alt,
      ctrl: ctrl,
    ));
  }

  static MouseButton _button(int raw) => switch (raw) {
        0 => MouseButton.left,
        1 => MouseButton.middle,
        2 => MouseButton.right,
        _ => MouseButton.none,
      };
}
