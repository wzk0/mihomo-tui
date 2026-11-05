/// Structured parsing of mihomo log lines.
library;

class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.message,
    required this.raw,
  });

  final String? time;
  final String level;
  final String message;
  final String raw;

  String get tag => switch (level) {
        'error' || 'fatal' => 'ERR ',
        'warning' || 'warn' => 'WARN',
        'debug' || 'trace' => 'DBG ',
        _ => 'INFO',
      };

  /// Understands mihomo's `time="~" level=info msg="~"` and plain fallbacks.
  static LogEntry parse(String raw) {
    final structured = RegExp(
      r'^time="([^"]*)"\s+level=([A-Za-z]+)\s+msg=(.*)$',
    ).firstMatch(raw);
    if (structured != null) {
      return LogEntry(
        time: _shortTime(structured.group(1)!),
        level: structured.group(2)!.toLowerCase(),
        message: _cleanMessage(structured.group(3)!),
        raw: raw,
      );
    }
    final levelOnly = RegExp(
      r'level=([A-Za-z]+)\s+msg=(.*)$',
    ).firstMatch(raw);
    if (levelOnly != null) {
      return LogEntry(
        time: null,
        level: levelOnly.group(1)!.toLowerCase(),
        message: _cleanMessage(levelOnly.group(2)!),
        raw: raw,
      );
    }
    final bracketed = RegExp(r'^\[([A-Za-z]+)\]\s*(.*)$').firstMatch(raw);
    if (bracketed != null) {
      return LogEntry(
        time: null,
        level: bracketed.group(1)!.toLowerCase(),
        message: bracketed.group(2)!,
        raw: raw,
      );
    }
    return LogEntry(time: null, level: 'info', message: raw, raw: raw);
  }

  static String _cleanMessage(String value) {
    var message = value.trim();
    if (message.length >= 2 &&
        message.startsWith('"') &&
        message.endsWith('"')) {
      message = message.substring(1, message.length - 1);
    }
    return message.replaceAll(r'\"', '"').replaceAll(r'\n', ' ');
  }

  static String? _shortTime(String value) {
    if (value.isEmpty) return null;
    final match = RegExp(r'(\d{2}:\d{2}:\d{2})').firstMatch(value);
    return match?.group(1);
  }
}
