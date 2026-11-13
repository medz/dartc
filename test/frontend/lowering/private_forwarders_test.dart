import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/private_forwarders.dart' as sdk;
import 'fixtures/private_forwarders_child.dart' as child_sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = FixtureComparison(
      await AnalysisSession(
        [
          'test/frontend/lowering/fixtures/private_forwarders.dart',
          'test/frontend/lowering/fixtures/private_forwarders_a.dart',
          'test/frontend/lowering/fixtures/private_forwarders_b.dart',
          'test/frontend/lowering/fixtures/private_forwarders_child.dart',
        ],
        sources: await SdkSources.load(),
      ).use((input) async => (await Lowering().lower(input)).program),
    );
  });

  test(
    'foreign methods/accessors/generics/void/Never bypass user noSuchMethod',
    () {
      for (var kind = 0; kind < 3; kind++) {
        for (var form = 0; form < 23; form++) {
          for (final value in [7, 1.5, 'bad', null]) {
            fixture.compare('privateForms', [
              kind,
              form,
              value,
            ], () => sdk.privateForms(kind, form, value));
          }
        }
      }
    },
  );
  test('independent foreign selectors and own same-spelled method coexist', () {
    for (var form = 0; form < 4; form++) {
      fixture.compare('privateSecond', [form], () => sdk.privateSecond(form));
    }
    fixture.compare('privateOwn', [], sdk.privateOwn);
  });
  test(
    'real and synthetic replacements use widened entry and tearoff types',
    () {
      for (var kind = 0; kind < 2; kind++) {
        for (final form in [0, 1, 2, 15, 16, 18, 20]) {
          for (final value in [7, 1.5, 'bad', null]) {
            fixture.compare('privateReplacement', [
              kind,
              form,
              value,
            ], () => sdk.privateReplacement(kind, form, value));
          }
        }
      }
    },
  );
  test(
    'compatible real subtype implementations retain their original bodies',
    () {
      for (var form = 0; form < 3; form++) {
        fixture.compare('privateCompatible', [
          form,
        ], () => sdk.privateCompatible(form));
      }
      final child = fixture.program.classes.singleWhere(
        (c) => c.type.name == 'CompatibleChild',
      );
      for (final name in ['_wide', '_return', '_same']) {
        final original = fixture.program.functions.singleWhere(
          (f) =>
              f.target.owner?.name == 'CompatibleReal' && f.target.name == name,
        );
        final resolved = fixture.program.lookupMember(
          child.type,
          original.target.selector,
        );
        expect(resolved.target, same(original.target));
        expect(resolved.target!.owner!.name, 'CompatibleReal');
        expect(resolved.unsupportedForwarder, isFalse);
        expect(
          fixture.program.functions.where(
            (f) =>
                f.target.owner?.name == 'CompatibleChild' &&
                f.target.name == name,
          ),
          isEmpty,
        );
      }
    },
  );
  test('inherited explicit covariance survives widened real replacement', () {
    for (var form = 0; form < 3; form++) {
      for (final value in [7, 1.5, 'bad', null]) {
        fixture.compare('privateCovariance', [
          form,
          value,
        ], () => sdk.privateCovariance(form, value));
      }
    }
  });
  test('multiple interfaces preserve covariance by named identity', () {
    for (var form = 0; form < 4; form++) {
      for (final value in [7, 1.5, 'bad', null]) {
        fixture.compare('privateNamed', [
          form,
          value,
        ], () => sdk.privateNamed(form, value));
      }
    }
  });
  test(
    'foreign unchanged ancestor retains defaults and virtual nSM overrides',
    () {
      for (var kind = 0; kind < 2; kind++) {
        for (var form = 0; form < 4; form++) {
          fixture.compare('privateUnchanged', [
            kind,
            form,
          ], () => sdk.privateUnchanged(kind, form));
        }
      }
    },
  );
  test('unchanged foreign throwing ancestor reuses original body', () {
    for (final form in [0, 1, 2, 15, 16, 18]) {
      for (final value in [7, 'bad']) {
        fixture.compare('privateThrowReuse', [
          form,
          value,
        ], () => child_sdk.privateThrowReuse(form, value));
      }
    }
    expect(
      fixture.program.functions.where(
        (f) =>
            f.target.owner?.name == 'ForeignThrowChild' &&
            f.target.name == '_f',
      ),
      isEmpty,
    );
  });
  test('real error factory is fresh, lazy, nonthrowing and preserves throw identity', () {
    for (var form = 0; form < 6; form++) {
      fixture.compare('privateErrorFactory', [
        form,
      ], () => sdk.privateErrorFactory(form));
    }
  });
  test('public known-shaped body still calls virtual Object.noSuchMethod', () {
    fixture.compare('privatePublicBody', [], sdk.privatePublicBody);
    final body = fixture.program.functions.singleWhere(
      (f) =>
          f.target.owner?.name == 'PublicForward' &&
          f.target.name == 'publicMethod',
    );
    final call = body.blocks
        .expand((b) => b.instructions)
        .whereType<InstanceCall>()
        .single;
    expect(call.member.library, Uri.parse('dart:core'));
    expect(call.member.owner, ValueType.object);
    expect(call.member.name, 'noSuchMethod');
    expect(call.member.returnType, ValueType.dynamicType);
  });
  test(
    'foreign failures retain the forwarding library in private invocations',
    () {
      final bodies = fixture.program.functions.where(
        (f) =>
            f.target.library?.scheme != 'dart' &&
            f.target.privateSelectorScope != null &&
            f.target.privateSelectorScope != f.target.library,
      );
      expect(bodies, isNotEmpty);
      for (final body in bodies) {
        final invocation = body.blocks
            .expand((b) => b.instructions)
            .whereType<MakeInvocation>()
            .single;
        expect(invocation.selector, (
          kind: body.target.selector.kind,
          name: body.target.selector.name,
          privateScope: body.target.library,
        ));
      }
    },
  );
  test('replacement defaults and declaration-ordered generic Invocation are retained', () {
    IrFunction body(String owner, String name) =>
        fixture.program.functions.singleWhere(
          (f) => f.target.owner?.name == owner && f.target.name == name,
        );
    for (final (owner, value) in [
      ('Default', 7),
      ('Changed', 20),
      ('SynthChanged', 30),
    ]) {
      expect((body(owner, '_f').defaults[0] as ScalarConstant).value, value);
    }
    final generic = body('Custom', '_gen');
    final invocation = generic.blocks
        .expand((b) => b.instructions)
        .whereType<MakeInvocation>()
        .single;
    expect(invocation.named.keys, ['z', 'a']);
    expect(invocation.typeArguments, generic.target.typeParameters);
    expect((generic.defaults[1] as ScalarConstant).value, 9);
    expect((generic.defaults[2] as ScalarConstant).value, 'a');
    final both = fixture.program.functions
        .where((f) => f.target.owner?.name == 'Both' && f.target.name == '_f')
        .toList();
    expect(both, hasLength(3));
    expect(
      both.map((f) => f.target.selector.privateScope).toSet(),
      hasLength(3),
    );
  });
  test(
    'source-order independent direct-super targets reuse original private body',
    () {
      final original = fixture.program.functions.singleWhere(
        (f) =>
            f.target.owner?.name == 'LocalBase' &&
            f.target.name == '_unchanged',
      );
      final direct = fixture.program.functions.singleWhere(
        (f) =>
            f.target.owner?.name == 'LocalChild' &&
            f.target.name == 'parentCall',
      );
      final call = direct.blocks
          .expand((b) => b.instructions)
          .whereType<DirectCall>()
          .single;
      expect(call.target, same(original.target));
      expect((call.inputs.last as ScalarConstant).value, 41);
      final tearBody = fixture.program.functions.singleWhere(
        (f) =>
            f.target.owner?.name == 'LocalChild' &&
            f.target.name == 'parentTear',
      );
      final tear = tearBody.blocks
          .expand((b) => b.instructions)
          .whereType<BindMethod>()
          .single;
      expect(tear.direct, isTrue);
      expect(tear.method, same(original.target));
      expect(
        fixture.program.functions.where(
          (f) =>
              [
                'ForeignChild',
                'ForeignOverride',
              ].contains(f.target.owner?.name) &&
              f.target.name == '_unchanged',
        ),
        isEmpty,
      );
    },
  );
}
