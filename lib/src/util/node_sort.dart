/// Ordering helpers for the proxy node list.
library;

import '../service/mihomo_api.dart';

/// How the node column is ordered.
enum NodeSortMode {
  original('默认'),
  delayAsc('延迟低到高'),
  delayDesc('延迟高到低');

  const NodeSortMode(this.label);

  final String label;

  NodeSortMode get next =>
      NodeSortMode.values[(index + 1) % NodeSortMode.values.length];
}

/// Returns [names] ordered according to [mode].
///
/// Groups sort last, untested nodes after timed-out ones, and equal ranks are
/// broken alphabetically so the order stays stable between refreshes.
List<String> orderNodeNames({
  required List<String> names,
  required NodeSortMode mode,
  required Map<String, ProxyNode> nodes,
  Map<String, int?> delays = const {},
}) {
  final ordered = [...names];
  if (mode == NodeSortMode.original) return ordered;

  /// Tier 0 = usable delay, 1 = timeout, 2 = untested, 3 = nested group.
  (int, int) key(String name) {
    final node = nodes[name];
    if (node != null && node.isGroup) return (3, 0);
    final delay = delays.containsKey(name) ? delays[name] : node?.delay;
    if (delay == null) return (2, 0);
    if (delay == 0) return (1, 0);
    return (0, delay);
  }

  ordered.sort((a, b) {
    final ka = key(a);
    final kb = key(b);
    if (ka.$1 != kb.$1) return ka.$1.compareTo(kb.$1);
    if (ka.$1 == 0 && ka.$2 != kb.$2) {
      return mode == NodeSortMode.delayAsc
          ? ka.$2.compareTo(kb.$2)
          : kb.$2.compareTo(ka.$2);
    }
    return a.compareTo(b);
  });
  return ordered;
}
