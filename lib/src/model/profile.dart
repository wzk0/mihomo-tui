/// A subscription profile managed by the app.
library;

class Profile {
  const Profile({
    required this.name,
    required this.url,
    this.updatedAt,
    this.size,
  });

  final String name;
  final String url;
  final DateTime? updatedAt;
  final int? size;

  Profile copyWith({
    String? name,
    String? url,
    DateTime? updatedAt,
    int? size,
  }) {
    return Profile(
      name: name ?? this.name,
      url: url ?? this.url,
      updatedAt: updatedAt ?? this.updatedAt,
      size: size ?? this.size,
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'url': url,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (size != null) 'size': size,
      };

  static Profile? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final url = json['url'];
    if (name is! String || name.isEmpty) return null;
    final updated = json['updatedAt'];
    DateTime? updatedAt;
    if (updated is String) updatedAt = DateTime.tryParse(updated);
    final size = json['size'];
    return Profile(
      name: name,
      url: url is String ? url : '',
      updatedAt: updatedAt,
      size: size is int ? size : null,
    );
  }
}

/// Rejects names that cannot safely become file names.
String? validateProfileName(String name) {
  if (name.trim().isEmpty) return '名称不能为空';
  if (name.trim() != name) return '名称首尾不能有空格';
  if (name.length > 64) return '名称过长（最多 64 个字符）';
  const invalid = r'<>:"/\|?*';
  for (final rune in name.runes) {
    final char = String.fromCharCode(rune);
    if (rune < 0x20 || invalid.contains(char)) {
      return '名称不能包含 $char 或控制字符';
    }
  }
  if (name.endsWith('.')) return '名称不能以点结尾';
  const reserved = {
    'CON', 'PRN', 'AUX', 'NUL', //
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };
  if (reserved.contains(name.toUpperCase())) return '该名称是系统保留名';
  return null;
}

String? validateSubscriptionUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '订阅地址不能为空';
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return '订阅地址无效';
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '仅支持 http/https 订阅地址';
  }
  if (uri.host.isEmpty) return '订阅地址缺少主机名';
  return null;
}
