import 'package:mihomo_tui/src/util/log_entry.dart';
import 'package:test/test.dart';

void main() {
  test('parses structured mihomo lines', () {
    final entry = LogEntry.parse(
      'time="2026-11-05T16:30:02.837496477+08:00" level=info '
      'msg="Mixed(http+socks) proxy listening at: 127.0.0.1:17890"',
    );
    expect(entry.time, '16:30:02');
    expect(entry.level, 'info');
    expect(
        entry.message, 'Mixed(http+socks) proxy listening at: 127.0.0.1:17890');
    expect(entry.tag, 'INFO');
  });

  test('parses warnings and keeps quotes stripped', () {
    final entry = LogEntry.parse(
      'time="2026-11-05T16:30:02.123+08:00" level=warning msg="shutting down"',
    );
    expect(entry.level, 'warning');
    expect(entry.tag, 'WARN');
    expect(entry.message, 'shutting down');
  });

  test('handles lines without time', () {
    final entry = LogEntry.parse('level=error msg="boom"');
    expect(entry.time, isNull);
    expect(entry.level, 'error');
    expect(entry.tag, 'ERR ');
  });

  test('handles bracketed and plain lines', () {
    final bracketed = LogEntry.parse('[Debug] some detail');
    expect(bracketed.level, 'debug');
    expect(bracketed.message, 'some detail');
    expect(bracketed.tag, 'DBG ');

    final plain = LogEntry.parse('furuda level message');
    expect(plain.level, 'info');
    expect(plain.message, 'furuda level message');
  });

  test('unescapes quotes and newlines', () {
    final entry = LogEntry.parse(
      r'time="2026-01-01T00:00:00Z" level=info msg="say \"hi\"\nnext"',
    );
    expect(entry.message, 'say "hi" next');
  });
}
