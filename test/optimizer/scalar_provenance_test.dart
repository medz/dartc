import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  for (final broad in [false, true]) {
    test('scalar payload preserves external alternatives ($broad)', () {
      final box = ClassType(null, 'Private');
      final program = IrProgram([
        IrClass(box, []),
        IrClass(ValueType.integer, []),
      ], []);
      final private = _step(
        FlowState(program, memoryLayout: _Layout()),
        NewPayload(box, const Constant.integer(0)),
        [_integer(0)],
      );
      final scalar = _step(
        private.normal!,
        MaterializeValue(const Constant.integer(42)),
        [_integer(42)],
      );
      final bound = broad ? ValueType.object : box;
      final mixed = scalar.value.join(FlowValue.unknown(bound, external: true));
      final backing = scalar.value.managedBackings.single;
      final renamed = FlowObject(backing.site, Object());
      final mapped = scalar.normal!.mapObjects({backing: renamed});
      final input = mixed.mapObjects(
        (object) => object == backing ? renamed : object,
      );
      for (final value in [
        mapped.resolveValue(input),
        mapped.resolveValue(input.check(box).value),
        mapped.resolveValue(input.carrierReferences),
      ]) {
        expect(value.externalUnknownTypes, isNotEmpty);
        expect(
          mapped.reachableValues([value]).objects,
          isNot(contains(private.value.objects.single)),
        );
      }
      final projected = mapped.project([input]);
      expect(projected.containsObject(renamed), isTrue);
      expect(projected.containsObject(private.value.objects.single), isFalse);
    });
  }

  test('payload refresh retains literal and address alternatives', () {
    final program = IrProgram([IrClass(ValueType.integer, [])], []);
    final scalar = _step(
      FlowState(program, memoryLayout: _Layout()),
      MaterializeValue(const Constant.integer(42)),
      [_integer(42)],
    );
    final backing = scalar.value.managedBackings.single;
    final changed = _step(
      scalar.normal!,
      StoreObjectData(
        backing.site,
        const Constant.integer(ObjectHeader.fieldsOffset),
        NativeScalarType(Int64),
        const Constant.integer(9),
      ),
      [
        FlowValue.object(backing),
        _integer(ObjectHeader.fieldsOffset),
        _integer(9),
      ],
    ).normal!;
    const text = Constant.string('retained');
    const nil = Constant.nullValue();
    final address = FlowAddress(backing, ObjectHeader.fieldsOffset);
    final mixed = FlowValue.joined([
      scalar.value,
      FlowValue.constant(text),
      FlowValue.constant(nil),
      FlowValue.address(address),
    ]);
    final resolved = changed.resolveValue(mixed);
    expect(resolved.constants, containsAll([text, nil]));
    expect(
      resolved.constants.whereType<ScalarConstant>().map(
        (value) => value.value,
      ),
      isNot(contains(42)),
    );
    expect(resolved.addresses, contains(address));
    expect(resolved.managedBackings, {backing});
    final scalarOnly = changed.resolveValue(scalar.value);
    expect((scalarOnly.constant as ScalarConstant).value, 9);
  });

  test('payload refresh preserves raw unknown backing capabilities', () {
    final program = IrProgram([IrClass(ValueType.integer, [])], []);
    final scalar = _step(
      FlowState(program, memoryLayout: _Layout()),
      MaterializeValue(const Constant.integer(42)),
      [_integer(42)],
    );
    final raw = FlowValue.unknown(.integer)
        .withManagedBackings(const [], unknown: true)
        .carrierReferences;
    final resolved = scalar.normal!.resolveValue(raw.join(scalar.value));
    expect(resolved.rawBackingTypes, raw.rawBackingTypes);
    expect(resolved.rawBackingTypes, contains(ValueType.integer));
  });

  test('an unknown scalar still acquires newly written address provenance', () {
    final box = ClassType(null, 'PointedTo');
    final program = IrProgram([
      IrClass(box, []),
      IrClass(ValueType.integer, []),
    ], []);
    final private = _step(
      FlowState(program, memoryLayout: _Layout()),
      NewPayload(box, const Constant.integer(0)),
      [_integer(0)],
    );
    final scalar = _step(
      private.normal!,
      MaterializeValue(const Constant.integer(42)),
      [_integer(42)],
    );
    final backing = scalar.value.managedBackings.single;
    final unknown = FlowValue.unknown(ValueType.integer)
        .withManagedBackings([backing], unknown: true);
    expect(scalar.normal!.resolveValue(unknown).references.isBottom, isTrue);
    final pointer = FlowAddress(private.value.objects.single, 0);
    final runtimeAddress = Block([ValueType.integer]).parameters.single;
    final written = _step(
      scalar.normal!,
      StoreObjectData(
        backing.site,
        const Constant.integer(ObjectHeader.fieldsOffset),
        NativeScalarType(Int64),
        runtimeAddress,
      ),
      [
        FlowValue.object(backing),
        _integer(ObjectHeader.fieldsOffset),
        FlowValue.address(pointer),
      ],
    ).normal!;
    final resolved = written.resolveValue(unknown);
    expect(resolved.addresses, contains(pointer));
    expect(resolved.references.objects, contains(private.value.objects.single));
    expect(
      written.project([resolved]).containsObject(private.value.objects.single),
      isTrue,
    );
  });
}

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));

  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([.word]);
}

FlowValue _integer(int value) => FlowValue.constant(Constant.integer(value));

FlowResult _step(
  FlowState state,
  Instruction operation,
  List<FlowValue> inputs,
) => state.transfer(
  operation,
  inputs,
  allocate: (site) => FlowObject(site, Object()),
  repeated: false,
  invoke: (_, _, _) => throw StateError('unexpected call'),
  call: (_, _, _) => throw StateError('unexpected call'),
)!;
