import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  test(
    'canonical core ancestors retain checked SDK interface relationships',
    () async {
      final sources = await SdkSources.load();
      final program = await AnalysisSession(
        ['test/compiler/fixtures/iterable_chaining.dart'],
        includeDependencies: true,
        sources: sources,
      ).use((input) async => (await Lowering().lower(input)).program);
      final factory = program.functions
          .singleWhere((function) => function.target.name == 'firstEfficient')
          .target;
      final efficient = factory.parameterTypes.first as ClassType;
      for (final name in ['ListBase', '_GrowableList', 'UserList']) {
        final declaration = program.classes.singleWhere(
          (c) => c.type.name == name,
        );
        final applied = declaration.type.instantiate([ValueType.integer]);
        expect(applied.asInstanceOf(efficient.declaration)?.typeArguments, [
          ValueType.integer,
        ]);
      }
    },
  );
  test(
    'target SDK storage retains nominal classes and inherited bodies',
    () async {
      final sources = await SdkSources.load();
      final program = await AnalysisSession(
        ['test/compiler/fixtures/integer_text.dart'],
        includeDependencies: true,
        sources: sources,
      ).use((input) async => (await Lowering().lower(input)).program);
      for (final name in ['_OneByteString', '_TwoByteString']) {
        final storage = program.classes.singleWhere((c) => c.type.name == name);
        expect(storage.type, isNot(ValueType.string));
        expect(storage.type.superclass, ValueType.string);
        final member = program.lookupMember(storage.type, (
          kind: .getter,
          name: 'length',
          privateScope: null,
        )).target!;
        expect(member.owner, ValueType.string);
        expect(program.implementationOf(member), isA<IrFunction>());
      }
      final latin1 = program.classes.singleWhere(
        (c) => c.type.name == '_OneByteString',
      );
      final predicate = program.functions.singleWhere(
        (f) =>
            f.target.owner == ValueType.string && f.target.name == '_isOneByte',
      );
      expect(
        predicate.blocks
            .expand((b) => b.instructions)
            .whereType<TypeTest>()
            .single
            .testedType,
        latin1.type,
      );
      final complement = program.functions.singleWhere(
        (f) => f.target.owner == ValueType.integer && f.target.name == '~',
      );
      expect(
        complement.blocks.expand((b) => b.instructions).whereType<IntBinary>(),
        isNotEmpty,
      );
      for (final type in [ValueType.integer, ValueType.floating]) {
        expect(
          program.functions.where(
            (f) => f.target.owner == type && f.target.name == '_equalToInteger',
          ),
          hasLength(1),
        );
      }
    },
  );
}
