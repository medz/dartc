import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:test/test.dart';

import 'region_origin_test.dart' as scenario;

void main() {
  test('a raw base with zero displacement can retain storage without carrying address bits', () {
    final op = DirectCall(scenario.map, [const Constant.integer(16)]);
    final allocation = FlowObject(op, Object(), type: ValueType.integer);
    final result = FlowState(
      IrProgram([], []),
      memoryLayout: scenario.Layout(),
    ).allocateMemory(allocation, scenario.integer(16), repeated: false);
    final live = result.normal!;
    final carried = FlowValue.address(result.value.addresses.single);
    final retained = carried.references;
    expect(retained.addresses.single.offset, 0);
    expect(retained.addresses.single.retainedBase, isTrue);
    expect(live.isMappedAddress(carried), isTrue);
    expect(live.isMappedAddress(retained), isFalse);
    expect(live.isMappedAddress(carried.join(scenario.integer(0))), isFalse);
    expect(
      live.isMappedAddress(carried.join(FlowValue.unknown(.integer))),
      isFalse,
    );
    final gone = live.overwriteNative(
      carried,
      scenario.integer(16),
      release: true,
    );
    expect(gone.isMappedAddress(carried), isFalse);
    expect(gone.isMappedAddress(retained), isFalse);
  });
}
