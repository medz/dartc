import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

void main() {
  final source = SourceFile(Uri.parse('memory:example'), 'price * count + fee');
  final result = parseExpression(scan(source));
  if (result.hasErrors) {
    for (final diagnostic in result.diagnostics) {
      print('${diagnostic.code}: ${diagnostic.message}');
    }
    return;
  }
  final sum = result.node as BinaryExpression;
  print(sum.op.spelling); // +
  print(sum.left.text); // price * count
  print(sum.right.text); // fee
}
