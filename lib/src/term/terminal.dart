/// Terminal backend: raw mode, alternate screen, mouse reporting and events.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'input_decoder.dart';
import 'keys.dart';
import 'win32.dart';

class TermSize {
  const TermSize(this.columns, this.rows);

  final int columns;
  final int rows;

  @override
  bool operator ==(Object other) =>
      other is TermSize && other.columns == columns && other.rows == rows;

  @override
  int get hashCode => Object.hash(columns, rows);

  @override
  String toString() => '${columns}x$rows';
}

abstract class TerminalBackend {
  Stream<TermEvent> get events;
  TermSize get size;

  /// Applies raw mode / alternate screen / mouse reporting.
  void start();

  /// Restores the terminal to its original state.
  void stop();

  /// Temporarily hands the terminal back to a child process (e.g. $EDITOR).
  void suspend();

  /// Re-acquires the terminal after [suspend].
  void resume();

  void write(String data);

  void setTitle(String title);

  /// Whether the terminal understands 24 bit colour.
  bool get supportsTrueColor;

  /// Asks the terminal for its background colour (OSC 11).
  /// Returns a packed 0xRRGGBB value, or null when it cannot be determined.
  Future<int?> probeBackgroundColor({
    Duration timeout = const Duration(milliseconds: 250),
  });

  /// True when interactive input could be set up.
  bool get isInteractive;
}

TerminalBackend createTerminal() {
  if (Platform.isWindows) return WindowsTerminal();
  return PosixTerminal();
}

bool _envTrueColor() {
  final colorTerm = Platform.environment['COLORTERM']?.toLowerCase() ?? '';
  if (colorTerm.contains('truecolor') || colorTerm.contains('24bit')) {
    return true;
  }
  final term = Platform.environment['TERM']?.toLowerCase() ?? '';
  if (term.contains('direct') || term.contains('24bit')) return true;
  final program = Platform.environment['TERM_PROGRAM']?.toLowerCase() ?? '';
  if (program.contains('iterm') ||
      program.contains('wezterm') ||
      program.contains('vscode') ||
      program.contains('windows terminal')) {
    return true;
  }
  // Windows Terminal / modern conhost handle truecolour.
  if (Platform.isWindows) return true;
  return false;
}

class PosixTerminal implements TerminalBackend {
  final _controller = StreamController<TermEvent>.broadcast();
  late final AnsiInputDecoder _decoder =
      AnsiInputDecoder((event) => _controller.add(event));
  StreamSubscription<List<int>>? _subscription;
  StreamSubscription<ProcessSignal>? _resizeSub;
  Timer? _escapeTimer;
  TermSize _size = const TermSize(100, 30);
  bool _originalEchoMode = false;
  bool _originalLineMode = true;
  bool _started = false;
  bool _suspended = false;

  @override
  Stream<TermEvent> get events => _controller.stream;

  @override
  TermSize get size => _querySize() ?? _size;

  @override
  bool get supportsTrueColor => _envTrueColor();

  @override
  bool get isInteractive => stdout.hasTerminal && stdin.hasTerminal;

  @override
  Future<int?> probeBackgroundColor({
    Duration timeout = const Duration(milliseconds: 250),
  }) async {
    final completer = Completer<int?>();
    late final StreamSubscription<TermEvent> subscription;
    subscription = _controller.stream.listen((event) {
      if (event is ColorReportEvent &&
          event.isBackground &&
          !completer.isCompleted) {
        completer.complete(
          (event.red << 16) | (event.green << 8) | event.blue,
        );
      }
    });
    try {
      write('\x1b]11;?\x1b\\');
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      await subscription.cancel();
    }
  }

  TermSize? _querySize() {
    try {
      final columns = stdout.terminalColumns;
      final rows = stdout.terminalLines;
      if (columns > 0 && rows > 0) {
        _size = TermSize(columns, rows);
        return _size;
      }
    } catch (_) {
      // Not a terminal.
    }
    final envColumns = int.tryParse(Platform.environment['COLUMNS'] ?? '');
    final envRows = int.tryParse(Platform.environment['LINES'] ?? '');
    if (envColumns != null && envRows != null) {
      _size = TermSize(envColumns, envRows);
      return _size;
    }
    return null;
  }

