import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
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
