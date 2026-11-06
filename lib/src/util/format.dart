/// Small formatting helpers shared by the UI.
library;

import 'dart:io';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

/// Compact byte size for table cells: `12.3G`, `850M`, `1.0T`.
String formatBytesShort(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  const units = ['K', 'M', 'G', 'T', 'P'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text =
      value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text${units[unit]}';
}

String formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 0) return '--';
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h ${minutes % 60}m';
  final days = hours ~/ 24;
  return '${days}d ${hours % 24}h';
}

String formatRelative(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final delta = reference.difference(time);
  if (delta.isNegative) return '刚刚';
  if (delta.inSeconds < 60) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes} 分钟前';
  if (delta.inHours < 24) return '${delta.inHours} 小时前';
  if (delta.inDays < 30) return '${delta.inDays} 天前';
  return '${time.year}-${_two(time.month)}-${_two(time.day)}';
}

String formatDateTime(DateTime time) =>
    '${time.year}-${_two(time.month)}-${_two(time.day)} '
    '${_two(time.hour)}:${_two(time.minute)}';

String _two(int value) => value.toString().padLeft(2, '0');

/// Short platform label such as `linux x64` / `windows arm64`.
String platformLabel() {
  final version = Platform.version;
  final arch = version.contains('arm64') || version.contains('aarch64')
      ? 'arm64'
      : version.contains('arm')
          ? 'arm'
          : version.contains('x64')
              ? 'x64'
              : 'unknown';
  return '${Platform.operatingSystem} $arch';
}
