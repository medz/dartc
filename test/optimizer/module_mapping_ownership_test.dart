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

final class _Layout() implements FlowMemoryLayout {
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

final class _Module() {
  final slot = GlobalVariable(_uri, 'slot', .integer, isLate: true);
  final dataA = NativeData(List.filled(64, 0), alignment: 8);
  final dataB = NativeData(List.filled(64, 0), alignment: 8);
  late final a = NativeDataAddress(dataA), b = NativeDataAddress(dataB);
  late final FlowValue addressA, addressB;
  late final FlowObject bId;
  late final FlowState initial;
  this {
    final entry = Block(),
        target = FunctionTarget(_uri, 'symbols', .integer, []);
    entry.emit(a);
    entry.emit(b);
    entry.finish(Return(b));
    final root = FlowState(
      IrProgram(
        [],
        [
          IrFunction(target, [entry]),
        ],
        globals: [slot],
      ),
      memoryLayout: _Layout(),
    );
    addressA = _transfer(root, a, []).value;
    addressB = _transfer(root, b, []).value;
    bId = (addressB.addresses.single.base as FlowRegion).allocation;
    initial = _store(root, bId, 1009);
  }

  FlowState onlyA(FlowState s) => s.project(
    [addressA],
    access: (
      globals: {},
      fields: {},
      data: {dataA},
      modules: {},
      context: false,
      memory: false,
      exposed: false,
      writes: false,
      rawWrites: false,
      cells: false,
    ),
  );
}

void main() {
  for (final exposure in [
    'none',
    'direct',
    'neighbor',
    'borrow',
    'release',
    'page-release',
    'unknown-release',
    'refs',
  ]) {
    test('fixed neighbors and a later checked mapping with $exposure', () {
      const page = 16384;
      final m = _Module(),
          prior = _region(),
          first = _region(),
          second = _region();
      var s = m.initial.copy();
      if (exposure == 'direct' ||
          exposure == 'neighbor' ||
          exposure == 'refs') {
        final passed = switch (exposure) {
          'direct' => m.addressB,
          'neighbor' => m.addressA,
          _ => const FlowValue.bottom().withReferences([m.addressA]),
        };
        s.recordEscape([passed]);
        s.publishMappingCapabilities();
      } else if (exposure == 'borrow') {
        s.invalidate([m.addressA]);
      } else if (exposure == 'release' || exposure == 'page-release') {
        s = _release(s, m.addressA, exposure == 'release' ? 64 : page);
      } else if (exposure == 'unknown-release') {
        s = s.overwriteNative(
          m.addressA,
          FlowValue.unknown(.integer),
          release: true,
        );
      }
      final isolated = ['none', 'borrow', 'release'].contains(exposure);
      expect(_read(s, m.bId), isolated ? 1009 : isNull);
      s = _release(_mapRegion(s, prior, page), _address(prior), page);
      s = _mapRegion(_mapRegion(s, first, page), second, page);
      s = _store(s, m.bId, 1009);
      s = _release(s, _address(first), page)
        ..join(_release(s, _address(second), page));
      for (final maxOffset in [page - 8, page - 16, page - 7]) {
        final at = FlowValue.joined([
          for (final r in [first, second])
            FlowValue.address(
              FlowAddress.ranged(FlowRegion(r), FlowIntegerRange(0, maxOffset)),
            ),
        ]);
        final written = _transfer(s, StoreNative(_zero, _word, _zero), [
          at,
          _int(77),
        ]).normal!;
        final read = _transfer(written, LoadNative(_zero, _word), [
          m.addressB,
        ]).value.integers;
        if (isolated && maxOffset <= page - 8) {
          expect(read?.constant, 1009);
        } else {
          expect(read?.contains(77) ?? true, isTrue);
        }
      }
    });
  }
  for (final route in ['summary', 'join-left', 'join-right', 'stale-summary']) {
    test('module mapping lifetime propagates across partial $route', () {
      final m = _Module(), entry = m.onlyA(m.initial).copy(resetWrites: true);
      final partial = entry.copy()
        ..recordEscape([m.addressA])
        ..publishMappingCapabilities();
      final result = switch (route) {
        'summary' => m.initial.applySummary(
          entry,
          partial,
          mapObject: (o) => o,
          mapValue: (v) => v,
        ),
        'join-left' => partial.copy(resetWrites: true)..join(m.initial),
        'join-right' => m.initial.copy()..join(partial.copy(resetWrites: true)),
        _ =>
          (m.initial.copy()
                ..recordEscape([m.addressA])
                ..publishMappingCapabilities())
              .applySummary(
                m.initial.copy(resetWrites: true),
                _store(m.initial.copy(resetWrites: true), m.bId, 1009),
                mapObject: (o) => o,
                mapValue: (v) => v,
                currentInput: false,
              ),
      };
      expect(_read(result, m.bId), isNull);
      expect(_read(m.initial, m.bId), 1009);
    });
  }
  test('an externally retained address survives an omitted sibling and its projection', () {
    final m = _Module(),
        target = _region(),
        base = _mapRegion(m.initial, target);
    final entry = m.onlyA(base).copy(resetWrites: true);
    final exit = entry.copy()
      ..recordEscape([m.addressA, _address(target)])
      ..publishMappingCapabilities();
    final returned = base.applySummary(
      entry,
      exit,
      mapObject: (o) => o,
      mapValue: (v) => v,
    );
    final read = _transfer(returned, LoadNative(_zero, _word), [
      m.addressB,
    ]).value;
    expect(
      read.references.addresses.any((p) => p.base == FlowRegion(target)),
      isTrue,
    );
    final projected = m.onlyA(returned);
    expect(projected.containsObject(target), isTrue);
    expect(projected.anchoredIdentities(), contains(target));
  });
  for (final reversed in [false, true]) {
    test(
      'joining projected inputs preserves fresh call history on normal and exceptional exits (reverse=$reversed)',
      () {
        final m = _Module();
        final handoff = m.onlyA(m.initial)
          ..recordEscape([m.addressA])
          ..publishMappingCapabilities();
        final original = m.initial.copy(resetWrites: true);
        final retired = handoff.copy(resetWrites: true);
        final entry = reversed ? retired.copy() : original.copy();
        expect(entry.join(reversed ? original : retired), isTrue);
        final beforeRead = _transfer(entry, LoadGlobal(m.slot), []);
        final checked = _transfer(entry, StoreGlobal(m.slot, _zero), [
          _int(83)
              .join(FlowValue.constant(const Constant.string('wrong type'))),
        ]);
        expect(checked.normal, isNotNull);
        expect(checked.hasSemanticFailure, isTrue);
        for (final (exceptional, exit) in [
          (false, checked.normal!),
          (true, checked.exceptional!),
        ]) {
          final returned = entry.applySummary(
            entry,
            exit,
            mapObject: (o) => o,
            mapValue: (v) => v,
          );
          final read = _transfer(returned, LoadGlobal(m.slot), []);
          if (exceptional) {
            expect(read.value, beforeRead.value);
            expect(read.hasSemanticFailure, beforeRead.hasSemanticFailure);
            expect(read.normal != null, beforeRead.normal != null);
          } else {
            expect(read.value.integers?.constant, 83);
          }
          expect(_read(returned, m.bId), isNull);
        }
        // An actual host operation, in contrast, does carry semantic writes.
        expect(
          () => original.applySummary(
            handoff,
            handoff,
            mapObject: (o) => o,
            mapValue: (v) => v,
          ),
          throwsArgumentError,
        );
      },
    );
  }
}
