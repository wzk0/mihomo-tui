/// Minimal command line splitting (quotes aware, no shell expansion).
library;

List<String> splitCommand(String command) {
  final result = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var hasContent = false;
  for (final char in command.split('')) {
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      hasContent = true;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      hasContent = true;
      continue;
    }
    if (char == ' ' || char == '\t') {
      if (hasContent) {
        result.add(buffer.toString());
        buffer.clear();
        hasContent = false;
      }
      continue;
    }
    buffer.write(char);
    hasContent = true;
  }
  if (hasContent) result.add(buffer.toString());
  return result;
}
