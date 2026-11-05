/// Profile CRUD, activation and inspection.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import '../model/profile.dart';
import '../model/profile_info.dart';
import '../model/settings.dart';
import 'downloader.dart';
import 'paths.dart';
import 'store.dart';

class ProfileException implements Exception {
  ProfileException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProfileRepository {
  ProfileRepository({
    required this.paths,
    required Settings settings,
    Downloader Function()? downloaderFactory,
  })  : settings = settings,
        _downloaderFactory = downloaderFactory ??
            (() => Downloader(proxy: settings.downloadProxy)) {
    _store = DataStore(paths.dataFile);
    data = _store.load();
  }

  final AppPaths paths;
  Settings settings;
  final Downloader Function() _downloaderFactory;
  late final DataStore _store;
  final Map<String, _CachedInfo> _infoCache = {};
  late AppData data;

  List<Profile> get profiles => data.profiles;

  String? get activeName => data.active;

  Profile? get activeProfile => data.activeProfile;

  String profileFile(String name) =>
      '${paths.profilesDir}${Platform.pathSeparator}$name.yaml';

  bool profileExists(String name) => File(profileFile(name)).existsSync();

  int? profileSize(String name) {
    final file = File(profileFile(name));
    if (!file.existsSync()) return null;
    try {
      return file.lengthSync();
    } catch (_) {
      return null;
    }
  }

  Profile? byName(String name) {
    for (final profile in data.profiles) {
      if (profile.name == name) return profile;
    }
    return null;
  }

  void reload() {
    data = _store.load();
  }

  void _persist() => _store.save(data);

  /// Parsed info cached by file modification time; null when the file is
  /// missing or invalid (see [cachedError]).
  ProfileInfo? cachedInfo(String name) {
    final file = File(profileFile(name));
    if (!file.existsSync()) return null;
    DateTime stamp;
    try {
      stamp = file.statSync().modified;
    } catch (_) {
      return null;
    }
    final cached = _infoCache[name];
    if (cached != null && cached.stamp == stamp) return cached.info;
    ProfileInfo? info;
    String? error;
    try {
      info = ProfileInfo.parse(file.readAsStringSync());
    } on FormatException catch (failure) {
      error = failure.message;
    } catch (failure) {
      error = failure.toString();
    }
    _infoCache[name] = _CachedInfo(stamp, info, error);
    return info;
  }

  String? cachedError(String name) {
    cachedInfo(name);
    return _infoCache[name]?.error;
  }

  void invalidateCache(String? name) {
    if (name == null) {
      _infoCache.clear();
    } else {
      _infoCache.remove(name);
    }
  }

  /// Reads the profile file and parses it. Throws [ProfileException] when the
  /// file is missing or invalid.
  ProfileInfo loadInfo(String name) {
    final file = File(profileFile(name));
    if (!file.existsSync()) {
      throw ProfileException('配置「$name」文件不存在');
    }
    final content = file.readAsStringSync();
    try {
      return ProfileInfo.parse(content);
    } on FormatException catch (error) {
      throw ProfileException(error.message);
    }
  }

  String readContent(String name) {
    final file = File(profileFile(name));
    if (!file.existsSync()) throw ProfileException('配置「$name」文件不存在');
    return file.readAsStringSync();
  }

  Future<void> add({
    required String name,
    required String url,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final nameError = validateProfileName(name);
    if (nameError != null) throw ProfileException(nameError);
    final urlError = validateSubscriptionUrl(url);
    if (urlError != null) throw ProfileException(urlError);
    if (byName(name) != null) throw ProfileException('已存在同名配置「$name」');

    final target = File(profileFile(name));
    final bytes = await _downloaderFactory().fetchToFile(
      url.trim(),
      target,
      onProgress: onProgress,
    );
    ProfileInfo info;
    try {
      info = ProfileInfo.parse(target.readAsStringSync());
    } on FormatException catch (error) {
      if (target.existsSync()) target.deleteSync();
      throw ProfileException(error.message);
    }
    if (info.nodeCount == 0 &&
        info.providerCount == 0 &&
        info.groupCount == 0) {
      if (target.existsSync()) target.deleteSync();
      throw ProfileException('订阅中没有找到任何节点或代理组');
    }
    data.profiles.add(Profile(
      name: name,
      url: url.trim(),
      updatedAt: DateTime.now(),
      size: bytes,
    ));
    invalidateCache(name);
    _persist();
  }

  Future<void> update(
    Profile profile, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    final urlError = validateSubscriptionUrl(profile.url);
    if (urlError != null) throw ProfileException('「${profile.name}」$urlError');
    final bytes = await _downloaderFactory().fetchToFile(
      profile.url,
      File(profileFile(profile.name)),
      onProgress: onProgress,
    );
    final index = data.profiles.indexWhere((p) => p.name == profile.name);
    if (index >= 0) {
      data.profiles[index] = data.profiles[index].copyWith(
        updatedAt: DateTime.now(),
        size: bytes,
      );
      invalidateCache(profile.name);
      _persist();
    }
  }

  /// Updates the editable metadata (name / subscription url) of a profile.
  /// The file is renamed when the name changes; the url is not downloaded here.
  Profile updateMeta(
    Profile profile, {
    required String name,
    required String url,
  }) {
    final nameError = validateProfileName(name);
    if (nameError != null) throw ProfileException(nameError);
    final urlError = validateSubscriptionUrl(url);
    if (urlError != null) throw ProfileException(urlError);

    var current = profile;
    if (name != profile.name) {
      if (byName(name) != null) throw ProfileException('已存在同名配置「$name」');
      rename(profile, name);
      current = byName(name)!;
    }
    final index = data.profiles.indexWhere((p) => p.name == current.name);
    if (index >= 0) {
      data.profiles[index] = data.profiles[index].copyWith(url: url.trim());
      current = data.profiles[index];
      _persist();
    }
    return current;
  }

  void rename(Profile profile, String newName) {
    final error = validateProfileName(newName);
    if (error != null) throw ProfileException(error);
    if (newName == profile.name) return;
    if (byName(newName) != null) throw ProfileException('已存在同名配置「$newName」');
    final from = File(profileFile(profile.name));
    if (from.existsSync()) {
      from.renameSync(profileFile(newName));
    }
    final index = data.profiles.indexWhere((p) => p.name == profile.name);
    if (index >= 0) {
      data.profiles[index] = data.profiles[index].copyWith(name: newName);
    }
    if (data.active == profile.name) data.active = newName;
    invalidateCache(profile.name);
    invalidateCache(newName);
    _persist();
  }

  void delete(Profile profile) {
    final file = File(profileFile(profile.name));
    if (file.existsSync()) file.deleteSync();
    data.profiles.removeWhere((p) => p.name == profile.name);
    if (data.active == profile.name) data.active = null;
    invalidateCache(profile.name);
    _persist();
  }

  /// Copies [profile] into mihomo's `config.yaml` and records it as active.
  void activate(Profile profile) {
    final source = File(profileFile(profile.name));
    if (!source.existsSync()) {
      throw ProfileException('配置「${profile.name}」文件不存在');
    }
    try {
      ProfileInfo.parse(source.readAsStringSync());
    } on FormatException catch (error) {
      throw ProfileException(error.message);
    }
    final home = Directory(paths.mihomoHome);
    home.createSync(recursive: true);
    final target = File(paths.mihomoConfigFile);
    if (target.existsSync()) {
      try {
        target.copySync('${target.path}.bak');
      } catch (_) {}
    }
    source.copySync(target.path);
    data.active = profile.name;
    _persist();
  }

  /// Imports legacy data created by the original python tool, if present.
  int importLegacy(String legacyDir) {
    var imported = 0;
    final dataFile = File('$legacyDir${Platform.pathSeparator}data.json');
    if (!dataFile.existsSync()) return 0;
    try {
      final legacy = DataStore(dataFile.path).load();
      for (final profile in legacy.profiles) {
        if (byName(profile.name) != null) continue;
        final source = File(
          '$legacyDir${Platform.pathSeparator}config'
          '${Platform.pathSeparator}${profile.name}',
        );
        if (!source.existsSync()) continue;
        Directory(paths.profilesDir).createSync(recursive: true);
        source.copySync(profileFile(profile.name));
        data.profiles.add(profile.copyWith(
          size: profileSize(profile.name),
          updatedAt: profile.updatedAt ?? DateTime.now(),
        ));
        imported++;
      }
      if (imported > 0) _persist();
    } catch (_) {
      // Legacy import is best effort.
    }
    return imported;
  }

  /// Ensures directories exist and pre-creates an empty legacy-compatible file.
  void ensureLayout() {
    for (final dir in [
      paths.configDir,
      paths.profilesDir,
      paths.logsDir,
      paths.runDir
    ]) {
      Directory(dir).createSync(recursive: true);
    }
    if (!File(paths.dataFile).existsSync()) _persist();
  }

  static ProfileInfo parseContent(String content) {
    try {
      final dynamic document = loadYaml(content);
      if (document is! YamlMap) {
        throw const FormatException('配置文件顶层不是映射（map）');
      }
    } on YamlException catch (error) {
      throw FormatException('配置不是合法的 YAML：${error.message}');
    }
    return ProfileInfo.parse(content);
  }
}

class _CachedInfo {
  _CachedInfo(this.stamp, this.info, this.error);

  final DateTime stamp;
  final ProfileInfo? info;
  final String? error;
}
