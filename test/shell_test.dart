import 'package:mihomo_tui/src/util/shell.dart';
import 'package:test/test.dart';

void main() {
  test('splits on whitespace', () {
    expect(splitCommand('code -w'), ['code', '-w']);
    expect(splitCommand('  code   -w  '), ['code', '-w']);
  });

  test('keeps quoted arguments together', () {
    expect(
      splitCommand('/usr/bin/nano --syntax "yaml file"'),
      ['/usr/bin/nano', '--syntax', 'yaml file'],
    );
    expect(splitCommand("vim -c 'set ft=yaml'"), ['vim', '-c', 'set ft=yaml']);
  });

  test('handles empty and quoted-only input', () {
    expect(splitCommand(''), isEmpty);
    expect(splitCommand('   '), isEmpty);
    expect(splitCommand('""'), ['']);
  });

  test('keeps windows path separators intact', () {
    expect(
      splitCommand(r'C:\Tools\mihomo.exe -d C:\Users\me'),
      [r'C:\Tools\mihomo.exe', '-d', r'C:\Users\me'],
    );
  });
}
