/// URL normalisation (including IDN → punycode) for subscription links.
library;

/// Converts a host that may contain non-ASCII labels (e.g. `例子.中国`) into
/// its ASCII / punycode form (`xn--fsqu00a.xn--fiqs8s`), so `dart:io` can
/// resolve it. Returns null when the host cannot be converted.
String? idnaToAscii(String host) {
  if (host.isEmpty) return null;
  final labels = host.split('.');
  final ascii = <String>[];
  for (final label in labels) {
    if (label.isEmpty) return null;
    if (label.runes.every((rune) => rune < 0x80)) {
      ascii.add(label.toLowerCase());
      continue;
    }
    final encoded = _punycode(label);
    if (encoded == null) return null;
    ascii.add('xn--$encoded');
  }
  return ascii.join('.');
}

// ---- RFC 3492 punycode -----------------------------------------------------

const int _base = 36;
const int _tMin = 1;
const int _tMax = 26;
const int _skew = 38;
const int _damp = 700;
const int _initialBias = 72;
const int _initialN = 128;

int _adapt(int delta, int numPoints, bool firstTime) {
  var value = firstTime ? delta ~/ _damp : delta ~/ 2;
  value += value ~/ numPoints;
  var k = 0;
  while (value > ((_base - _tMin) * _tMax) ~/ 2) {
    value ~/= _base - _tMin;
    k += _base;
  }
  return k + (((_base - _tMin + 1) * value) ~/ (value + _skew));
}

String _digit(int value) => value < 26
    ? String.fromCharCode(0x61 + value)
    : String.fromCharCode(0x30 + value - 26);

String? _punycode(String label) {
  final input = label.runes.toList();
  final output = StringBuffer();
  for (final rune in input) {
    if (rune < 0x80) output.writeCharCode(rune);
  }
  final basicCount = output.length;
  var handled = basicCount;
  if (basicCount > 0) output.write('-');

  var n = _initialN;
  var delta = 0;
  var bias = _initialBias;
  while (handled < input.length) {
    var next = 0x7fffffff;
    for (final rune in input) {
      if (rune >= n && rune < next) next = rune;
    }
    if (next == 0x7fffffff) return null;
    delta += (next - n) * (handled + 1);
    n = next;
    for (final rune in input) {
      if (rune < n) delta++;
      if (rune != n) continue;
      var q = delta;
      for (var k = _base;; k += _base) {
        final t = k <= bias ? _tMin : (k >= bias + _tMax ? _tMax : k - bias);
        if (q < t) break;
        output.write(_digit(t + (q - t) % (_base - t)));
        q = (q - t) ~/ (_base - t);
      }
      output.write(_digit(q));
      bias = _adapt(delta, handled + 1, handled == basicCount);
      delta = 0;
      handled++;
    }
    delta++;
    n++;
  }
  return output.toString();
}

/// Normalises a user supplied http(s) URL.
///
/// - trims whitespace / invisible characters / surrounding quotes
/// - adds `https://` when the scheme is missing
/// - converts internationalised hostnames to punycode so `dart:io` can use them
///
/// Returns null when the value is not a usable http(s) URL.
Uri? normalizeHttpUri(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  text = text.replaceAll(
    RegExp(r'[\u200b-\u200f\u202a-\u202e\ufeff]'),
    '',
  );
  text = text.replaceAll(RegExp(r'''^[<"“”'\s]+|[>"“”'\s]+$'''), '');
  if (text.isEmpty) return null;
  if (!text.contains('://')) {
    if (!RegExp(r'^[\w.\-]+(:\d+)?(/|$)').hasMatch(text)) return null;
    text = 'https://$text';
  }
  final parsed = Uri.tryParse(text);
  if (parsed == null) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  var host = parsed.host;
  if (host.isEmpty) return null;

  final needsIdna = host.contains('%') || host.runes.any((r) => r > 0x7f);
  if (needsIdna) {
    final decoded = Uri.decodeComponent(host);
    final ascii = idnaToAscii(decoded);
    if (ascii == null) return null;
    host = ascii;
  }
  final isIpv6 = host.contains(':');
  final validHost = isIpv6
      ? RegExp(r'^\[?[0-9a-fA-F:.%]+\]?$').hasMatch(host)
      : RegExp(
          r'^[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?'
          r'(\.[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?)*$',
        ).hasMatch(host);
  if (!validHost) return null;
  try {
    return parsed.replace(host: host);
  } catch (_) {
    return null;
  }
}
