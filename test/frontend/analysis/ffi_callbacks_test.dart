import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(
    () =>
        directory = Directory.systemTemp.createTempSync('dartc-ffi-callback-'),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> check(String source, {bool inspect = false}) async {
    final file = File('${directory.path}/entry.dart')
      ..writeAsStringSync(source);
    await AnalysisSession([file.path]).use((input) {
      if (inspect) {
        final callbacks = _CallbackTypes();
        input.libraries.single.units.single.unit.accept(callbacks);
        expect(callbacks.types, hasLength(10));
        for (final type in callbacks.types) {
          expect(
            type.optionalParameterTypes.isNotEmpty ||
                type.namedParameterTypes.isNotEmpty,
            isTrue,
            reason: 'Checking must retain the callback type: $type',
          );
        }
      }
    });
  }

  test(
    'accepts callable optional shapes and preserves their source types',
    () async {
      await check('''
import 'dart:ffi';
int positional(int value, [int extra = 3]) => value + extra;
int allOptional([int value = 2, int extra = 3]) => value + extra;
int named(int value, {int extra = 4}) => value + extra;
void notify(int value, [int extra = 3]) {}
void unused() {
  Pointer.fromFunction<Int64 Function(Int64)>(positional, -1);
  Pointer.fromFunction<Int64 Function(Int64, Int64)>(positional, -1);
  Pointer.fromFunction<Int64 Function()>(allOptional, -1);
  Pointer.fromFunction<Int64 Function(Int64)>(named, -1);
  NativeCallable<Int64 Function(Int64)>.isolateLocal(positional, exceptionalReturn: -1);
  NativeCallable<Int64 Function(Int64, Int64)>.isolateLocal(positional, exceptionalReturn: -1);
  NativeCallable<Int64 Function()>.isolateLocal(allOptional, exceptionalReturn: -1);
  NativeCallable<Int64 Function(Int64)>.isolateLocal(exceptionalReturn: -1, named);
  NativeCallable<Void Function(Int64)>.listener(notify);
  final capture = 5;
  NativeCallable<Int64 Function(Int64)>.isolateLocal(
    (int value, [int extra = 3]) => value + extra + capture,
    exceptionalReturn: -1,
  );
}
''', inspect: true);
    },
  );

  for (final invalid in [false, true]) {
    test(
      'nested callbacks in a part retain fallback checks: $invalid',
      () async {
        final source =
            """
part of 'entry.dart';
int optional(int value, [int extra = 3]) => value + extra;
void unused() {
  NativeCallable<Int64 Function(Int64)>.isolateLocal(
    (int value, [int extra = 3]) {
      final call = NativeCallable<Int64 Function(Int64)>.isolateLocal(
        optional,
        exceptionalReturn: ${invalid ? "'bad'" : '-1'},
      );
      call.close();
      return value + extra;
    },
    exceptionalReturn: -1,
  );
}
""";
        final part = File('${directory.path}/callbacks.dart')
          ..writeAsStringSync(source);
        final result = check("import 'dart:ffi'; part 'callbacks.dart';");
        if (invalid) {
          await expectLater(
            result,
            throwsA(
              isA<FormatException>()
                  .having(
                    (error) => error.message,
                    'source',
                    contains(part.uri.toString()),
                  )
                  .having(
                    (error) => error.offset,
                    'offset',
                    source.indexOf("'bad'"),
                  ),
            ),
          );
        } else {
          await result;
        }
      },
    );
  }

  test('optional callbacks use the flattened variadic arity', () async {
    await check('''
import 'dart:ffi';
double callback(int first, [double second = 0, int third = 0]) => first + second + third;
void unused() {
  Pointer.fromFunction<Double Function(Int, VarArgs<(Double, Int)>)>(callback, -1.0);
  NativeCallable<Double Function(Int, VarArgs<(Double, Int)>)>.isolateLocal(callback, exceptionalReturn: -1.0);
  NativeCallable<Double Function(Int, VarArgs<()>)>.isolateLocal(callback, exceptionalReturn: -1.0);
}
''');
  });

  for (final (name, declaration, invocation) in [
    (
      'excess variadic arguments',
      'int callback(int first, [int second = 0]) => first;',
      'Pointer.fromFunction<Int Function(Int, VarArgs<(Int, Int)>)>(callback, -1)',
    ),
    (
      'named variadic fields',
      'int callback(int first, [int second = 0]) => first;',
      'Pointer.fromFunction<Int Function(Int, VarArgs<({Int second})>)>(callback, -1)',
    ),
    (
      'nonfinal variadic marker',
      'int callback(int first, [int second = 0]) => first;',
      'Pointer.fromFunction<Int Function(VarArgs<(Int,)>, Int)>(callback, -1)',
    ),
    (
      'missing required positional argument',
      'int callback(int first, int second, [int third = 0]) => first;',
      'Pointer.fromFunction<Int64 Function(Int64)>(callback, -1)',
    ),
    (
      'excess native arguments',
      'int callback(int first, [int second = 0]) => first;',
      'Pointer.fromFunction<Int64 Function(Int64, Int64, Int64)>(callback, -1)',
    ),
    (
      'required named argument',
      'int callback(int first, {required int second, int third = 0}) => first;',
      'NativeCallable<Int64 Function(Int64)>.isolateLocal(callback, exceptionalReturn: -1)',
    ),
    (
      'incompatible argument representation',
      'int callback(double first, [int second = 0]) => 1;',
      'Pointer.fromFunction<Int64 Function(Int64)>(callback, -1)',
    ),
    (
      'incompatible result representation',
      'double callback(int first, [int second = 0]) => 1.0;',
      'NativeCallable<Int64 Function(Int64)>.isolateLocal(callback, exceptionalReturn: -1)',
    ),
    (
      'non-native signature',
      'int callback(int first, [int second = 0]) => first;',
      'Pointer.fromFunction<Int64 Function(int)>(callback, -1)',
    ),
    (
      'missing static callback fallback',
      'int callback(int first, [int second = 0]) => first;',
      'Pointer.fromFunction<Int64 Function(Int64)>(callback)',
    ),
    (
      'missing closure callback fallback',
      'int callback(int first, [int second = 0]) => first;',
      'NativeCallable<Int64 Function(Int64)>.isolateLocal(callback)',
    ),
    (
      'wrong fallback type',
      'int callback(int first, [int second = 0]) => first;',
      "Pointer.fromFunction<Int64 Function(Int64)>(callback, 'bad')",
    ),
    (
      'null fallback',
      'int callback(int first, [int second = 0]) => first;',
      'NativeCallable<Int64 Function(Int64)>.isolateLocal(callback, exceptionalReturn: null)',
    ),
    (
      'nonconstant fallback',
      'int fallback = -1; int callback(int first, [int second = 0]) => first;',
      'Pointer.fromFunction<Int64 Function(Int64)>(callback, fallback)',
    ),
    (
      'forbidden void fallback',
      'void callback(int first, [int second = 0]) {}',
      'NativeCallable<Void Function(Int64)>.isolateLocal(callback, exceptionalReturn: -1)',
    ),
    (
      'nonvoid listener',
      'int callback(int first, [int second = 0]) => first;',
      'NativeCallable<Int64 Function(Int64)>.listener(callback)',
    ),
    (
      'generic static callback',
      'T callback<T>(T first, [T? second]) => first;',
      'Pointer.fromFunction<Int64 Function(Int64)>(callback, -1)',
    ),
    (
      'nonstatic fromFunction source',
      'final callback = (int first, [int second = 0]) => first;',
      'Pointer.fromFunction<Int64 Function(Int64)>(callback, -1)',
    ),
    (
      'optional native-to-Dart signature',
      'Pointer<NativeFunction<Int64 Function(Int64)>> pointer = Pointer.fromAddress(0);',
      'pointer.asFunction<int Function(int, [int])>()',
    ),
    (
      'unrelated static error',
      "int broken = 'bad'; int callback(int first, [int second = 0]) => first;",
      'Pointer.fromFunction<Int64 Function(Int64)>(callback, -1)',
    ),
  ]) {
    test('rejects unused $name after optional callback checking', () async {
      await expectLater(
        check("import 'dart:ffi'; $declaration void unused() { $invocation; }"),
        throwsFormatException,
      );
    });
  }
}

final class _CallbackTypes() extends RecursiveAstVisitor<void> {
  final types = <FunctionType>[];

  void _record(ArgumentList arguments) {
    final argument = arguments.arguments
        .where((node) => node is! NamedArgument)
        .first;
    types.add(argument.argumentExpression.staticType! as FunctionType);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'fromFunction') _record(node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.argumentList);
    super.visitInstanceCreationExpression(node);
  }
}
