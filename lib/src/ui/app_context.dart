/// The surface the views are allowed to use, implemented by `App`.
library;

import '../model/profile.dart';
import '../model/profile_info.dart';
import '../model/settings.dart';
import '../service/autostart.dart';
import '../service/core_updater.dart';
import '../service/mihomo_api.dart';
import '../service/mihomo_core.dart';
import '../service/system_proxy.dart';
import '../service/paths.dart';
import '../service/profile_repo.dart';
import '../term/terminal.dart';
import 'overlay.dart';
import 'theme.dart';

enum ToastLevel { info, success, warning, error }

abstract class AppContext {
  Theme get theme;
  TerminalBackend get terminal;
  AppPaths get paths;
  Settings get settings;
  ProfileRepository get repo;
  MihomoCore get core;

  CoreStatus? get coreStatus;

  /// Id of the interactive region currently under the mouse pointer.
  String? get hoverId;
  MihomoApi? get apiRef;
  bool get apiOnline;
  String? get apiVersion;
  ApiConfig? get apiConfig;
  ProxySnapshot? get proxySnapshot;
  ConnectionsInfo? get connections;
  ProfileInfo? get activeInfo;
  DateTime? get coreStartedAt;

  bool get busy;
  String? get busyLabel;

  void requestFrame();

  /// Switches to the view at [index] and focuses the content pane.
  void openView(int index);

  Future<void> refresh();

  void toast(String message, {ToastLevel level = ToastLevel.info});

  void showOverlay(Overlay overlay);

  void confirm({
    required String title,
    required String message,
    List<String> detail = const [],
    String confirmLabel = '确认',
    bool danger = false,
    required void Function() onConfirm,
  });

  Future<void> startCore();

  Future<void> stopCore();

  Future<void> restartCore();

  Future<void> activateProfile(Profile profile);

  /// Edits the subscription metadata (name / url).
  Future<void> editProfileMeta(Profile profile);

  /// Edits the downloaded subscription file (`profiles/<name>.yaml`).
  Future<void> editProfile(Profile profile);

  /// Edits the config mihomo actually loads (`<home>/config.yaml`).
  Future<void> editActiveConfig();

  Future<void> updateProfile(Profile profile);

  void openUrl(String url);

  bool copyToClipboard(String text);

  Future<void> reloadConfig();

  Future<void> setMode(String mode);

  Future<void> applySettings(Settings next);

  Future<void> cycleThemeAccent();

  Future<void> cycleColorMode();

  Future<void> toggleSystemProxy();

  /// Current OS proxy state (cached, refreshed periodically).
  SystemProxyState get systemProxyState;

  /// First non-loopback IPv4 address (for the LAN proxy row).
  String? get lanAddress;

  /// Toggles mihomo's `allow-lan` through the controller.
  Future<void> toggleAllowLan();

  /// Login/boot autostart state of the core.
  AutostartState get autostartState;

  Future<void> toggleAutostart();

  /// Downloads the newest mihomo release for this platform (via the selected
  /// mirror) and installs it over the current binary.
  Future<void> updateCore();

  /// Reachability results per mirror id (may be empty / stale).
  Map<String, MirrorProbe> get mirrorProbes;

  bool isMirrorProbing(String id);

  /// Opens the mirror picker and refreshes the connectivity results.
  void showMirrorPicker();

  Future<void> exportData();

  /// Leaves the TUI while keeping the mihomo core running.
  void hideToBackground();

  /// Downloads a profile's config into mihomo's config.yaml and optionally
  /// starts the core.
  Future<void> addProfileInteractive();
}
