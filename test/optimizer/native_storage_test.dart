import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _type = ClassType(null, 'Bytes');
final _program = IrProgram([IrClass(_type, [])], []);
final _layout = _Layout();
final _activation = Object();
final _u8 = NativeScalarType(Uint8);
final _u32 = NativeScalarType(Uint32);
final _i64 = NativeScalarType(Int64);
const _placeholder = Constant.integer(0);

void main() {
  test('string constants expose UTF-16 bytes within their payload only', () {
    const literal = Constant.string('A\u{1f642}\ud800');
    final state = FlowState(_program, memoryLayout: _layout);
    final start = _layout.objectLayout(ValueType.string).size;
    final address = FlowValue.address(FlowAddress(literal, start));
    for (final (index, unit) in [65, 0xd83d, 0xde42, 0xd800].indexed) {
      expect(
        _number(
          _load(state, _offset(address, index * 2), NativeScalarType(Uint16)),
        ),
        unit,
      );
      expect(
        _number(_load(state, _offset(address, index * 2), _u8)),
        unit & 0xff,
      );
    }
    for (final offset in [-1, 7, 8]) {
      expect(
        _load(
          state,
          _offset(address, offset),
          NativeScalarType(Uint16),
        ).constant,
        isNull,
      );
    }
    expect(_load(FlowState(_program), address, _u8).constant, isNull);
  });

  test('rebound SSA definitions do not alias earlier payload contents', () {
    final allocation = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final value = FlowValue.integerRange(FlowIntegerRange(3, 9))
        .withSource(Block([.integer]).parameters.single, _activation);
    final before = _store(allocation.state, allocation.address, _i64, value);
    final after = before.copy()..retainSources((_) => false);
    expect(_load(before, allocation.address, _i64), value);
    expect(_load(after, allocation.address, _i64), value.withSources(const []));
  });

  test('native integer fragments widen as one stored value at loop joins', () {
    final allocation = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final before = _store(
      allocation.state,
      allocation.address,
      _i64,
      FlowValue.integerRange(FlowIntegerRange(3, 5)),
    );
    final after = _store(
      before,
      allocation.address,
      _i64,
      FlowValue.integerRange(FlowIntegerRange(3, 9)),
    );
    final union = before.copy()..join(after);
    final widened = before.copy()..join(after, widen: true);
    expect(
      _load(union, allocation.address, _i64).integers,
      FlowIntegerRange(3, 9),
    );
    expect(
      _load(widened, allocation.address, _i64).integers,
      FlowIntegerRange(3, FlowIntegerRange.maximum),
    );
    expect(widened.join(after, widen: true), isFalse);
  });

  test(
    'zeroed payload excludes the header and requires an explicit target',
    () {
      final allocation = _allocate(
        FlowState(_program, memoryLayout: _layout),
        16,
      );
      final start = _layout.objectLayout(_type).size;
      expect(
        _load(allocation.state, allocation.address, _i64).constant,
        isA<ScalarConstant>().having((c) => c.value, 'value', 0),
      );
      for (final offset in [0, start - 1, start + 12, start + 16]) {
        final address = FlowValue.address(
          FlowAddress(allocation.object.objects.single, offset),
        );
        expect(_load(allocation.state, address, _i64).constant, isNull);
      }
      final unknown = _allocate(FlowState(_program), 16);
      expect(_load(unknown.state, unknown.address, _u8).constant, isNull);
      expect(
        () =>
            allocation.state.join(FlowState(_program, memoryLayout: _Layout())),
        throwsArgumentError,
      );
    },
  );

  test(
    'bounded reads inspect sparse interior changes without enumerating memory',
    () {
      const length = 1 << 30;
      final a = _allocate(FlowState(_program, memoryLayout: _layout), length);
      final start = a.address.addresses.single.offset!;
      final offsets = FlowValue.integerRange(
        FlowIntegerRange(start, start + length - 8),
      );
      final load = LoadObjectData(
        ObjectConstant(_type, {}),
        _placeholder,
        _i64,
      );
      expect(
        _number(_step(a.state, load, operands: [a.object, offsets]).value),
        0,
      );
      final middle = _store(
        a.state,
        _offset(a.address, length ~/ 2),
        _u8,
        _integer(1),
      );
      final changed = _step(middle, load, operands: [a.object, offsets]).value;
      expect(changed.constant, isNull);
      expect(changed.integers!.contains(1), isTrue);
      expect(changed.integers!.contains(1 << 56), isTrue);
      expect(
        _number(_step(a.state, load, operands: [a.object, offsets]).value),
        0,
      );
    },
  );

  test('bounded reads agree with every concrete byte window', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 12);
    final start = a.address.addresses.single.offset!;
    final bytes = [0, 0, 7, 7, 7, 0, 2, 9, 0, 0, 0, 0];
    var state = a.state;
    for (final (index, byte) in bytes.indexed) {
      state = _store(state, _offset(a.address, index), _u8, _integer(byte));
    }
    final load = LoadObjectData(ObjectConstant(_type, {}), _placeholder, _u32);
    for (var lower = 0; lower <= bytes.length - 4; lower++) {
      for (var upper = lower; upper <= bytes.length - 4; upper++) {
        final result = _step(
          state,
          load,
          operands: [
            a.object,
            FlowValue.integerRange(
              FlowIntegerRange(start + lower, start + upper),
            ),
          ],
        ).value;
        final actual = [
          for (var offset = lower; offset <= upper; offset++)
            bytes[offset] |
                bytes[offset + 1] << 8 |
                bytes[offset + 2] << 16 |
                bytes[offset + 3] << 24,
        ]..sort();
        for (final value in actual) {
          expect(
            result.integers!.contains(value),
            isTrue,
            reason: 'byte starts $lower..$upper lost $value',
          );
        }
        expect(result.integers!.lower, actual.first);
        expect(result.integers!.upper, actual.last);
      }
    }
  });

  test(
    'aligned byte reads include unknown regions between unaligned boundaries',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 24);
      final start = a.address.addresses.single.offset!;
      final changed = _step(
        a.state,
        StoreObjectData(
          ObjectConstant(_type, {}),
          _placeholder,
          _u32,
          _placeholder,
        ),
        operands: [a.object, _integer(start + 5), FlowValue.unknown(.integer)],
      ).normal!;
      final value = _step(
        changed,
        LoadObjectData(ObjectConstant(_type, {}), _placeholder, _u8),
        operands: [
          a.object,
          FlowValue.integerRange(
            FlowIntegerRange(start, start + 16, zeroBits: 3),
          ),
        ],
      ).value;
      expect(value.constant, isNull);
      expect(value.integers!.contains(255), isTrue);
    },
  );

  test(
    'bounded writes preserve outside bytes, other allocations and snapshots',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
      final b = _allocate(a.state, 8);
      final start = a.address.addresses.single.offset!;
      final store = StoreObjectData(
        ObjectConstant(_type, {}),
        _placeholder,
        _u32,
        _placeholder,
      );
      final written = _step(
        b.state,
        store,
        operands: [
          a.object,
          FlowValue.integerRange(FlowIntegerRange(start + 4, start + 7)),
          _integer(42),
        ],
      ).normal!;
      for (var index = 0; index < 16; index++) {
        expect(
          _number(_load(written, _offset(a.address, index), _u8)),
          4 <= index && index < 11 ? isNull : 0,
          reason: 'byte $index',
        );
        expect(_number(_load(b.state, _offset(a.address, index), _u8)), 0);
      }
      expect(_number(_load(written, b.address, _i64)), 0);
      for (final offsets in [
        FlowIntegerRange(start - 1, start + 1),
        FlowIntegerRange(start + 12, start + 13),
      ]) {
        final escaped = _step(
          b.state,
          store,
          operands: [a.object, FlowValue.integerRange(offsets), _integer(42)],
        ).normal!;
        expect(_load(escaped, b.address, _i64).constant, isNull);
      }
    },
  );

  test('native aliases observe truncated, signed and overlapping writes', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final first = _store(a.state, a.address, _u32, _integer(0x12345678));
    final byte = _offset(a.address, 1);
    expect(_number(_load(first, byte, NativeScalarType(Uint16))), 0x3456);
    final second = _store(first, byte, _u8, _integer(0x1ff));
    expect(_number(_load(second, a.address, _u32)), 0x1234ff78);
    expect(_number(_load(second, byte, NativeScalarType(Int8))), -1);
    expect(_number(_load(a.state, a.address, _u32)), 0);
    expect(_number(_load(first, a.address, _u32)), 0x12345678);
  });

  test(
    'native precision, negative zero and boolean storage match their types',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
      final f32 = NativeScalarType(Float), f64 = NativeScalarType(Double);
      final rounded = _store(
        a.state,
        a.address,
        f32,
        .constant(const Constant.floating(16777217.0)),
      );
      expect(_number(_load(rounded, a.address, f32)), 16777216.0);
      final signed = _store(
        rounded,
        a.address,
        f64,
        .constant(const Constant.floating(-0.0)),
      );
      expect(
        1 / (_number(_load(signed, a.address, f64)) as double),
        double.negativeInfinity,
      );
      final boolean = _store(signed, a.address, _u8, _integer(128));
      expect(
        _load(
          boolean,
          a.address,
          NativeScalarType(Bool),
        ).constant?.structuralKey,
        const Constant.boolean(true).structuralKey,
      );
    },
  );

  test(
    'joins retain untouched bytes and weaken ambiguous or repeated writes',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
      final b = _allocate(a.state, 16);
      final left = _store(b.state, a.address, _u8, _integer(1));
      final right = _store(b.state, a.address, _u8, _integer(2));
      final joined = left.copy()..join(right);
      expect(_load(joined, a.address, _u8).constant, isNull);
      expect(_number(_load(joined, _offset(a.address, 1), _u8)), 0);
      final uncertain = _store(
        b.state,
        a.address.join(b.address),
        _u8,
        _integer(9),
      );
      expect(_load(uncertain, a.address, _u8).constant, isNull);
      expect(_load(uncertain, b.address, _u8).constant, isNull);

      final operation = NewPayload(_type, const Constant.integer(16));
      final result = _step(b.state, operation, repeated: true);
      final address = FlowValue.address(
        FlowAddress(
          result.value.objects.single,
          _layout.objectLayout(_type).size,
        ),
      );
      final repeated = _store(result.normal!, address, _u8, _integer(3));
      expect(_load(repeated, address, _u8).constant, isNull);
    },
  );

  test('external writes invalidate exposed storage, unbounded addresses do not guess bounds', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final b = _allocate(a.state, 8);
    final external = b.state.copy()..invalidate([a.address]);
    expect(_load(external, a.address, _i64).constant, isNull);
    expect(_number(_load(external, b.address, _i64)), 0);
    final unbounded = FlowValue.address(
      FlowAddress(a.object.objects.single, null),
    );
    final unknown = _store(b.state, unbounded, _u8, _integer(7));
    expect(_load(unknown, a.address, _u8).constant, isNull);
    expect(_load(unknown, b.address, _u8).constant, isNull);
    expect(_load(b.state, unbounded, _u8).constant, isNull);
  });

  test('unknown copy sources invalidate only the destination range', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final copied = _step(
      a.state,
      CopyNative(_placeholder, _placeholder, NativeArrayType(_u8, 4)),
      operands: [_offset(a.address, 4), .unknown(.integer)],
    ).normal!;
    expect(_number(_load(copied, a.address, _u32)), 0);
    expect(_load(copied, _offset(a.address, 4), _u32).constant, isNull);
    expect(_number(_load(copied, _offset(a.address, 8), _i64)), 0);
    final empty = _step(
      a.state,
      CopyNative(
        _placeholder,
        _placeholder,
        NativeArrayType(_u8, 0, variableLength: true),
      ),
      operands: [.unknown(.integer), .unknown(.integer)],
    );
    expect(empty.effects, isEmpty);
    expect(empty.normal, a.state);
  });

  test('native copies use the source snapshot across overlapping ranges', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final first = _store(
      a.state,
      a.address,
      _i64,
      _integer(0x0807060504030201),
    );
    final copied = _step(
      first,
      CopyNative(_placeholder, _placeholder, NativeArrayType(_u8, 8)),
      operands: [_offset(a.address, 2), a.address],
    ).normal!;
    expect(
      _number(_load(copied, _offset(a.address, 2), _i64)),
      0x0807060504030201,
    );
    expect(_number(_load(copied, a.address, _u32)), 0x02010201);
  });

  test(
    'large zeroed allocations and copies do not enumerate their byte range',
    () {
      const size = 1 << 30;
      final a = _allocate(FlowState(_program, memoryLayout: _layout), size);
      final b = _allocate(a.state, size);
      final source = _store(
        b.state,
        _offset(a.address, size - 1),
        _u8,
        _integer(42),
      );
      final copied = _step(
        source,
        CopyNative(_placeholder, _placeholder, NativeArrayType(_u8, size)),
        operands: [b.address, a.address],
      ).normal!;
      expect(_number(_load(copied, _offset(b.address, size - 1), _u8)), 42);
      expect(_number(_load(copied, _offset(b.address, size - 8), _u32)), 0);
    },
  );

  test('stored addresses retain allocation identities through projection and summaries', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final b = _allocate(a.state, 8);
    final input = b.state.project([a.address, b.address]);
    final output = _store(input, a.address, _i64, b.address);
    final mapped = FlowObject(b.object.objects.single.site, Object());
    FlowObject object(FlowObject value) =>
        value == b.object.objects.single ? mapped : value;
    FlowValue value(FlowValue source) => source.mapObjects(object);
    final applied = b.state.applySummary(
      input,
      output,
      mapObject: object,
      mapValue: value,
    );
    final address = _load(applied, a.address, _i64).addresses.single;
    expect(address.base, mapped);
    expect(address.offset, b.address.addresses.single.offset);
    expect(applied.reachableValues([a.object]).objects, contains(mapped));
    expect(_number(_load(b.state, a.address, _i64)), 0);
  });

  test('partial writes destroy a stored address without losing its reachable owner', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final b = _allocate(a.state, 8);
    final stored = _store(b.state, a.address, _i64, b.address);
    final overwritten = _store(stored, _offset(a.address, 3), _u8, _integer(0));
    final value = _load(overwritten, a.address, _i64);
    expect(value.addresses, isEmpty);
    expect(value.references.objects, contains(b.object.objects.single));
    final exposed = stored.copy()..invalidate([a.address]);
    expect(_load(exposed, a.address, _i64).addresses, isEmpty);
    expect(
      exposed.reachableValues([a.object]).objects,
      contains(b.object.objects.single),
    );
  });
}

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));

  @override
  ObjectLayout objectLayout(ClassType type) =>
      ObjectLayout([.word, .reference]);
}

