import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

FlowResult _transfer(FlowState s, Instruction op, List<FlowValue> args) =>
    s.transfer(
      op,
      args,
      allocate: (_) => throw StateError('allocation'),
      repeated: false,
      invoke: (_, _, _) => throw StateError('call'),
      call: (_, _, _) => throw StateError('call'),
    )!;

void main() {
  test('publication preserves managed identities, headers and private heap fields while admitting both global binding states', () {
    final t = ClassType(null, 'RootSlots'),
        flag = InstanceField(t, 'bound', .boolean),
        number = InstanceField(t, 'value', .integer);
    final module = ModuleObject(
      t,
      initialFields: {
        flag: const Constant.boolean(true),
        number: const Constant.integer(31),
      },
    );
    final global = GlobalVariable(
      Uri.parse('memory:module-writing'),
      'lateValue',
      .integer,
      isLate: true,
    );
    final d = NativeData(List.filled(64, 1), alignment: 8);
    final root = FunctionTarget(null, 'marker', .integer, []), b = Block();
    final addr = b.emit(NativeDataAddress(d)),
        ref = b.emit(ModuleObjectReference(module));
    final allocation = b.emit(NewPayload(t, const Constant.integer(8)));
    b.finish(Return(addr));
    final p = IrProgram(
      [
        IrClass(t, [flag, number]),
      ],
      [
        IrFunction(root, [b]),
      ],
      globals: [global],
    );
    final layout = ProgramLayout(
      p.classes,
      nativeLayout: NativeLayout(Target.host()),
    );
    var state = FlowState(p, memoryLayout: layout);
    final pointer = _transfer(state, addr, []).value,
        fixed = _transfer(state, ref, []).value;
    final id = FlowObject(allocation, Object()), dyn = FlowValue.object(id);
    final made = state.transfer(
      allocation,
      [FlowValue.constant(const Constant.integer(8))],
      allocate: (_) => id,
      repeated: false,
      invoke: (_, _, _) => throw StateError('call'),
      call: (_, _, _) => throw StateError('call'),
    )!;
    state = made.normal!;
    state = _transfer(
      state,
      StoreField(number, allocation, const Constant.integer(19)),
      [dyn, FlowValue.constant(const Constant.integer(19))],
    ).normal!;
    state = _transfer(state, StoreGlobal(global, const Constant.integer(31)), [
      FlowValue.constant(const Constant.integer(31)),
    ]).normal!;
    final size = layout.objectLayout(t).size;
    final at = Constant.integer(ObjectHeader.sizeOffset);
    FlowValue header(FlowState s) => _transfer(
      s,
      LoadObjectData(ref, at, NativeScalarType(Int64)),
      [fixed, FlowValue.constant(at)],
    ).value;
    expect(header(state).integers?.constant, size);
    expect(
      _transfer(state, LoadField(flag, ref), [fixed]).value.constant,
      const Constant.boolean(true),
    );
    final published = state.copy()
      ..recordEscape([pointer])
      ..publishMappingCapabilities();
    final bound = _transfer(published, LoadField(flag, ref), [fixed]).value;
    final oldGlobal = _transfer(published, LoadGlobal(global), []);
    expect(oldGlobal.normal, isNotNull);
    expect(oldGlobal.hasSemanticFailure, isTrue);
    expect(bound.constant, isNull);
    expect(bound.unknownTypes, contains(ValueType.boolean));
    expect(
      _transfer(published, ref, []).value.objects.single,
      same(fixed.objects.single),
    );
    expect(header(published).integers?.constant, size);
    expect(
      _transfer(published, LoadField(number, allocation), [
        dyn,
      ]).value.integers?.constant,
      19,
    );
    expect(published.escapedValues.objects, isNot(contains(id)));
    expect(
      _transfer(published, LoadField(number, ref), [
        fixed,
      ]).value.integers?.constant,
      isNull,
    );
  });
}
