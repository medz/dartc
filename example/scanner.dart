import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

void main() {
  final source = SourceFile(
    Uri.parse('memory:example.dart'),
    r'final message = "Hello, $name!";',
  );
  final result = scan(source);
  for (final token in result.tokens) {
    print('${token.kind.name} [${token.start}, ${token.end}): ${token.lexeme}');
  }
  for (final diagnostic in result.diagnostics) {
    print('${diagnostic.code}: ${diagnostic.message}');
  }
}
