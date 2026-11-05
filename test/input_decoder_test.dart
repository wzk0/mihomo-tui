import 'dart:convert';

import 'package:mihomo_tui/src/term/input_decoder.dart';
import 'package:mihomo_tui/src/term/keys.dart';
import 'package:test/test.dart';

AnsiInputDecoder collecting(List<TermEvent> sink) => AnsiInputDecoder(sink.add);

void main() {
  test('single bytes map to keys', () {
    final events = <TermEvent>[];
    final decoder = collecting(events);
    decoder.add([0x0d, 0x09, 0x7f]);
    expect(events.length, 3);
    expect((events[0] as KeyEvent).kind, KeyKind.enter);
    expect((events[1] as KeyEvent).kind, KeyKind.tab);
    expect((events[2] as KeyEvent).kind, KeyKind.backspace);
  });

  test('ctrl+letter and ctrl+c', () {
    final events = <TermEvent>[];
    collecting(events).add([0x03]);
    expect((events.single as KeyEvent).ctrl, isTrue);
    expect((events.single as KeyEvent).char, 'c');
  });

  test('arrow keys and modified arrows', () {
    final events = <TermEvent>[];
    final decoder = collecting(events);
    decoder.add(utf8.encode('\x1b[A\x1b[B\x1b[1;5C'));
    expect((events[0] as KeyEvent).kind, KeyKind.up);
    expect((events[1] as KeyEvent).kind, KeyKind.down);
    final ctrlRight = events[2] as KeyEvent;
    expect(ctrlRight.kind, KeyKind.right);
    expect(ctrlRight.ctrl, isTrue);
  });

  test('home/end/delete/page keys', () {
    final events = <TermEvent>[];
    collecting(events).add(utf8.encode('\x1b[H\x1b[4~\x1b[3~\x1b[5~\x1b[6~'));
    expect((events[0] as KeyEvent).kind, KeyKind.home);
    expect((events[1] as KeyEvent).kind, KeyKind.end);
    expect((events[2] as KeyEvent).kind, KeyKind.delete);
    expect((events[3] as KeyEvent).kind, KeyKind.pageUp);
    expect((events[4] as KeyEvent).kind, KeyKind.pageDown);
  });

  test('SS3 function keys', () {
    final events = <TermEvent>[];
    collecting(events).add(utf8.encode('\x1bOP\x1bOQ'));
    expect((events[0] as KeyEvent).kind, KeyKind.f1);
    expect((events[1] as KeyEvent).kind, KeyKind.f2);
  });

  test('alt+char', () {
    final events = <TermEvent>[];
    collecting(events).add(utf8.encode('\x1bx'));
    final event = events.single as KeyEvent;
    expect(event.char, 'x');
    expect(event.alt, isTrue);
  });

  test('utf8 multibyte characters', () {
    final events = <TermEvent>[];
    final decoder = collecting(events);
    final bytes = utf8.encode('中');
    decoder.add([bytes[0]]);
    expect(events, isEmpty);
    decoder.add(bytes.sublist(1));
    expect((events.single as KeyEvent).char, '中');
  });

  test('SGR mouse press and release', () {
    final events = <TermEvent>[];
    collecting(events).add(utf8.encode('\x1b[<0;10;5M\x1b[<0;10;5m'));
    final press = events[0] as MouseEvent;
    expect(press.kind, MouseKind.press);
    expect(press.button, MouseButton.left);
    expect(press.x, 9);
    expect(press.y, 4);
    expect((events[1] as MouseEvent).kind, MouseKind.release);
  });

  test('wheel direction', () {
    final events = <TermEvent>[];
    collecting(events).add(utf8.encode('\x1b[<64;3;3M\x1b[<65;3;3M'));
    expect((events[0] as MouseEvent).wheelDelta, -1);
    expect((events[1] as MouseEvent).wheelDelta, 1);
  });

  test('x10 mouse encoding', () {
    final events = <TermEvent>[];
    collecting(events).add([0x1b, 0x5b, 0x4d, 32 + 0, 32 + 4, 32 + 2]);
    final click = events.single as MouseEvent;
    expect(click.kind, MouseKind.press);
    expect(click.x, 4);
    expect(click.y, 2);
  });

  test('split escape sequences wait for the rest', () {
    final events = <TermEvent>[];
    final decoder = collecting(events);
    decoder.add([0x1b]);
    expect(events, isEmpty);
    expect(decoder.hasOnlyEscape, isTrue);
    decoder.add([0x5b]);
    expect(events, isEmpty);
    decoder.add([0x41]);
    expect((events.single as KeyEvent).kind, KeyKind.up);
  });

  test('lone escape flushes as Escape', () {
    final events = <TermEvent>[];
    final decoder = collecting(events);
    decoder.add([0x1b]);
    decoder.flushPendingEscape();
    expect((events.single as KeyEvent).kind, KeyKind.escape);
  });

  group('OSC colour reports', () {
    test('background reply with BEL terminator', () {
      final events = <TermEvent>[];
      collecting(events).add(utf8.encode('\x1b]11;rgb:1a1a/1b1b/1c1c\x07'));
      final report = events.single as ColorReportEvent;
      expect(report.isBackground, isTrue);
      expect(report.red, 0x1a);
      expect(report.green, 0x1b);
      expect(report.blue, 0x1c);
      expect(report.isLight, isFalse);
    });

    test('light background reply with ST terminator', () {
      final events = <TermEvent>[];
      collecting(events).add(utf8.encode('\x1b]11;rgb:ffff/ffff/ffff\x1b\\'));
      final report = events.single as ColorReportEvent;
      expect(report.isLight, isTrue);
      expect(report.luminance, greaterThan(0.9));
    });

    test('foreground reply is flagged as foreground', () {
      final events = <TermEvent>[];
      collecting(events).add(utf8.encode('\x1b]10;#ffffff\x07'));
      final report = events.single as ColorReportEvent;
      expect(report.isBackground, isFalse);
      expect(report.red, 255);
    });

    test('unrelated OSC sequences are ignored', () {
      final events = <TermEvent>[];
      collecting(events)
        ..add(utf8.encode('\x1b]0;window title\x07'))
        ..add(utf8.encode('\x1b]4;1;rgb:0000/0000/0000\x07'));
      expect(events, isEmpty);
    });

    test('reports split across reads are reassembled', () {
      final events = <TermEvent>[];
      final decoder = collecting(events);
      final bytes = utf8.encode('\x1b]11;rgb:0000/0000/0000\x1b\\');
      decoder.add(bytes.sublist(0, 6));
      expect(events, isEmpty);
      decoder.add(bytes.sublist(6));
      expect(events.single, isA<ColorReportEvent>());
    });
  });
}
