import 'package:mihomo_tui/src/service/mihomo_api.dart';
import 'package:mihomo_tui/src/util/node_sort.dart';
import 'package:test/test.dart';

ProxyNode node(String name,
        {String? now, List<String> all = const [], int? delay}) =>
    ProxyNode(
      name: name,
      type: all.isEmpty ? 'Shadowsocks' : 'Selector',
      now: now,
      all: all,
      delay: delay,
    );

void main() {
  final nodes = <String, ProxyNode>{
    'fast': node('fast', delay: 80),
    'slow': node('slow', delay: 900),
    'dead': node('dead', delay: 0),
    'untested': node('untested'),
    'group': node('group', now: 'fast', all: ['fast']),
  };
  const names = ['slow', 'group', 'dead', 'fast', 'untested'];

  test('original mode keeps the config order', () {
    expect(
      orderNodeNames(names: names, mode: NodeSortMode.original, nodes: nodes),
      names,
    );
  });

  test('ascending puts fast nodes first and groups last', () {
    final ordered =
        orderNodeNames(names: names, mode: NodeSortMode.delayAsc, nodes: nodes);
    expect(ordered.indexOf('fast'), 0);
    expect(ordered.indexOf('slow'), 1);
    expect(ordered.indexOf('dead'), 2);
    expect(ordered.indexOf('untested'), 3);
    expect(ordered.indexOf('group'), 4);
  });

  test('descending puts slow nodes first but keeps dead ones last', () {
    final ordered = orderNodeNames(
        names: names, mode: NodeSortMode.delayDesc, nodes: nodes);
    expect(ordered.indexOf('slow'), 0);
    expect(ordered.indexOf('fast'), 1);
    expect(ordered.indexOf('dead'), 2);
    expect(ordered.indexOf('group'), 4);
  });

  test('explicit delay overrides win over history', () {
    final ordered = orderNodeNames(
      names: ['fast', 'slow'],
      mode: NodeSortMode.delayAsc,
      nodes: nodes,
      delays: {'fast': 500, 'slow': 10},
    );
    expect(ordered, ['slow', 'fast']);
  });

  test('equal ranks fall back to name order', () {
    final ordered = orderNodeNames(
      names: ['b', 'a'],
      mode: NodeSortMode.delayAsc,
      nodes: {'a': node('a'), 'b': node('b')},
    );
    expect(ordered, ['a', 'b']);
  });

  test('modes cycle', () {
    expect(NodeSortMode.original.label, '默认');
    expect(NodeSortMode.original.next, NodeSortMode.delayAsc);
    expect(NodeSortMode.delayAsc.next, NodeSortMode.delayDesc);
    expect(NodeSortMode.delayDesc.next, NodeSortMode.original);
  });
}
