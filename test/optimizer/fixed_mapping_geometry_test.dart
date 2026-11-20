import 'dart:ffi' show Int64;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/optimizer/integer_range.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/src/optimizer/memory_layout.dart';
import 'package:dartc/target.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/layout.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('memory:retirement-geometry');
final _map = FunctionTarget(_uri, 'map', .integer, [.integer]);
final _word = NativeScalarType(Int64);
const _zero = Constant.integer(0);

final class _Layout implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([]);
}

FlowObject _region() => FlowObject(DirectCall(_map, [_zero]), Object());
FlowValue _address(FlowObject region, [int offset = 0]) =>
    FlowValue.address(FlowAddress(FlowRegion(region), offset));
FlowValue _int(int value) => FlowValue.constant(Constant.integer(value));
FlowState _mapRegion(FlowState s, FlowObject a, [int bytes = 4096]) =>
    s.allocateMemory(a, _int(bytes), repeated: false).normal!;
FlowResult _transfer(FlowState s, Instruction op, List<FlowValue> args) =>
    s.transfer(
      op,
      args,
      allocate: (_) => throw StateError('unexpected allocation'),
      repeated: false,
      invoke: (_, _, _) => throw StateError('unexpected call'),
      call: (_, _, _) => throw StateError('unexpected closure'),
    )!;
FlowState _store(FlowState s, FlowObject a, int value) => _transfer(
  s,
  StoreNative(_zero, _word, _zero),
  [_address(a), _int(value)],
).normal!;
int? _read(FlowState s, FlowObject a) => _transfer(
  s,
  LoadNative(_zero, _word),
  [_address(a)],
).value.integers?.constant;
FlowState _release(FlowState s, FlowValue p, [int width = 4096]) =>
    s.overwriteNative(p, _int(width), release: true);

void main() {
  for (final mode in [
    'local',
    'published',
    'host writes',
    'released',
    'cross-end',
    'external',
    'replacement',
  ]) {
    test('a fixed module block after a previous retirement ($mode)', () {
      final data = NativeData(List.filled(64, 0), alignment: 8);
      final b0 = Block(), target = FunctionTarget(_uri, 'fixed', .integer, []);
      final ref = b0.emit(NativeDataAddress(data));
      b0.finish(Return(ref));
      var s = FlowState(
        IrProgram([], [
          IrFunction(target, [b0]),
        ]),
        memoryLayout: _Layout(),
      );
      final fixed = _transfer(s, ref, []).value;
      final fixedId = (fixed.addresses.single.base as FlowRegion).allocation;
      final old = _region(), first = _region(), second = _region();
      s = _release(_mapRegion(s, old), _address(old));
      s = _mapRegion(_mapRegion(s, first), second);
      final candidate = FlowValue.joined([
        for (final id in [first, second])
          FlowValue.address(
            FlowAddress.ranged(
              FlowRegion(id),
              FlowIntegerRange(0, mode == 'cross-end' ? 4090 : 4032),
            ),
          ),
      ]);
      if (mode == 'published') {
        s.recordEscape([fixed]);
        s.publishMappingCapabilities();
      } else if (mode == 'host writes') {
        s.invalidate([fixed]);
      } else if (mode == 'released') {
        s = _release(s, fixed, 64);
      }
      s = _store(s, fixedId, 1009);
      final ready = _release(s, _address(first))
        ..join(_release(s, _address(second)));
      // The two destination ranges replicate the real StoreNative offsets.
      final replacement = _region();
      final before = mode == 'replacement'
          ? _store(_mapRegion(ready, replacement), replacement, 47)
          : ready;
      final address = mode == 'external'
          ? candidate.join(FlowValue.unknown(.integer, external: true))
          : candidate;
      final result = _transfer(before, StoreNative(_zero, _word, _zero), [
        address,
        _int(0),
      ]).normal!;
      if (mode == 'replacement') expect(_read(result, replacement), isNull);
      if (mode == 'local' || mode == 'replacement') {
        expect(_read(result, fixedId), 1009);
      } else {
        expect(_read(result, fixedId), isNull);
      }
    });
  }
  for (final hasConflictingOccupant in [false, true]) {
    test(
      'summary materialization distinguishes a missing region from a different occupant ($hasConflictingOccupant)',
      () {
        final data = NativeData(List.filled(64, 0), alignment: 8);
        final block = Block(),
            target = FunctionTarget(_uri, 'materialize', .integer, []);
        final fixedRead = block.emit(NativeDataAddress(data));
        block.finish(Return(fixedRead));
        final s = FlowState(
          IrProgram([], [
            IrFunction(target, [block]),
          ]),
          memoryLayout: _Layout(),
        );
        final fixed =
            (_transfer(s, fixedRead, []).value.addresses.single.base
                    as FlowRegion)
                .allocation;
        final source = _region();
        final caller = _store(s, fixed, 1009);
        final before = _mapRegion(caller, source).copy(resetWrites: true);
        final after = _release(before, _address(source));
        final input = hasConflictingOccupant
            ? _mapRegion(caller, source, 64)
            : caller;
        final returned = input.applySummary(
          before,
          after,
          mapObject: (a) => a,
          mapValue: (a) => a,
        );
        final result = _release(returned, _address(source));
        expect(_read(result, fixed), hasConflictingOccupant ? isNull : 1009);
      },
    );
  }
}
