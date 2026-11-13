import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixture_comparison.dart';
import 'fixtures/covariant_forwarder_sources.dart' as sdk;

void main() {
  late IrProgram sourceProgram;
  setUpAll(() async {
    sourceProgram = (await FixtureComparison.load(
      'covariant_forwarder_sources',
    )).program;
  });

  Future<IrProgram> lower(String source) async {
    final directory = Directory.systemTemp.createTempSync(
      'dartc-wrapper-guard-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/entry.dart')
      ..writeAsStringSync(source);
    return AnalysisSession([file.path])
        .use((input) async => (await Lowering().lower(input)).program);
  }

  final sources = <String, String>{
    'abstract interface covariance propagates to descendants': '''
abstract class I { Object? f([num x = 10]); }
class A implements I {
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}
abstract class J { Object? f([covariant num x = 40]); }
abstract class B extends A implements J {}
class C extends B {}
''',
    'abstract interface covariance is checked without descendants': '''
abstract class I { Object? f([num x = 10]); }
class A implements I { dynamic noSuchMethod(Invocation i) => 1; }
abstract class J { Object? f([covariant num x = 40]); }
abstract class B extends A implements J {}
''',
    'class covariance remains distinct from explicit covariance': '''
class R { Object? f([covariant num? x = 10]) => x; }
abstract class B<T extends num> extends R { Object? f([T? x]); }
class C extends B<int> {}
''',
    'abstract forwarding retains method bound covariance': '''
abstract class I { Object? f<U extends Object?>([num x = 10]); }
class A implements I { dynamic noSuchMethod(Invocation i) => 1; }
abstract class J<T> { Object? f<U extends T>([num x = 40]); }
abstract class B extends A implements J<Object?> {}
class C extends B {}
''',
    'concrete inheritance adds specialized interface checks': '''
class R { Object? f(int value) => value; }
abstract class J<T> { Object? f(T value); }
class A extends R implements J<int> {}
''',
    'different interface and inherited entry types are preserved': '''
class R { Object? f([num x = 10]) => x; }
abstract class B extends R { Object? f([covariant int x = 20]); }
class C extends B {}
''',
  };
  for (final entry in sources.entries) {
    test(entry.key, () async {
      await lower(entry.value);
    });
  }

  test('own real covariant override wins over inherited body', () async {
    final program = await lower('''
class R { Object? f([num x = 10]) => x; }
class D extends R { Object? f([covariant int x = 30]) => x + 1; }
Object? run() => D().f();
''');
    final entry = program.functions.singleWhere((f) => f.target.name == 'run');
    expect(IrInterpreter(program, {}).run(entry, []), 31);
  });

  test(
    'unchanged inherited covariance keeps the actual implementation',
    () async {
      final program = await lower('''
class R { Object? f({covariant num x = 10, num y = 11}) => x; }
abstract class B extends R {
  Object? f({num y = 21, covariant num x = 20});
}
class C extends B {}
Object? run() => C().f();
''');
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'run',
      );
      expect(IrInterpreter(program, {}).run(entry, []), 10);
    },
  );

  test(
    'generic inherited class checks alone do not become a wrapper guard',
    () async {
      final program = await lower('''
class R<T> { Object? f(T x) => x; }
abstract class B extends R<int> { Object? f(int x); }
class C extends B {}
Object? run() => C().f(10);
''');
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'run',
      );
      expect(IrInterpreter(program, {}).run(entry, []), 10);
    },
  );

  test('own real covariant override wins over an inherited nSM body', () async {
    final program = await lower('''
abstract class I { Object? f([num x = 10]); }
class A implements I { dynamic noSuchMethod(Invocation i) => 1; }
class D extends A { Object? f([covariant int x = 30]) => x + 1; }
Object? run() => D().f();
''');
    final entry = program.functions.singleWhere((f) => f.target.name == 'run');
    expect(IrInterpreter(program, {}).run(entry, []), 31);
  });

  test('unchanged deep inheritance reuses a covariant nSM body', () async {
    final program = await lower('''
abstract class I { Object? f([covariant num x = 10]); }
class A implements I {
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}
abstract class B extends A {}
class C extends B {}
abstract class D extends C {}
class E extends D {}
class F extends E {}
Object? run() => F().f();
''');
    final entry = program.functions.singleWhere((f) => f.target.name == 'run');
    expect(IrInterpreter(program, {}).run(entry, []), 10);
  });

  test(
    'inherited method-bound class covariance survives specialization',
    () async {
      final program = await lower('''
class R<T> { Object? f<U extends T>([num x = 10]) => x; }
abstract class B extends R<Object?> { Object? f<U extends Object?>([num x = 20]); }
class C extends B {}
Object? run() => C().f();
''');
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'run',
      );
      expect(IrInterpreter(program, {}).run(entry, []), 10);
    },
  );

  test(
    'contravariant-only method bounds do not introduce class covariance',
    () async {
      final program = await lower('''
class R { Object? f<U extends void Function(num)>([num x = 10]) => x; }
abstract class J<T> { Object? f<U extends void Function(T)>([num x = 40]); }
abstract class B extends R implements J<num> {
  Object? f<U extends void Function(num)>([num x = 20]);
}
class C extends B {}
Object? run() => C().f();
''');
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'run',
      );
      expect(IrInterpreter(program, {}).run(entry, []), 10);
    },
  );

  test(
    'synthesized method-bound class covariance survives abstract redeclaration',
    () async {
      final program = await lower('''
abstract class I<T> { Object? f<U extends T>([num x = 10]); }
class A implements I<Object?> {
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}
abstract class B extends A { Object? f<U extends Object?>([num x = 20]); }
class C extends B {}
Object? run() => C().f();
''');
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'run',
      );
      expect(IrInterpreter(program, {}).run(entry, []), 10);
    },
  );

  for (final (name, run, forms, valueForms) in [
    ('sourceCovariance', sdk.sourceCovariance, 11, {1, 5, 8, 9, 10}),
    ('ownSourceCovariance', sdk.ownSourceCovariance, 11, {1, 5, 8, 9, 10}),
    ('transitiveSourceCovariance', sdk.transitiveSourceCovariance, 5, {1, 3}),
  ]) {
    test('$name preserves checks, defaults and tearoff types', () {
      final fixture = FixtureComparison(sourceProgram);
      for (var form = 0; form < forms; form++) {
        for (final value
            in valueForms.contains(form) ? [7, 1.5, 'bad', null] : [null]) {
          fixture.compare(name, [form, value], () => run(form, value));
        }
      }
    });
  }
}
