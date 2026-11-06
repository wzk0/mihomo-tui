/// Shared HTTP proxy helpers for outbound downloads.
library;

import 'dart:io';

/// Returns the proxy directive for [target] based on the standard proxy
/// environment variables, or null when direct access should be used.
/// Loopback targets are never proxied.
String? envProxyDirective(Uri target, {String? explicit}) {
  if (_isLoopback(target.host)) return null;
  final raw =
      (explicit == null || explicit.trim().isEmpty) ? envProxy() : explicit;
  if (raw == null) return null;
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
  if (uri == null || uri.host.isEmpty) return null;
  // A host containing '%' (percent encoded / mangled proxy value) would make
  // dart:io throw "is not a valid link-local address"; ignore it instead.
  if (uri.host.contains('%') || uri.host.runes.any((r) => r > 0x7f)) {
    return null;
  }
  final port = uri.hasPort ? uri.port : 80;
  return 'PROXY ${uri.host}:$port';
}

/// First usable proxy URL from the environment (socks entries are skipped
/// because [HttpClient] only understands HTTP proxies).
String? envProxy() {
  final env = Platform.environment;
  for (final key in [
    'https_proxy',
    'HTTPS_PROXY',
    'all_proxy',
    'ALL_PROXY',
    'http_proxy',
    'HTTP_PROXY',
  ]) {
    final value = env[key];
    if (value == null || value.trim().isEmpty) continue;
    if (value.startsWith('socks')) continue;
    return value.trim();
  }
  return null;
}

bool _isLoopback(String host) =>
    host == 'localhost' ||
    host == '127.0.0.1' ||
    host == '::1' ||
    host == '[::1]';
