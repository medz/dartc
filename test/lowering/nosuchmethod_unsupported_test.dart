import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/nosuchmethod_unsupported.dart' as sdk;
import 'fixtures/nosuchmethod_unsupported_private.dart' as private_sdk;

void main() {
  const fixture = 'test/lowering/fixtures/nosuchmethod_unsupported.dart';
  const privateFixture =
      'test/lowering/fixtures/nosuchmethod_unsupported_private.dart';
  late IrProgram program;
  setUpAll(() async {
    program = await AnalysisSession([fixture, privateFixture])
        .use((input) => Lowering().lower(input).program);
  });

  IrClass declaration(String name) =>
      program.classes.singleWhere((c) => c.type.name == name);

  MemberSelector method(String name, [Uri? library]) =>
      (kind: .method, name: name, privateLibrary: library);

  test(
    'emits ordinary typed method, accessor, callable and private bodies',
    () {
      final forwarded = declaration('Forwarded');
      expect(forwarded.unsupportedForwarders, isEmpty);
      expect(
        forwarded.members.keys.toSet(),
        containsAll({
          method('method'),
          (kind: FunctionKind.getter, name: 'property', privateLibrary: null),
          (kind: FunctionKind.setter, name: 'property', privateLibrary: null),
          method('call'),
          method('_private', forwarded.type.library),
        }),
      );
      final lookup = program.lookupMember(
        forwarded.type.instantiate([ValueType.integer]),
        method('method'),
      );
      expect(lookup.target, same(forwarded.members[method('method')]));
      expect(lookup.unmodeledBoundary, isNull);
      expect(lookup.unsupportedForwarder, isFalse);
      final child = declaration('ForwardedChild');
      expect(child.unsupportedForwarders, forwarded.unsupportedForwarders);
      expect(
        program.lookupMember(child.type, method('method')).target,
        same(lookup.target),
      );
      expect(
        program
            .lookupMember(forwarded.type, method('notDeclared'))
            .unsupportedForwarder,
        isFalse,
      );
    },
  );

  test(
    'abstract and sealed declarations defer obligations to concrete child',
    () {
      for (final name in [
        'Deferred',
        'SealedDeferred',
        'AbstractRedeclaration',
      ]) {
        expect(declaration(name).unsupportedForwarders, isEmpty, reason: name);
      }
      for (final name in [
        'DeferredChild',
        'SealedChild',
        'RedeclarationChild',
      ]) {
        expect(
          program.lookupMember(declaration(name).type, method('method')).target,
          isNotNull,
          reason: name,
        );
      }
    },
  );

  test(
    'real implementations win even when analyzer retains forwarding marker',
    () {
      final real = declaration('Real').members[method('method')];
      for (final name in ['Real', 'RealChild', 'RedeclarationChild']) {
        final cls = declaration(name);
        expect(
          cls.unsupportedForwarders,
          isNot(contains(method('method'))),
          reason: name,
        );
        expect(
          program.lookupMember(cls.type, method('method')).target,
          same(real),
          reason: name,
        );
      }
      expect(sdk.Real().method(1), 2);
      expect(sdk.RedeclarationChild().method(1), 2);
    },
  );

  test('abstract redeclaration does not hide an ordinary inherited body', () {
    final child = declaration('OrdinaryChild');
    expect(child.unsupportedForwarders, isEmpty);
    expect(
      program.lookupMember(child.type, method('method')).target,
      same(declaration('OrdinaryImplementation').members[method('method')]),
    );
    expect(sdk.OrdinaryChild().method(7), 7);
  });

  test('foreign private obligations emit throwing bodies even with Object.noSuchMethod', () {
    final uri = declaration('PrivateContract').type.library;
    for (final name in ['DefaultPrivate', 'CustomPrivate']) {
      final cls = declaration(name);
      expect(cls.unsupportedForwarders, isEmpty);
      expect(
        cls.members.keys,
        containsAll({
          method('_method', uri),
          (kind: FunctionKind.getter, name: '_property', privateLibrary: uri),
          (kind: FunctionKind.setter, name: '_property', privateLibrary: uri),
        }),
      );
      final lookup = program.lookupMember(cls.type, method('_method', uri));
      expect(lookup.target, same(cls.members[method('_method', uri)]));
      expect(lookup.target!.privateSelectorLibrary, uri);
      expect(lookup.unsupportedForwarder, isFalse);
      expect(
        program
            .lookupMember(cls.type, method('_method', cls.type.library))
            .unsupportedForwarder,
        isFalse,
      );
    }
    expect(
      () => private_sdk.invokePrivate(sdk.DefaultPrivate()),
      throwsNoSuchMethodError,
    );
    expect(
      () => private_sdk.invokePrivate(sdk.CustomPrivate()),
      throwsNoSuchMethodError,
    );
  });

  test('a compatible foreign private concrete implementation still wins', () {
    final owner = declaration('PrivateImplementation');
    final selector = method('_implemented', owner.type.library);
    expect(
      program.lookupMember(declaration('RealPrivate').type, selector).target,
      same(owner.members[selector]),
    );
  });

  test('partial core implementations are not rejected at class lowering', () {
    final cls = declaration('PartialIterable');

    expect(
      program.lookupMember(cls.type, (
        kind: FunctionKind.getter,
        name: 'iterator',
        privateLibrary: null,
      )).target,
      isNotNull,
    );
    expect(
      program.lookupMember(cls.type, (
        kind: FunctionKind.getter,
        name: 'length',
        privateLibrary: null,
      )).target,
      isNotNull,
    );
  });

  test(
    'foreign private forwarder replaces an incompatible real body',
    () async {
      final directory = Directory.systemTemp.createTempSync('dartc-forwarder-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/entry.dart')
        ..writeAsStringSync('''
import '${File(privateFixture).absolute.uri}';
class Incompatible extends ChangedPrivateImplementation {}
int invoke() => invokeChangedPrivate(Incompatible());
''');
      final lowered = await AnalysisSession([file.path, privateFixture])
          .use((input) => Lowering().lower(input).program);
      final cls = lowered.classes.singleWhere(
        (c) => c.type.name == 'Incompatible',
      );
      final selector = method(
        '_implemented',
        File(privateFixture).absolute.uri,
      );
      final replacement = lowered.lookupMember(cls.type, selector).target!;
      expect(replacement.owner, cls.type);
      expect(replacement.signature.parameters.single, ValueType.number);
      final entry = lowered.functions.singleWhere(
        (f) => f.target.name == 'invoke',
      );
      expect(
        () => FixtureRunner(lowered, {}).run(entry, []),
        throwsNoSuchMethodError,
      );
    },
  );
  test(
    'missing merged generic defaults remain an explicit selector boundary',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'dartc-merged-defaults-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/entry.dart')
        ..writeAsStringSync('''
abstract class A { dynamic g<T extends Object?>({Object? p = 10}); }
abstract class B { Object? g<U extends dynamic>({dynamic p = 20}); }
class C implements A, B { dynamic noSuchMethod(Invocation i) => null; }
Object? invoke() { dynamic c = C(); return c.g(); }
''');
      final lowered = await AnalysisSession([file.path])
          .use((input) => Lowering().lower(input).program);
      final cls = lowered.classes.singleWhere((c) => c.type.name == 'C');
      expect(
        lowered.lookupMember(cls.type, method('g')).unsupportedForwarder,
        isTrue,
      );
      final entry = lowered.functions.singleWhere(
        (f) => f.target.name == 'invoke',
      );
      expect(
        () => FixtureRunner(lowered, {}).run(entry, []),
        throwsUnsupportedError,
      );
    },
  );

  test('foreign private replacement does not reuse an incompatible synthetic ancestor', () async {
    final directory = Directory.systemTemp.createTempSync(
      'dartc-private-replacement-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final parent = File('${directory.path}/parent.dart')
      ..writeAsStringSync('''
abstract class Contract { num _value([int x = 40]); }
class Parent implements Contract { dynamic noSuchMethod(Invocation i) => 1; }
abstract class Changed extends Parent { int _value([int x = 50]); }
int call(Changed receiver) => receiver._value();
''');
    final child = File('${directory.path}/child.dart')
      ..writeAsStringSync(
        "import 'parent.dart'; class Child extends Changed {} int invoke() => call(Child());",
      );
    final lowered = await AnalysisSession([child.path, parent.path])
        .use((input) => Lowering().lower(input).program);
    final cls = lowered.classes.singleWhere((c) => c.type.name == 'Child');
    final replacement = lowered
        .lookupMember(cls.type, method('_value', parent.uri))
        .target!;
    expect(replacement.owner, cls.type);
    expect(replacement.returnType, ValueType.integer);
    final entry = lowered.functions.singleWhere(
      (f) => f.target.name == 'invoke',
    );
    expect(
      () => FixtureRunner(lowered, {}).run(entry, []),
      throwsNoSuchMethodError,
    );
  });
}
