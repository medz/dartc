import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart';
import 'package:dartc/src/compiler/runtime.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  test(
    'every target ABI index selects its constant in the bundled SDK',
    () async {
      final lowered = await prepareRuntime(
        'test/compiler/fixtures/abi_integers.dart',
      );
      final query = lowered.runtime.primitives.entries
          .singleWhere((entry) => entry.value == MemoryOperation.abi)
          .key;
      final factory = lowered.program.functions.singleWhere(
        (body) =>
            body.target.name == 'current' &&
            body.target.owner?.library == Uri.parse('dart:ffi') &&
            body.target.owner?.name == 'Abi',
      );
      final values = factory.sequenceConstants.single.elements;
      for (final os in OperatingSystem.values) {
        for (final arch in Architecture.values) {
          final target = Target(os, arch);
          final body = bindRuntime(
            lowered,
            target,
          ).program.implementationOf(query) as IrFunction;
          final index =
              ((body.blocks.single.end as Return).value as ScalarConstant).value
                  as int;
          final selected = values[index] as ObjectConstant;
          String component(String field) {
            final value =
                selected.fields.entries
                        .singleWhere((entry) => entry.key.name == field)
                        .value
                    as ObjectConstant;
            return (value.fields.entries
                            .singleWhere((entry) => entry.key.name == '_name')
                            .value
                        as ScalarConstant)
                    .value
                as String;
          }

          expect(
            '${component('_os')}_${component('_architecture')}',
            '${os.name}_${arch.name}',
            reason: '$target selected SDK ABI index $index',
          );
        }
      }
    },
  );
}
