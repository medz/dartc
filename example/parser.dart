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

  final signature = SourceFile(
    Uri.parse('memory:signature'),
    'List<int> Function(String input)',
  );
  final parsedType = parseTypeAnnotation(scan(signature));
  if (parsedType.hasErrors) return;
  final function = parsedType.node as FunctionTypeAnnotation;
  print(function.returnType!.text); // List<int>
  print(function.parameters.parameters.single.name!.text); // input

  final collection = parseExpression(
    scan(
      SourceFile(
        Uri.parse('memory:collection'),
        '[for (var item in items) if (item != null) item]',
      ),
    ),
  );
  if (collection.hasErrors) return;
  final list = collection.node as CollectionExpression;
  final loop = list.elements.single as ForElement;
  print((loop.parts as ForInParts).iterable.text); // items
  print((loop.body as IfElement).condition.text); // item != null

  final message = parseExpression(
    scan(SourceFile(Uri.parse('memory:message'), r'"Total: ${price * count}"')),
  );
  if (message.hasErrors) return;
  final string = message.node as InterpolatedStringExpression;
  final interpolation = string.parts[1] as StringInterpolation;
  print(interpolation.expression.text); // price * count

  final creation = parseExpression(
    scan(
      SourceFile(Uri.parse('memory:creation'), 'new p.Box<int>.named(value)'),
    ),
  );
  if (creation.hasErrors) return;
  final constructor = creation.node as InstanceCreationExpression;
  print(constructor.name.map((n) => n.text).join('.')); // p.Box
  print(constructor.typeArguments!.text); // <int>
  print(constructor.constructorName!.text); // named

  final configured = parseExpression(
    scan(
      SourceFile(Uri.parse('memory:cascade'), 'make()..color = .blue..build()'),
    ),
  );
  if (configured.hasErrors) return;
  final cascade = configured.node as CascadeExpression;
  print(cascade.target.text); // make()
  final assignment = cascade.sections.first as AssignmentExpression;
  final shorthand = assignment.right as DotShorthandExpression;
  print(shorthand.expression.text); // .blue
  print(cascade.sections.last.text); // ..build()
}
