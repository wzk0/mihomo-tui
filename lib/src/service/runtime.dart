/// Builds the service graph shared by the TUI and the headless CLI commands.
library;

import 'dart:io';

import '../model/settings.dart';
import 'mihomo_core.dart';
import 'paths.dart';
import 'profile_repo.dart';

class Runtime {
  Runtime({
    required this.settings,
    required this.paths,
    required this.repo,
    required this.core,
  });

  final Settings settings;
  final AppPaths paths;
  final ProfileRepository repo;
  final MihomoCore core;

  factory Runtime.build({
    required Settings settings,
    String? configDir,
    String? mihomoHome,
    String? binaryOverride,
    String? editorOverride,
  }) {
    final paths = AppPaths(
      configDir: configDir ?? AppPaths.defaultConfigDir,
      mihomoHome:
          mihomoHome ?? settings.mihomoHome ?? AppPaths.defaultMihomoHome,
      mihomoBin: settings.mihomoBin,
      editor: editorOverride ?? settings.editor ?? AppPaths.defaultEditor,
    );
    return Runtime(
      settings: settings,
      paths: paths,
      repo: ProfileRepository(paths: paths, settings: settings),
      core: MihomoCore(
        paths: paths,
        binaryOverride: binaryOverride ?? settings.mihomoBin,
      ),
    );
  }

  static Settings loadSettings([String? configDir]) {
    final dir = configDir ?? AppPaths.defaultConfigDir;
    return Settings.load(
      '$dir${Platform.pathSeparator}settings.json',
    );
  }
}