  @override
  void start() {
    if (_started) return;
    _started = true;
    _suspended = false;
    try {
      _originalEchoMode = stdin.echoMode;
      _originalLineMode = stdin.lineMode;
      stdin.echoMode = false;
      stdin.lineMode = false;
    } catch (_) {
      // stdin is not a terminal; keep going with whatever we get.
    }
    unawaited(_setSignalKeys(false));
    _querySize();
    stdout.write(
      '\x1b[?1049h'
      '\x1b[?25l'
      '\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h'
      '\x1b[2J\x1b[H',
    );
    _subscription = stdin.listen(
      _onBytes,
      onError: (Object _) {},
      cancelOnError: false,
    );
    if (!Platform.isWindows) {
      try {
        _resizeSub = ProcessSignal.sigwinch.watch().listen((_) {
          // Give the terminal a moment to settle, then report the real size.
          Timer(const Duration(milliseconds: 40), () {
            _querySize();
            _controller.add(ResizeEvent(size.columns, size.rows));
          });
        });
      } catch (_) {
        // SIGWINCH is unavailable on some platforms.
      }
    }
  }

  void _onBytes(List<int> bytes) {
    _decoder.add(bytes);
    _escapeTimer?.cancel();
    if (_decoder.hasOnlyEscape) {
      _escapeTimer = Timer(const Duration(milliseconds: 40), () {
        _decoder.flushPendingEscape();
      });
    }
  }

  @override
  void stop() {
    if (!_started) return;
    _started = false;
    _escapeTimer?.cancel();
    _escapeTimer = null;
    unawaited(_setSignalKeys(true));
    _subscription?.cancel();
    _subscription = null;
    _resizeSub?.cancel();
    _resizeSub = null;
    _safeWrite(
      '\x1b[0m'
      '\x1b[?1003l\x1b[?1002l\x1b[?1006l\x1b[?1000l'
      '\x1b[?25h'
      '\x1b[?1049l',
    );
    try {
      stdin.echoMode = _originalEchoMode;
      stdin.lineMode = _originalLineMode;
    } catch (_) {
      // Ignore.
    }
  }

  @override
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    // Pause (never cancel) the stdin subscription: dart:io's stdin can only be
    // listened to once, and cancelling it also detaches the child's stdin.
    _subscription?.pause();
    _resizeSub?.pause();
    _escapeTimer?.cancel();
    stdout.write(
      '\x1b[0m'
      '\x1b[?1003l\x1b[?1002l\x1b[?1006l\x1b[?1000l'
      '\x1b[?25h'
      '\x1b[?1049l',
    );
    try {
      stdin.echoMode = _originalEchoMode;
      stdin.lineMode = _originalLineMode;
    } catch (_) {}
    unawaited(_setSignalKeys(true));
    stdout.flush();
  }

  @override
  void resume() {
    if (!_suspended) return;
    _suspended = false;
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
    } catch (_) {}
    unawaited(_setSignalKeys(false));
    _querySize();
    _safeWrite(
      '\x1b[?1049h'
      '\x1b[?25l'
      '\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h'
      '\x1b[2J\x1b[H',
    );
    _subscription?.resume();
    _resizeSub?.resume();
  }

  void _safeWrite(String data) {
    try {
      stdout.write(data);
    } catch (_) {
      // The terminal may already be gone (e.g. SIGHUP while closing).
    }
  }

  /// Ctrl+C must reach the app as a key (copy inside text fields), so the
  /// terminal's ISIG flag is cleared while the TUI owns the tty.
  ///
  /// `stty` is run through `sh` with its own stdin redirected from /dev/tty:
  /// after the stdin subscription is cancelled our fd 0 may no longer be
  /// usable, and we never want stty's diagnostics on screen.
  Future<void> _setSignalKeys(bool enabled) async {
    final flag = enabled ? 'isig' : '-isig';
    try {
      await Process.run(
        'sh',
        ['-c', 'stty $flag < /dev/tty 2>/dev/null'],
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      // stty (or /dev/tty) unavailable: Ctrl+C keeps sending SIGINT.
    }
  }

  @override
  void write(String data) {
    try {
      stdout.add(utf8.encode(data));
    } catch (_) {
      // Ignore writes to a closed terminal.
    }
  }

  @override
  void setTitle(String title) {
    final clean = title.replaceAll(RegExp(r'[\x00-\x1f]'), '');
    write('\x1b]0;$clean\x07');
  }
}

/// Windows console backend: ANSI output with VT processing enabled, input read
/// through ReadConsoleInputW so that keys and mouse events are available.
class WindowsTerminal implements TerminalBackend {
  final _controller = StreamController<TermEvent>.broadcast();
  Timer? _timer;
  TermSize _size = const TermSize(100, 30);
  bool _started = false;
  bool _suspended = false;
  var _originalInputMode = 0;
  var _originalOutputMode = 0;
  int _inputHandle = 0;
  int _outputHandle = 0;
  final _buffer = calloc<Uint8>(20 * 64);
  final _recordCount = calloc<Uint32>();
  final _pendingEvents = calloc<Uint32>();

  @override
  Stream<TermEvent> get events => _controller.stream;

