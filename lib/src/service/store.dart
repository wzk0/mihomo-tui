/// `data.json` - profile list plus the currently selected profile.
library;

import 'dart:convert';
import 'dart:io';

import '../model/profile.dart';

class AppData {
  AppData({List<Profile>? profiles, this.active})
      : profiles = profiles ?? <Profile>[];

  List<Profile> profiles;

  /// Name of the profile that was last copied to mihomo's config.yaml.
  String? active;

  Profile? get activeProfile {
    for (final profile in profiles) {
      if (profile.name == active) return profile;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'active': active,
        'profiles': profiles.map((p) => p.toJson()).toList(),
      };

  static AppData fromJson(Object? json) {
    if (json is List) {
      // Legacy format: a bare list of {name, url} objects.
      return AppData(
        profiles: json
            .map(Profile.fromJson)
            .whereType<Profile>()
            .toList(growable: true),
      );
    }
    if (json is Map) {
      final rawProfiles = json['profiles'];
      final profiles = <Profile>[];
      if (rawProfiles is List) {
        for (final item in rawProfiles) {
          final profile = Profile.fromJson(item);
          if (profile != null) profiles.add(profile);
        }
      }
      return AppData(
        profiles: profiles,
        active: json['active'] is String ? json['active'] as String : null,
      );
    }
    return AppData();
  }
}

class DataStore {
  DataStore(this.path);

  final String path;

  AppData load() {
    final file = File(path);
    if (!file.existsSync()) return AppData();
    try {
      return AppData.fromJson(jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return AppData();
    }
  }

  void save(AppData data) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
    );
    tmp.renameSync(path);
  }
}
