/// HTTP downloads for subscriptions, honouring proxy environment variables.
library;

import 'dart:async';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../util/net.dart' as net;

class DownloadException implements Exception {
  DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DownloadProgress {
  const DownloadProgress(this.received, this.total);

  final int received;
  final int? total;

  double? get fraction {
    final total = this.total;
    if (total == null || total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }
}

class Downloader {
  Downloader({
    this.proxy,
    this.userAgent = 'clash.meta/mihomo-tui',
    this.cancelled,
  });

  /// Explicit proxy (`http://host:port`). When null, standard proxy
  /// environment variables are inspected.
  final String? proxy;
  final String userAgent;
  final bool Function()? cancelled;

  static String? envProxy() => net.envProxy();

  String? _proxyDirective(Uri target) =>
      net.envProxyDirective(target, explicit: proxy);

  /// Downloads [url] into [target], validating that the body is a mihomo
  /// configuration. Returns the number of bytes written.
  Future<int> fetchToFile(
    String url,
    File target, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw DownloadException('订阅地址无效：$url');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = userAgent
      ..idleTimeout = const Duration(seconds: 5);
    final directive = _proxyDirective(uri);
    if (directive != null) client.findProxy = (_) => directive;

    File? temp;
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DownloadException('服务器返回 HTTP ${response.statusCode}');
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      temp = File('${target.path}.part');
      temp.parent.createSync(recursive: true);
      final sink = temp.openWrite();
      var received = 0;
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      try {
        await for (final chunk in response) {
          if (cancelled?.call() ?? false) throw DownloadException('已取消');
          if (DateTime.now().isAfter(deadline)) {
            throw DownloadException('下载超时');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(DownloadProgress(received, total));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0) throw DownloadException('下载内容为空');

      final content = await temp.readAsString();
      if (content.trim().isEmpty) throw DownloadException('下载内容为空');
      final dynamic parsed;
      try {
        parsed = loadYaml(content);
      } on YamlException catch (error) {
        throw DownloadException('订阅内容不是合法的 YAML：${error.message}');
      }
      if (parsed is! YamlMap) {
        throw DownloadException('订阅内容不是有效的 mihomo 配置');
      }

      target.parent.createSync(recursive: true);
      if (target.existsSync()) target.deleteSync();
      await temp.rename(target.path);
      temp = null;
      return received;
    } on SocketException catch (error) {
      throw DownloadException('网络错误：${error.message}');
    } on HandshakeException catch (error) {
      throw DownloadException('TLS 握手失败：${error.message}');
    } on TimeoutException {
      throw DownloadException('连接超时');
    } finally {
      client.close(force: true);
      if (temp != null && temp.existsSync()) {
        try {
          temp.deleteSync();
        } catch (_) {}
      }
    }
  }
}