  @override
  TermSize get size {
    final current = _windowsSize();
    if (current != null) _size = current;
    return _size;
  }

  @override
  bool get supportsTrueColor => true;

  @override
  bool get isInteractive => stdout.hasTerminal;

  /// Approximate RGB values of the 16 legacy console background colours.
  static const _consolePalette = [
    0x0c0c0c,
    0xc50f1f,
    0x13a10e,
    0xc19c00,
    0x0037da,
    0x881798,
    0x3a96dd,
    0xcccccc,
    0x767676,
    0xe74856,
    0x16c60c,
    0xf9f1a5,
    0x3b78ff,
    0xb4009e,
    0x61d6d6,
    0xf2f2f2,
  ];

  @override
  Future<int?> probeBackgroundColor({
    Duration timeout = const Duration(milliseconds: 250),
  }) async {
    try {
      final attributes = Win32.instance.consoleAttributes();
      if (attributes == null) return null;
      final background = (attributes >> 4) & 0x0f;
      return _consolePalette[background];
    } catch (_) {
      return null;
    }
  }

  TermSize? _windowsSize() {
    try {
      final result = Win32.instance.consoleSize();
      if (result != null) return TermSize(result.columns, result.rows);
    } catch (_) {}
    return null;
  }

  void _applyModes() {
    final win = Win32.instance;
    _inputHandle = win.getStdHandle(stdInputHandle);
    _outputHandle = win.getStdHandle(stdOutputHandle);
    final mode = calloc<Uint32>();
    try {
      if (win.getConsoleMode(_inputHandle, mode) != 0) {
        _originalInputMode = mode.value;
        win.setConsoleMode(
          _inputHandle,
          enableExtendedFlags | enableWindowInput | enableMouseInput,
        );
      }
      if (win.getConsoleMode(_outputHandle, mode) != 0) {
        _originalOutputMode = mode.value;
        win.setConsoleMode(
          _outputHandle,
          mode.value | enableProcessedOutput | enableVirtualTerminalProcessing,
        );
      }
    } finally {
      calloc.free(mode);
    }
    win.setConsoleOutputCP(65001);
    win.setConsoleCP(65001);
  }

  void _restoreModes() {
    final win = Win32.instance;
    final mode = calloc<Uint32>();
    try {
      if (_originalInputMode != 0 &&
          win.getConsoleMode(_inputHandle, mode) != 0) {
        win.setConsoleMode(_inputHandle, _originalInputMode);
      }
      if (_originalOutputMode != 0 &&
          win.getConsoleMode(_outputHandle, mode) != 0) {
        win.setConsoleMode(_outputHandle, _originalOutputMode);
      }
    } finally {
      calloc.free(mode);
    }
  }

