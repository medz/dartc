import 'dart:io';

import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

void main() {
  test('unmodeled superclass cannot lose application covariance', () async {
    final directory = Directory.systemTemp.createTempSync('dartc-mixins-');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/base.dart').writeAsStringSync(
      'class Base { int accept(covariant int value) => value; }',
    );
    final file = File('${directory.path}/entry.dart')
      ..writeAsStringSync(
        "import 'base.dart'; "
        'mixin M { int accept(int value) => value; } '
        'class C extends Base with M {} '
        'int run() => C().accept(1);',
      );
    await expectLater(
      CheckedLibraries.read([file.path], Lowering.lower),
      throwsA(isA<UnsupportedError>()),
    );
  });
  group('unsupported mixins fail at their source', () {
    for (final (name, source) in <(String, String)>[
      (
        'constant mixin applications',
        'class B { const B(); } '
            'mixin M { int value() => 1; } '
            'class C = B with M; '
            'Object run() => const C();',
      ),
      (
        'application requiring a typed noSuchMethod forwarder',
        'abstract class I { int absent(int value); } '
            'mixin M { dynamic noSuchMethod(Invocation call) => 1; } '
            'class C with M implements I {} '
            'int run() => C().absent(1);',
      ),
      (
        'generic application classes',
        'mixin M { int value() => 1; } '
            'class C<T> with M {} '
            'int run() => C<int>().value();',
      ),
      (
        'generic base types',
        'class Base<T> {} '
            'mixin M { int value() => 1; } '
            'class C extends Base<int> with M {} '
            'int run() => C().value();',
      ),
      (
        'covariance introduced by application',
        'class Base { int accept(covariant int value) => value; } '
            'mixin M { int accept(int value) => value; } '
            'class C extends Base with M {} '
            'int run() => C().accept(1);',
      ),

      (
        'generic mixin types',
        'mixin M<T> { T identity(T value) => value; } '
            'class C with M<int> {} '
            'int run() => C().identity(1);',
      ),
      (
        'generic on constraints',
        'class Generic<T> {} '
            'class Base extends Generic<int> {} '
            'mixin M on Generic<int> { int value() => 1; } '
            'class C extends Base with M {} '
            'int run() => C().value();',
      ),
      (
        'generic mixin methods',
        'mixin M { T identity<T>(T value) => value; } '
            'class C with M {} '
            'int run() => C().identity<int>(1);',
      ),
      (
        'nested mixin class applications',
        'mixin A { int value() => 1; } '
            'mixin class M = Object with A; '
            'class C with M {} '
            'int run() => C().value();',
      ),

      (
        'abstract members',
        'mixin M { int value(); int invoke() => value(); } '
            'class C with M { int value() => 1; } '
            'int run() => C().invoke();',
      ),
      (
        'implemented interfaces',
        'abstract class I { int value(); } '
            'mixin M implements I { int value() => 1; } '
            'class C with M {} '
            'int run() => C().value();',
      ),
    ]) {
      test(name, () async {
        final directory = Directory.systemTemp.createTempSync('dartc-mixins-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/entry.dart')
          ..writeAsStringSync(source);
        await expectLater(
          CheckedLibraries.read([file.path], Lowering.lower),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'source',
              contains('entry.dart:'),
            ),
          ),
        );
      });
    }
  });
}
