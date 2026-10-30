import 'package:dartc/source.dart';

void main() {
  final source = SourceFile(
    Uri.parse('memory:example.dart'),
    'void main() {\n  print("hi");\n}\n',
  );
  final span = SourceSpan(source, 16, 21);
  final position = source.lineInfo.location(span.start);
  print('${source.uri}:${position.line}:${position.column}: ${span.text}');
}
