import 'dart:ffi' show Uint8, Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('memory:address-flow');
final _type = ClassType(_uri, 'Storage');
final _object = ObjectConstant(_type, {});

ProgramFlowFacts _analyze(
  Block block, {
  List<FlowValue> arguments = const [],
  FlowMemoryLayout? memoryLayout,
}) {
  final function = IrFunction(
    FunctionTarget(
      _uri,
      'entry',
      .dynamicType,
      block.parameters.map((p) => p.type),
    ),
    [block],
  );
  final program = IrProgram([IrClass(_type, [])], [function]);
  return ProgramFlow(program, [
    (target: function.target, arguments: arguments),
  ], memoryLayout: memoryLayout).facts;
}

void main() {
  test(
    'managed offsets survive pointer views, scaled offsets and recovery',
    () {
      final block = Block();
      final base = block.emit(ReferenceAddress(_object));
      final bytes = block.emit(
        IntBinary(.add, base, const Constant.integer(40)),
      );
      final pointer = block.emit(
        PointerFromAddress(bytes, FfiTypes.int64Pointer),
      );
      final shifted = block.emit(
        PointerOffset(pointer, const Constant.integer(-2)),
      );
      final address = block.emit(PointerAddress(shifted));
      final back = block.emit(
        IntBinary(.subtract, address, const Constant.integer(24)),
      );
      final reference = block.emit(ReferenceFromAddress(back, _type));
      block.finish(Return(reference));
      final facts = _analyze(block, memoryLayout: _Memory());
      expect(facts.valueOf(address).addresses.single.offset, 24);
      expect(
        facts.valueOf(reference).constant?.structuralKey,
        _object.structuralKey,
      );
      expect(
        facts.valueOf(address).references.constants.single.structuralKey,
        _object.structuralKey,
      );
    },
  );

  test(
    'unknown offsets retain their base without inventing an in-bounds read',
    () {
      final block = Block([ValueType.integer]);
      final base = block.emit(ReferenceAddress(_object));
      final address = block.emit(
        IntBinary(.add, base, block.parameters.single),
      );
      final reference = block.emit(ReferenceFromAddress(address, _type));
      block.finish(Return(reference));
      final facts = _analyze(block, arguments: [FlowValue.unknown(.integer)]);
      expect(facts.valueOf(address).addresses.single.offset, isNull);
      expect(facts.valueOf(address).unknownTypes, isEmpty);
      expect(facts.valueOf(reference).constant, isNull);
      expect(
        facts.valueOf(reference).references.constants.single.structuralKey,
        _object.structuralKey,
      );
    },
  );

  test('relative differences fold but independent base addresses do not', () {
    final otherType = ClassType(_uri, 'OtherStorage');
    final other = ObjectConstant(otherType, {});
    final block = Block();
    final base = block.emit(ReferenceAddress(_object));
    final end = block.emit(IntBinary(.add, base, const Constant.integer(12)));
    final distance = block.emit(IntBinary(.subtract, end, base));
    final unrelated = block.emit(
      IntBinary(.subtract, base, block.emit(ReferenceAddress(other))),
    );
    block.finish(Return(distance));
    final facts = _analyze(block);
    expect(
      facts.valueOf(distance).constant?.structuralKey,
      const Constant.integer(12).structuralKey,
    );
    expect(facts.valueOf(unrelated).constant, isNull);
  });

  test('native bytes follow actual addresses through a call summary', () {
    final layout = _Memory();
    final start = layout.objectLayout(_type).size;
    final relay = FunctionTarget(_uri, 'offset', .integer, [.integer]);
    final called = Block(relay.parameterTypes);
    called.finish(
      Return(
        called.emit(
          IntBinary(.add, called.parameters.single, const Constant.integer(1)),
        ),
      ),
    );
    final block = Block();
    final storage = block.emit(NewPayload(_type, const Constant.integer(4)));
    final base = block.emit(ReferenceAddress(storage));
    final data = block.emit(IntBinary(.add, base, Constant.integer(start)));
    final zero = block.emit(LoadNative(data, NativeScalarType(Uint8)));
    final address = block.emit(DirectCall(relay, [data]));
    block.emit(
      StoreNative(
        address,
        NativeScalarType(Uint8),
        const Constant.integer(0x107),
      ),
    );
    final result = block.emit(LoadNative(address, NativeScalarType(Uint8)));
    final header = block.emit(LoadNative(base, NativeScalarType(Uint8)));
    block.finish(Return(result));
    final entry = IrFunction(FunctionTarget(_uri, 'bytes', .integer, []), [
      block,
    ]);
    final program = IrProgram(
      [IrClass(_type, [])],
      [
        entry,
        IrFunction(relay, [called]),
      ],
    );
    final facts = ProgramFlow(program, [
      (target: entry.target, arguments: []),
    ], memoryLayout: layout).facts;
    expect(
      facts.valueOf(zero).constant?.structuralKey,
      const Constant.integer(0).structuralKey,
    );
    expect(
      facts.returnedBy(entry.target).constant?.structuralKey,
      const Constant.integer(7).structuralKey,
    );
    expect(facts.valueOf(header).constant, isNull);
  });

  test('an address stored in native bytes retains its managed identity', () {
    final layout = _Memory();
    final block = Block();
    final storage = block.emit(NewPayload(_type, const Constant.integer(8)));
    final start = block.emit(
      IntBinary(
        .add,
        block.emit(ReferenceAddress(storage)),
        Constant.integer(layout.objectLayout(_type).size),
      ),
    );
    final address = block.emit(ReferenceAddress(_object));
    block.emit(StoreNative(start, NativeScalarType(Int64), address));
    final read = block.emit(LoadNative(start, NativeScalarType(Int64)));
    final reference = block.emit(ReferenceFromAddress(read, _type));
    block.finish(Return(reference));
    final facts = _analyze(block, memoryLayout: layout);
    expect(
      facts.valueOf(reference).constant?.structuralKey,
      _object.structuralKey,
    );
  });

  test('null survives pointer and reference round trips', () {
    final block = Block();
    final base = block.emit(ReferenceAddress(const Constant.nullValue()));
    final pointer = block.emit(PointerFromAddress(base, FfiTypes.int64Pointer));
    final address = block.emit(PointerAddress(pointer));
    final result = block.emit(ReferenceFromAddress(address, .object.nullable));
    block.finish(Return(result));
    final facts = _analyze(block);
    expect(
      facts.valueOf(base).constant?.structuralKey,
      const Constant.integer(0).structuralKey,
    );
    expect(
      facts.valueOf(result).constant?.structuralKey,
      const Constant.nullValue().structuralKey,
    );
  });

  test('pointer element scaling is not inferred without target layout', () {
    final block = Block();
    final base = block.emit(ReferenceAddress(_object));
    final pointer = block.emit(PointerFromAddress(base, FfiTypes.int64Pointer));
    final shifted = block.emit(
      PointerOffset(pointer, const Constant.integer(2)),
    );
    block.finish(Return(shifted));
    final facts = _analyze(block);
    expect(facts.valueOf(shifted).addresses.single.offset, isNull);
  });
}

final class _Memory() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .arm64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([]);
}
