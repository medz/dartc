import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixtures/nosuchmethod_unsupported.dart' as sdk;
import 'fixtures/nosuchmethod_unsupported_private.dart' as private_sdk;

void main() {
  const fixture = 'test/lowering/fixtures/nosuchmethod_unsupported.dart';
  const privateFixture =
      'test/lowering/fixtures/nosuchmethod_unsupported_private.dart';
  late IrProgram program;
  setUpAll(() async {
    program = await CheckedLibraries.read([
      fixture,
      privateFixture,
    ], Lowering.lower);
  });

  IrClass declaration(String name) =>
      program.classes.singleWhere((c) => c.type.name == name);

  MemberSelector method(String name, [Uri? library]) =>
      (kind: .method, name: name, privateLibrary: library);

  test('records typed method, accessor, callable and private obligations', () {
    final forwarded = declaration('Forwarded');
    expect(forwarded.unsupportedForwarders, {
      method('method'),
      (kind: FunctionKind.getter, name: 'property', privateLibrary: null),
      (kind: FunctionKind.setter, name: 'property', privateLibrary: null),
      method('call'),
      method('_private', forwarded.type.library),
    });
    final lookup = program.lookupMember(
      forwarded.type.instantiate([ValueType.integer]),
      method('method'),
    );
    expect(lookup.target, isNull);
    expect(lookup.unmodeledBoundary, isNull);
    expect(lookup.unsupportedForwarder, isTrue);
    final child = declaration('ForwardedChild');
    expect(child.unsupportedForwarders, forwarded.unsupportedForwarders);
    expect(
      program.lookupMember(child.type, method('method')).unsupportedForwarder,
      isTrue,
    );
    expect(
      program
          .lookupMember(forwarded.type, method('notDeclared'))
          .unsupportedForwarder,
      isFalse,
    );
  });

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
          declaration(name).unsupportedForwarders,
          contains(method('method')),
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
          contains(method('method')),
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

  test(
    'foreign private obligations are guarded even with Object.noSuchMethod',
    () {
      final uri = declaration('PrivateContract').type.library;
      for (final name in ['DefaultPrivate', 'CustomPrivate']) {
        final cls = declaration(name);
        expect(cls.unsupportedForwarders, {
          method('_method', uri),
          (kind: FunctionKind.getter, name: '_property', privateLibrary: uri),
          (kind: FunctionKind.setter, name: '_property', privateLibrary: uri),
        });
        final lookup = program.lookupMember(cls.type, method('_method', uri));
        expect(lookup.target, isNull);
        expect(lookup.unsupportedForwarder, isTrue);
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
    },
  );

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
    expect(cls.unsupportedForwarders, isNotEmpty);
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
      )).unsupportedForwarder,
      isTrue,
    );
  });

  test(
    'rejects foreign private forwarder replacing incompatible real body',
    () async {
      final directory = Directory.systemTemp.createTempSync('dartc-forwarder-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/entry.dart')
        ..writeAsStringSync('''
import '${File(privateFixture).absolute.uri}';
class Incompatible extends ChangedPrivateImplementation {}
int invoke(Incompatible receiver) => invokeChangedPrivate(receiver);
''');
      await expectLater(
        CheckedLibraries.read([file.path, privateFixture], Lowering.lower),
        throwsA(
          isA<UnsupportedError>()
              .having(
                (e) => e.message,
                'feature',
                contains(
                  'inherited private noSuchMethod forwarder _implemented',
                ),
              )
              .having((e) => e.message, 'source', contains('entry.dart:2:')),
        ),
      );
    },
  );
}
