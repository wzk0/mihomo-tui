/// System clipboard access (best effort, no native plugins).
library;

import 'dart:convert';
import 'dart:io';

class Clipboard {
  Clipboard._();

  /// Commands that read the clipboard, tried in order.
  static final List<List<String>> _readers = [
    if (Platform.isMacOS) ['pbpaste'],
    if (Platform.isWindows)
      [
        'powershell',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-Clipboard -Raw',
      ],
    if (!Platform.isMacOS && !Platform.isWindows) ...[
      ['wl-paste', '--no-newline'],
      ['xclip', '-o', '-selection', 'clipboard'],
      ['xsel', '-o', '--clipboard'],
    ],
  ];

  /// Commands that write the clipboard, tried in order.
  static final List<List<String>> _writers = [
    if (Platform.isMacOS) ['pbcopy'],
    if (Platform.isWindows) ['clip'],
    if (!Platform.isMacOS && !Platform.isWindows) ...[
      ['wl-copy'],
      ['xclip', '-selection', 'clipboard'],
      ['xsel', '--clipboard', '--input'],
    ],
  ];

  static bool get canWrite => _writers.any((c) => _exists(c.first));

  /// Reads the clipboard as text; null when unavailable.
  static Future<String?> read() async {
    for (final command in _readers) {
      if (!_exists(command.first)) continue;
      try {
        final result =
            await Process.run(command.first, command.skip(1).toList());
        if (result.exitCode != 0) continue;
        return '${result.stdout}';
      } on ProcessException {
        continue;
      }
    }
    return null;
  }

  /// Copies [text] to the clipboard.
  static Future<bool> write(String text) async {
    for (final command in _writers) {
      if (!_exists(command.first)) continue;
      Process? process;
      try {
        process = await Process.start(command.first, command.skip(1).toList());
        process.stdin.add(utf8.encode(text));
        await process.stdin.flush();
        await process.stdin.close();
        final code = await process.exitCode
            .timeout(const Duration(seconds: 5), onTimeout: () => -1);
        if (code == 0) return true;
        continue;
      } catch (_) {
        try {
          process?.kill();
        } catch (_) {}
        continue;
      }
    }
    return false;
  }

  static bool _exists(String executable) {
    final path = Platform.environment['PATH'] ?? '';
    for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final candidate = File('$dir${Platform.pathSeparator}$executable');
      if (candidate.existsSync()) return true;
      if (Platform.isWindows) {
        final exe = File('$dir\\$executable.exe');
        if (exe.existsSync()) return true;
      }
    }
    return false;
  }
}
