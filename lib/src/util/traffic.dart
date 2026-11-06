/// Shared formatting for subscription traffic quotas.
library;

import 'format.dart';

class TrafficSummary {
  const TrafficSummary({
    required this.bar,
    required this.text,
    this.fraction,
  });

  final String bar;
  final String text;
  final double? fraction;

  String get display => '$bar $text';
}

/// Builds an ASCII progress bar plus a "used / total | remaining | expiry"
/// summary. Returns null when the provider reports no traffic data.
TrafficSummary? summarizeTraffic({
  required int? used,
  required int? total,
  DateTime? expire,
  int barWidth = 16,
}) {
  if (used == null && total == null) return null;
  double? fraction;
  var filled = 0;
  if (total != null && total > 0) {
    fraction = ((used ?? 0) / total).clamp(0.0, 1.0);
    filled = (fraction * barWidth).round().clamp(0, barWidth);
  }
  final bar = '[${'#' * filled}${'-' * (barWidth - filled)}]';
  final parts = <String>[];
  if (used != null && total != null && total > 0) {
    final remaining = total - used < 0 ? 0 : total - used;
    parts.add(
      '已用 ${formatBytes(used)} / ${formatBytes(total)} | 剩余 ${formatBytes(remaining)}',
    );
  } else if (used != null) {
    parts.add('已用 ${formatBytes(used)}');
  }
  if (expire != null) {
    final days = expire.difference(DateTime.now()).inDays;
    final date = '${expire.year}-${_two(expire.month)}-${_two(expire.day)}';
    parts.add('到期 $date${days >= 0 ? '（$days 天）' : '（已过期）'}');
  }
  return TrafficSummary(bar: bar, text: parts.join(' | '), fraction: fraction);
}

String _two(int value) => value.toString().padLeft(2, '0');