({FlowState state, FlowValue object, FlowValue address}) _allocate(
  FlowState state,
  int bytes,
) {
  final result = _step(state, NewPayload(_type, Constant.integer(bytes)));
  return (
    state: result.normal!,
    object: result.value,
    address: FlowValue.address(
      FlowAddress(
        result.value.objects.single,
        _layout.objectLayout(_type).size,
      ),
    ),
  );
}

FlowValue _offset(FlowValue value, int amount) {
  final address = value.addresses.single;
  return FlowValue.address(FlowAddress(address.base, address.offset! + amount));
}

FlowValue _integer(int value) => .constant(Constant.integer(value));
Object? _number(FlowValue value) => (value.constant as ScalarConstant?)?.value;

FlowValue _load(FlowState state, FlowValue address, NativeTypeRef type) =>
    _step(state, LoadNative(_placeholder, type), operands: [address]).value;

FlowState _store(
  FlowState state,
  FlowValue address,
  NativeTypeRef type,
  FlowValue value,
) => _step(
  state,
  StoreNative(
    _placeholder,
    type,
    type.isFloating ? const Constant.floating(0) : _placeholder,
  ),
  operands: [address, value],
).normal!;

FlowResult _step(
  FlowState state,
  Instruction operation, {
  List<FlowValue>? operands,
  bool repeated = false,
}) => state.transfer(
  operation,
  operands ??
      operation.inputs.map((v) => FlowValue.constant(v as Constant)).toList(),
  allocate: (site) => FlowObject(site, _activation),
  repeated: repeated,
  invoke: (_, _, _) => throw StateError('Unexpected call'),
  call: (_, _, _) => throw StateError('Unexpected closure'),
)!;
