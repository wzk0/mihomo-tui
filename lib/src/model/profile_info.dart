/// Parsed view of a mihomo configuration file.
library;

import 'package:yaml/yaml.dart';

class ProfileInfo {
  const ProfileInfo({
    required this.mixedPort,
    required this.port,
    required this.socksPort,
    required this.tproxyPort,
    required this.redirPort,
    required this.mode,
    required this.externalController,
    required this.secret,
    required this.externalUi,
    required this.allowLan,
    required this.ipv6,
    required this.tunEnabled,
    required this.nodeCount,
    required this.groupCount,
    required this.ruleCount,
    required this.providerCount,
    required this.logLevel,
    required this.finalMatchTarget,
  });

  final int? mixedPort;
  final int? port;
  final int? socksPort;
  final int? tproxyPort;
  final int? redirPort;
  final String mode;
  final String? externalController;
  final String? secret;
  final String? externalUi;
  final bool allowLan;
  final bool ipv6;
  final bool tunEnabled;
  final int nodeCount;
  final int groupCount;
  final int ruleCount;
  final int providerCount;
  final String? logLevel;

  /// Target of the last `MATCH,<target>` rule, i.e. the default proxy group.
  final String? finalMatchTarget;

  static ProfileInfo parse(String content) {
    final dynamic document;
    try {
      document = loadYaml(content);
    } on YamlException catch (error) {
      throw FormatException('配置不是合法的 YAML：${error.message}');
    }
    if (document is! YamlMap) {
      throw const FormatException('配置文件顶层不是映射（map）');
    }

    int? readPort(String key) {
      final value = document[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    bool readBool(String key) {
      final value = document[key];
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.toLowerCase();
        return normalized == 'true' || normalized == 'yes' || normalized == '1';
      }
      return false;
    }

    String? readString(String key) {
      final value = document[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is int) return value.toString();
      return null;
    }

    final proxies = document['proxies'];
    final groups = document['proxy-groups'];
    final rules = document['rules'];
    final providers = document['proxy-providers'];
    final tun = document['tun'];

    String? matchTarget;
    if (rules is YamlList) {
      for (final rule in rules) {
        if (rule is! String) continue;
        final fields = rule.split(',');
        if (fields.length >= 2 &&
            fields.first.trim().toUpperCase() == 'MATCH') {
          matchTarget = fields[1].trim();
        }
      }
    }

    return ProfileInfo(
      mixedPort: readPort('mixed-port'),
      port: readPort('port'),
      socksPort: readPort('socks-port'),
      tproxyPort: readPort('tproxy-port'),
      redirPort: readPort('redir-port'),
      mode: readString('mode') ?? 'rule',
      externalController: readString('external-controller'),
      secret: readString('secret'),
      externalUi: readString('external-ui'),
      allowLan: readBool('allow-lan'),
      ipv6: readBool('ipv6'),
      tunEnabled: tun is YamlMap && tun['enable'] == true,
      nodeCount: proxies is YamlList ? proxies.length : 0,
      groupCount: groups is YamlList ? groups.length : 0,
      ruleCount: rules is YamlList ? rules.length : 0,
      providerCount: providers is YamlMap ? providers.length : 0,
      logLevel: readString('log-level'),
      finalMatchTarget: matchTarget,
    );
  }

  /// Preferred local proxy port for `http_proxy` style variables.
  int? get preferredProxyPort => mixedPort ?? port ?? socksPort;

  List<String> get portSummary {
    final parts = <String>[];
    if (mixedPort != null) parts.add('mixed $mixedPort');
    if (port != null) parts.add('http $port');
    if (socksPort != null) parts.add('socks $socksPort');
    if (tproxyPort != null) parts.add('tproxy $tproxyPort');
    if (redirPort != null) parts.add('redir $redirPort');
    return parts;
  }

  /// `host:port` of the RESTful controller, normalised from common spellings.
  String? get controllerAddress {
    final raw = externalController;
    if (raw == null) return null;
    var value = raw;
    if (value.startsWith('http://')) value = value.substring(7);
    if (value.startsWith('https://')) value = value.substring(8);
    if (value.startsWith(':')) {
      return '127.0.0.1$value';
    }
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final host = parts[0];
    if (host == '0.0.0.0' || host == '::' || host == '[::]') {
      return '127.0.0.1:${parts[1]}';
    }
    return value;
  }

  String? get apiBase {
    final address = controllerAddress;
    if (address == null) return null;
    return 'http://$address';
  }

  String? get panelUrl {
    final address = controllerAddress;
    if (address == null) return null;
    final query = <String, String>{
      'hostname': address.split(':').first,
      'port': address.split(':').last,
      if (secret != null) 'secret': secret!,
    };
    if (externalUi != null) {
      return 'http://$address/ui/';
    }
    final uri = Uri.https('metacubex.github.io', '/metacubexd/', {
      'hostname': query['hostname']!,
      'port': query['port']!,
      if (query['secret'] != null) 'secret': query['secret']!,
    });
    return uri.toString();
  }
}
