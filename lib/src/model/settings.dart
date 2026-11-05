/// Persisted user settings.
library;

import 'dart:convert';
import 'dart:io';

class Settings {
  const Settings({
    this.mihomoBin,
    this.mihomoHome,
    this.editor,
    this.downloadProxy,
    this.accent,
    this.colorMode,
  });

  final String? mihomoBin;
  final String? mihomoHome;
  final String? editor;

  /// Explicit proxy for subscription downloads; empty means "use env".
  final String? downloadProxy;

  /// Accent colour preset id (see `Theme.accentOrder`).
  final String? accent;

  /// `auto`, `dark` or `light`.
  final String? colorMode;

  Settings copyWith({
    String? mihomoBin,
    String? mihomoHome,
    String? editor,
    String? downloadProxy,
    String? accent,
    String? colorMode,
    bool clearMihomoBin = false,
    bool clearMihomoHome = false,
    bool clearEditor = false,
    bool clearDownloadProxy = false,
    bool clearAccent = false,
    bool clearColorMode = false,
  }) {
    return Settings(
      mihomoBin: clearMihomoBin ? null : (mihomoBin ?? this.mihomoBin),
      mihomoHome: clearMihomoHome ? null : (mihomoHome ?? this.mihomoHome),
      editor: clearEditor ? null : (editor ?? this.editor),
      downloadProxy:
          clearDownloadProxy ? null : (downloadProxy ?? this.downloadProxy),
      accent: clearAccent ? null : (accent ?? this.accent),
      colorMode: clearColorMode ? null : (colorMode ?? this.colorMode),
    );
  }

  Map<String, Object?> toJson() => {
        'mihomoBin': mihomoBin,
        'mihomoHome': mihomoHome,
        'editor': editor,
        'downloadProxy': downloadProxy,
        'accent': accent,
        'colorMode': colorMode,
      };

  static Settings fromJson(Map<String, Object?> json) {
    String? read(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      return null;
    }

    return Settings(
      mihomoBin: read('mihomoBin'),
      mihomoHome: read('mihomoHome'),
      editor: read('editor'),
      downloadProxy: read('downloadProxy'),
      accent: read('accent'),
      colorMode: read('colorMode'),
    );
  }

  static Settings load(String path) {
    final file = File(path);
    if (!file.existsSync()) return const Settings();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, Object?>) return Settings.fromJson(decoded);
    } catch (_) {
      // Corrupt settings file: fall back to defaults.
    }
    return const Settings();
  }

  void save(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
    tmp.renameSync(path);
  }
}
