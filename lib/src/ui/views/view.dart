/// Common contract for the main content panes.
library;

import 'package:mihomo_tui/src/term/keys.dart';
import 'package:mihomo_tui/src/ui/app_context.dart';
import 'package:mihomo_tui/src/ui/overlay.dart';
import 'package:mihomo_tui/src/ui/painter.dart';

abstract class View {
  /// Label used in the sidebar.
  String get label;

  /// Title rendered on the content frame.
  String get title;

  List<KeyHint> hints(AppContext app);

  void draw(AppContext app, Painter painter, Rect area,
      {required bool focused});

  /// Returns true when the event was consumed.
  bool onKey(AppContext app, KeyEvent event);

  /// Called roughly once a second while this view is visible.
  void onTick(AppContext app) {}

  /// Wheel fallback: used when the pointer is over a non-interactive area of
  /// the view. Returns true when the view scrolled.
  bool onWheel(AppContext app, int delta) => false;

  void reset() {}
}
