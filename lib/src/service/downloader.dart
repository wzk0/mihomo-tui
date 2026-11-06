/// HTTP downloads for subscriptions, honouring proxy environment variables.
library;

import 'dart:async';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../util/net.dart' as net;
import '../util/url.dart';

/// Traffic / expiry reported by a provider through the
/// `Subscription-Userinfo` response header.
class SubscriptionInfo {
  const SubscriptionInfo({
    this.upload = 0,
    this.download = 0,
    this.total,
    this.expireAt,
  });

  final int upload;
  final int download;
  final int? total;
  final DateTime? expireAt;

  int get used => upload + download;

  /// Remaining traffic in bytes (null when the provider does not report it).
  int? get remaining {
    final total = this.total;
    if (total == null || total <= 0) return null;
    final left = total - used;
    return left < 0 ? 0 : left;
  }

  double? get fraction {
    final total = this.total;
    if (total == null || total <= 0) return null;
    return (used / total).clamp(0.0, 1.0);
  }

  bool get hasAny => total != null || upload > 0 || download > 0;

  /// Parses `upload=1; download=2; total=3; expire=1700000000`.
  static SubscriptionInfo? parse(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    int? number(String key) {
      final match = RegExp('$key=(-?\\d+)').firstMatch(header);
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    final upload = number('upload') ?? 0;
    final download = number('download') ?? 0;
    final total = number('total');
    final expire = number('expire');
    if (upload == 0 && download == 0 && total == null && expire == null) {
      return null;
    }
    return SubscriptionInfo(
      upload: upload,
      download: download,
      total: total,
      expireAt: expire == null || expire <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expire * 1000),
    );
  }
}

class DownloadResult {
  const DownloadResult({required this.bytes, this.info});

  final int bytes;
  final SubscriptionInfo? info;
}

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
  /// configuration. Returns the bytes written plus provider traffic info.
  Future<DownloadResult> fetchToFile(
    String url,
    File target, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    final uri = normalizeHttpUri(url);
    if (uri == null) {
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
      final HttpClientRequest request;
      try {
        request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      } on FormatException catch (error) {
        throw DownloadException(
          '订阅地址无法解析（主机名可能包含中文或 % 编码）：${error.message}',
        );
      } on ArgumentError catch (error) {
        throw DownloadException('订阅地址无法解析：${error.message}');
      }
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DownloadException('服务器返回 HTTP ${response.statusCode}');
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      final userInfo = SubscriptionInfo.parse(
        response.headers.value('subscription-userinfo'),
      );
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
      return DownloadResult(bytes: received, info: userInfo);
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
