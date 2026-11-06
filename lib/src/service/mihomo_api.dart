/// RESTful controller client for the mihomo (Clash.Meta) API.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ProxyNode {
  const ProxyNode({
    required this.name,
    required this.type,
    this.now,
    this.all = const [],
    this.delay,
    this.alive = true,
  });

  final String name;
  final String type;
  final String? now;
  final List<String> all;
  final int? delay;
  final bool alive;

  bool get isGroup => all.isNotEmpty;
}

class ProxySnapshot {
  const ProxySnapshot({required this.groups, required this.nodes});

  final List<ProxyNode> groups;
  final Map<String, ProxyNode> nodes;
}

class ApiConfig {
  const ApiConfig({
    this.mode,
    this.logLevel,
    this.mixedPort,
    this.port,
    this.socksPort,
    this.allowLan,
  });

  final String? mode;
  final String? logLevel;
  final int? mixedPort;
  final int? port;
  final int? socksPort;
  final bool? allowLan;

  static ApiConfig fromJson(Map<String, Object?> json) {
    int? port(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    return ApiConfig(
      mode: json['mode'] as String?,
      logLevel: json['log-level'] as String?,
      mixedPort: port('mixed-port'),
      port: port('port'),
      socksPort: port('socks-port'),
      allowLan: json['allow-lan'] as bool?,
    );
  }
}

class ConnectionsInfo {
  const ConnectionsInfo({
    required this.count,
    required this.uploadTotal,
    required this.downloadTotal,
  });

  final int count;
  final int uploadTotal;
  final int downloadTotal;
}

class MihomoApi {
  MihomoApi({required this.baseUrl, this.secret});

  final String baseUrl;
  final String? secret;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..idleTimeout = const Duration(seconds: 5);

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: path,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<Object?> _request(
    String method,
    Uri uri, {
    Object? body,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final request = await _client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (secret != null && secret!.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $secret',
        );
      }
      if (body != null) {
        final payload = jsonEncode(body);
        request.headers.contentLength = utf8.encode(payload).length;
        request.add(utf8.encode(payload));
      }
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'HTTP ${response.statusCode}${text.isEmpty ? '' : '：${text.trim()}'}',
          statusCode: response.statusCode,
        );
      }
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } on SocketException {
      throw ApiException('无法连接 mihomo 控制器');
    } on TimeoutException {
      throw ApiException('请求 mihomo 控制器超时');
    } on FormatException {
      throw ApiException('控制器返回了无法解析的数据');
    }
  }

  Future<bool> ping() async {
    try {
      await _request('GET', _uri('/version'));
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<String?> version() async {
    final json = await _request('GET', _uri('/version'));
    if (json is Map && json['version'] is String) {
      return json['version'] as String;
    }
    return null;
  }

  Future<ApiConfig> configs() async {
    final json = await _request('GET', _uri('/configs'));
    if (json is Map<String, Object?>) return ApiConfig.fromJson(json);
    if (json is Map) return ApiConfig.fromJson(json.cast<String, Object?>());
    throw ApiException('控制器返回了无效的配置数据');
  }

  Future<void> setMode(String mode) async {
    await _request('PATCH', _uri('/configs'), body: {'mode': mode});
  }

  /// Toggles `allow-lan` on the running core.
  Future<void> setAllowLan(bool enabled) async {
    await _request('PATCH', _uri('/configs'), body: {'allow-lan': enabled});
  }

  Future<void> reload() async {
    await _request(
      'PUT',
      _uri('/configs', {'force': 'true'}),
      body: {'path': '', 'payload': ''},
      timeout: const Duration(seconds: 10),
    );
  }

  Future<ProxySnapshot> proxies() async {
    final json = await _request('GET', _uri('/proxies'));
    if (json is! Map || json['proxies'] is! Map) {
      throw ApiException('控制器返回了无效的代理数据');
    }
    final raw = (json['proxies'] as Map).cast<String, Object?>();
    final nodes = <String, ProxyNode>{};
    final groups = <ProxyNode>[];
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final data = (entry.value as Map).cast<String, Object?>();
      final all = <String>[];
      final rawAll = data['all'];
      if (rawAll is List) {
        for (final item in rawAll) {
          if (item is String) all.add(item);
        }
      }
      int? delay;
      final history = data['history'];
      if (history is List && history.isNotEmpty) {
        final last = history.last;
        if (last is Map && last['delay'] is num) {
          delay = (last['delay'] as num).toInt();
        }
      }
      final node = ProxyNode(
        name: entry.key,
        type: data['type'] is String ? data['type'] as String : '',
        now: data['now'] is String && (data['now'] as String).trim().isNotEmpty
            ? data['now'] as String
            : null,
        all: all,
        delay: delay,
        alive: data['alive'] is bool ? data['alive'] as bool : true,
      );
      nodes[entry.key] = node;
      if (node.isGroup) groups.add(node);
    }
    groups.sort((a, b) => a.name.compareTo(b.name));
    return ProxySnapshot(groups: groups, nodes: nodes);
  }

  Future<void> select(String group, String node) async {
    await _request(
      'PUT',
      _uri('/proxies/${Uri.encodeComponent(group)}'),
      body: {'name': node},
    );
  }

  Future<int?> delay(
    String name, {
    int timeoutMs = 5000,
    String url = 'http://www.gstatic.com/generate_204',
  }) async {
    final json = await _request(
      'GET',
      _uri('/proxies/${Uri.encodeComponent(name)}/delay', {
        'timeout': '$timeoutMs',
        'url': url,
      }),
      timeout: Duration(milliseconds: timeoutMs + 2000),
    );
    if (json is Map && json['delay'] is num) {
      return (json['delay'] as num).toInt();
    }
    return null;
  }

  Future<ConnectionsInfo> connections() async {
    final json = await _request('GET', _uri('/connections'));
    if (json is! Map) throw ApiException('控制器返回了无效的连接数据');
    final connections = json['connections'];
    return ConnectionsInfo(
      count: connections is List ? connections.length : 0,
      uploadTotal: (json['uploadTotal'] as num?)?.toInt() ?? 0,
      downloadTotal: (json['downloadTotal'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> closeAllConnections() async {
    await _request('DELETE', _uri('/connections'));
  }

  void dispose() => _client.close(force: true);
}
