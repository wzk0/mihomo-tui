/// Helpers for walking mihomo's proxy-group selection chain.
library;

import '../service/mihomo_api.dart';

/// Follows `now` pointers from a group until a real (leaf) node is reached.
///
/// Groups may point at other groups, so `group.now` alone is often only the
/// first hop of a path. Returns null when the group has no selection.
ProxyNode? resolveSelectedNode(ProxySnapshot snapshot, ProxyNode group) {
  var current = _clean(group.now);
  final seen = <String>{group.name};
  var hops = 0;
  ProxyNode? last;
  while (current != null && hops++ < 16) {
    if (!seen.add(current)) break; // cycle guard
    final node = snapshot.nodes[current];
    if (node == null) return last;
    last = node;
    final next = _clean(node.now);
    if (!node.isGroup || next == null) return node;
    current = next;
  }
  return last;
}

String? _clean(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

/// Picks the group that the config's final `MATCH` rule points at, falling
/// back to GLOBAL and then to the first available group.
ProxyNode? defaultGroup(ProxySnapshot snapshot, String? matchTarget) {
  if (matchTarget != null) {
    final candidate = snapshot.nodes[matchTarget];
    if (candidate != null && candidate.isGroup) return candidate;
  }
  final global = snapshot.nodes['GLOBAL'];
  if (global != null && global.isGroup) {
    return global;
  }
  if (snapshot.groups.isNotEmpty) {
    return snapshot.nodes[snapshot.groups.first.name];
  }
  return null;
}
