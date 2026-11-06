import 'package:mihomo_tui/src/ui/views/logs_view.dart';
import 'package:test/test.dart';

void main() {
  test('density modes cycle in order', () {
    expect(LogMode.standard.next, LogMode.compact);
    expect(LogMode.compact.next, LogMode.standard);
  });

  test('modes have labels', () {
    expect(LogMode.standard.label, '标准');
    expect(LogMode.compact.label, '精简');
  });
}
