/// Cursor + viewport bookkeeping shared by the list views.
library;

/// Keeps a selection and a scroll offset consistent: the cursor is always
/// inside the viewport and the viewport never scrolls past the last item, so
/// lists never render trailing blank rows.
class ListState {
  ListState({this.selected = 0, this.scroll = 0});

  int selected;
  int scroll;

  int total = 0;
  int visible = 1;

  int get maxScroll => total > visible ? total - visible : 0;

  /// Updates the bounds and clamps both cursor and scroll offset.
  void bind({required int total, required int visible}) {
    this.total = total < 0 ? 0 : total;
    this.visible = visible < 1 ? 1 : visible;
    if (selected >= this.total) selected = this.total == 0 ? 0 : this.total - 1;
    if (selected < 0) selected = 0;
    if (scroll > maxScroll) scroll = maxScroll;
    if (scroll < 0) scroll = 0;
  }

  /// Scrolls the viewport, dragging the cursor along when it would leave it.
  void wheel(int delta) {
    if (delta == 0) return;
    scroll = (scroll + delta).clamp(0, maxScroll);
    if (selected < scroll) selected = scroll;
    if (selected >= scroll + visible) selected = scroll + visible - 1;
    if (selected >= total) selected = total == 0 ? 0 : total - 1;
  }

  /// Moves the cursor by [delta] (wrapping) and keeps it visible.
  void moveBy(int delta) {
    if (total == 0) return;
    selected = (selected + delta) % total;
    if (selected < 0) selected += total;
    ensureVisible();
  }

  void ensureVisible() {
    if (selected < scroll) scroll = selected;
    if (selected >= scroll + visible) scroll = selected - visible + 1;
    if (scroll > maxScroll) scroll = maxScroll;
    if (scroll < 0) scroll = 0;
  }

  void select(int index) {
    if (total == 0) return;
    selected = index.clamp(0, total - 1);
    ensureVisible();
  }

  void reset() {
    selected = 0;
    scroll = 0;
  }
}
