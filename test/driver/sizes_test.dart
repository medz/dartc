import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';

const _program = '''
abstract class Shape {
  int area();
}

class Square implements Shape {
  final int side;
  Square(this.side);

  @override
  int area() => side * side;
}

int total(List<Shape> shapes) {
  var sum = 0;
  for (final shape in shapes) {
    sum += shape.area();
  }
  return sum;
}

void main() {
  print(total([Square(2)]));
}
''';

void main() {
  late ProgramSizes sizes;
  late Uri source;

  setUpAll(() async {
    final directory = writeSources({'main.dart': _program});
    source = Uri.file('${directory.path}/main.dart');
    sizes = await measureProgram(
      source.toFilePath(),
      const CompileOptions(optimizations: {}),
    );
  });

  FunctionSize named(String name) =>
      sizes.functions.singleWhere((function) => function.name.endsWith(name));

  test('parts make up the file', () {
    final parts = sizes.parts.values.fold(0, (sum, bytes) => sum + bytes);
    expect(parts, sizes.fileBytes);
    expect(sizes.parts['code'], greaterThan(0));
    expect(sizes.parts['stack maps'], greaterThan(0));
    expect(sizes.parts['dispatch table'], greaterThan(0));
  });

  test('functions make up the code, largest first', () {
    final functions = sizes.functions;
    final bytes = functions.fold(0, (sum, function) => sum + function.bytes);
    expect(bytes, sizes.parts['code']);
    for (var i = 1; i < functions.length; i++) {
      expect(functions[i - 1].bytes, greaterThanOrEqualTo(functions[i].bytes));
    }
    expect({
      for (final function in functions) function.name,
    }, hasLength(functions.length));
  });

  test('a function tells what declares it', () {
    final area = named('.Square.area');
    expect(area.library, source);
    expect(area.owner, 'Square');
    expect(named('.total').owner, isNull);
    expect(named('.print').library, Uri.parse('dart:core'));
  });

  test('a call on objects tells where it is and where they are made', () {
    final steps = named('.Square.area').why;
    expect(
      [for (final step in steps) step.how],
      ['a call of area on Square', 'used', 'the entry of the program'],
    );
    expect(steps[0].name, endsWith('.Square.area'));
    expect(steps[0].createdBy, endsWith('.main'));
    expect(steps[1].name, endsWith('.total'));
    expect(steps[2].name, endsWith('.main'));
  });

  test('every translated function tells why it is there', () {
    for (final function in sizes.functions) {
      if (!function.name.startsWith('dart.')) continue;
      expect(function.why, isNotEmpty, reason: function.name);
      expect(function.why.first.name, function.name);
    }
  });

  test('what lowering makes has no reason and no library', () {
    final start = sizes.functions.singleWhere((f) => f.name == '.start');
    expect(start.why, isEmpty);
    expect(start.library, isNull);
  });
}