  @override
  void start() {
    if (_started) return;
    _started = true;
    _suspended = false;
    _applyModes();
    _size = _windowsSize() ?? _size;
    _safeWrite(
      '\x1b[?1049h'
      '\x1b[?25l'
      '\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h'
      '\x1b[2J\x1b[H',
    );
    _timer = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => _pump(),
    );
  }

  void _pump() {
    if (_suspended) return;
    final win = Win32.instance;
    final current = _windowsSize();
    if (current != null && current != _size) {
      _size = current;
      _controller.add(ResizeEvent(current.columns, current.rows));
    }
    if (win.getNumberOfConsoleInputEvents(_inputHandle, _pendingEvents) == 0) {
      return;
    }
    final count = _pendingEvents.value;
    if (count == 0) return;
    final toRead = count > 64 ? 64 : count;
    if (win.readConsoleInput(_inputHandle, _buffer, toRead, _recordCount) ==
        0) {
      return;
    }
    final data = _buffer.asTypedList(20 * _recordCount.value);
    final view = ByteData.sublistView(data);
    for (var i = 0; i < _recordCount.value; i++) {
      _handleRecord(view, i * 20);
    }
  }

  void _handleRecord(ByteData view, int base) {
    final type = view.getUint16(base, Endian.host);
    if (type == 0x0001) {
      final keyDown = view.getInt32(base + 4, Endian.host);
      if (keyDown == 0) return;
      final vk = view.getUint16(base + 10, Endian.host);
      final charCode = view.getUint16(base + 14, Endian.host);
      final control = view.getUint32(base + 16, Endian.host);
      final shift = control & 0x0010 != 0;
      final ctrl = control & 0x0008 != 0 || control & 0x0004 != 0;
      final alt = control & 0x0002 != 0 || control & 0x0001 != 0;
      final event = _mapKey(vk, charCode, ctrl: ctrl, alt: alt, shift: shift);
      if (event != null) _controller.add(event);
      return;
    }
    if (type == 0x0002) {
      final x = view.getInt16(base + 4, Endian.host);
      final y = view.getInt16(base + 6, Endian.host);
      final buttons = view.getUint32(base + 8, Endian.host);
      final control = view.getUint32(base + 12, Endian.host);
      final flags = view.getUint32(base + 16, Endian.host);
      final shift = control & 0x0010 != 0;
      final ctrl = control & 0x0008 != 0 || control & 0x0004 != 0;
      final alt = control & 0x0002 != 0 || control & 0x0001 != 0;
      if (flags & 0x0004 != 0) {
        final delta = (buttons >> 16) & 0xffff;
        final signed = delta >= 0x8000 ? delta - 0x10000 : delta;
        _controller.add(MouseEvent(
          kind: MouseKind.wheel,
          x: x,
          y: y,
          wheelDelta: signed > 0 ? -1 : 1,
          shift: shift,
          ctrl: ctrl,
          alt: alt,
        ));
        return;
      }
      final isMove = flags & 0x0001 != 0;
      final kind = isMove ? MouseKind.move : MouseKind.press;
      final button = buttons & 0x0001 != 0
          ? MouseButton.left
          : buttons & 0x0004 != 0
              ? MouseButton.middle
              : buttons & 0x0002 != 0
                  ? MouseButton.right
                  : MouseButton.none;
      _controller.add(MouseEvent(
        kind: kind,
        x: x,
        y: y,
        button: button,
        shift: shift,
        ctrl: ctrl,
        alt: alt,
      ));
    }
  }

  KeyEvent? _mapKey(
    int vk,
    int charCode, {
    required bool ctrl,
    required bool alt,
    required bool shift,
  }) {
    const specials = {
      0x25: KeyKind.left,
      0x26: KeyKind.up,
      0x27: KeyKind.right,
      0x28: KeyKind.down,
      0x24: KeyKind.home,
      0x23: KeyKind.end,
      0x21: KeyKind.pageUp,
      0x22: KeyKind.pageDown,
      0x2d: KeyKind.insert,
      0x2e: KeyKind.delete,
      0x0d: KeyKind.enter,
      0x08: KeyKind.backspace,
      0x09: KeyKind.tab,
      0x1b: KeyKind.escape,
      0x70: KeyKind.f1,
      0x71: KeyKind.f2,
      0x72: KeyKind.f3,
      0x73: KeyKind.f4,
      0x74: KeyKind.f5,
      0x75: KeyKind.f6,
      0x76: KeyKind.f7,
      0x77: KeyKind.f8,
      0x78: KeyKind.f9,
      0x79: KeyKind.f10,
      0x7a: KeyKind.f11,
      0x7b: KeyKind.f12,
    };
    final special = specials[vk];
    if (special != null) {
      return KeyEvent(special, ctrl: ctrl, alt: alt, shift: shift);
    }
    if (charCode == 0) return null;
    final char = String.fromCharCode(charCode);
    if (charCode < 0x20) {
      return KeyEvent(
        KeyKind.char,
        char: String.fromCharCode(charCode + 0x60),
        ctrl: true,
        alt: alt,
        shift: shift,
      );
    }
    return KeyEvent(
      KeyKind.char,
      char: char,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
    );
  }

  @override
  void stop() {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    _safeWrite(
      '\x1b[0m'
      '\x1b[?1003l\x1b[?1002l\x1b[?1006l\x1b[?1000l'
      '\x1b[?25h'
      '\x1b[?1049l',
    );
    _restoreModes();
    calloc
      ..free(_buffer)
      ..free(_recordCount)
      ..free(_pendingEvents);
  }

  @override
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    _safeWrite(
      '\x1b[0m'
      '\x1b[?1003l\x1b[?1002l\x1b[?1006l\x1b[?1000l'
      '\x1b[?25h'
      '\x1b[?1049l',
    );
    _restoreModes();
  }

  @override
  void resume() {
    if (!_suspended) return;
    _suspended = false;
    _applyModes();
    _size = _windowsSize() ?? _size;
    _safeWrite(
      '\x1b[?1049h'
      '\x1b[?25l'
      '\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h'
      '\x1b[2J\x1b[H',
    );
  }

  void _safeWrite(String data) {
    try {
      stdout.write(data);
    } catch (_) {
      // The terminal may already be gone (e.g. SIGHUP while closing).
    }
  }

  @override
  void write(String data) {
    try {
      stdout.add(utf8.encode(data));
    } catch (_) {
      // Ignore writes to a closed terminal.
    }
  }

  @override
  void setTitle(String title) {
    final clean = title.replaceAll(RegExp(r'[\x00-\x1f]'), '');
    write('\x1b]0;$clean\x07');
  }
}
