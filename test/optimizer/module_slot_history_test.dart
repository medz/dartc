import 'dart:ffi' show Int8, Int32, Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/src/optimizer/integer_range.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

const z = Constant.integer(0);
const nv = Constant.nullValue();
final width = NativeScalarType(Int64);
FlowValue n(int x) => FlowValue.constant(Constant.integer(x));
final synthetic = FunctionTarget(null, 'map', .integer, [.integer]);
FlowObject region() => FlowObject(DirectCall(synthetic, [z]), Object());
FlowValue ptr(FlowObject x, [int offset = 0]) =>
    FlowValue.address(FlowAddress(FlowRegion(x), offset));
FlowValue ranged(FlowObject x, int max) => FlowValue.address(
  FlowAddress.ranged(FlowRegion(x), FlowIntegerRange(0, max)),
);
FlowResult step(FlowState s, Instruction op, List<FlowValue> args) =>
    s.transfer(
      op,
      args,
      allocate: (op) => FlowObject(op, Object()),
      repeated: false,
      invoke: (_, _, _) => throw StateError('invoke'),
      call: (_, _, _) => throw StateError('call'),
    )!;
bool nullOnly(FlowValue v) =>
    v.unknownTypes.isEmpty &&
    v.objects.isEmpty &&
    v.constants.length == 1 &&
    v.constants.single is ScalarConstant &&
    (v.constants.single as ScalarConstant).value == null;

void main() {
  test('unbounded zero writes preserve only a bound null module slot', () {
    final table = ClassType(null, 'Table');
    final item = ClassType(null, 'Item');
    final reference = InstanceField(table, 'reference', item.nullable);
    final marker = InstanceField(table, 'marker', .integer);
    final module = ModuleObject(table, initialFields: {
      reference: nv,
      marker: const Constant.integer(37),
    });
    final target = FunctionTarget(null, 'entry', .voidType, []);
    final block = Block();
    final address = block.emit(ModuleObjectReference(module));
    block.finish(const Return());
    final program = IrProgram([
      IrClass(table, [reference, marker]),
      IrClass(item, []),
    ], [IrFunction(target, [block])]);
    final initial = FlowState(program, memoryLayout: ProgramLayout(
      program.classes, nativeLayout: NativeLayout(Target.host()),
    ));
    final load = step(initial, address, []);
    final owner = load.value.objects.single;
    final entry = load.normal!.copy(resetWrites: true);
    final anywhere = FlowValue.unknown(.integer);
    for (final width in [Int8, Int32, Int64]) {
      final store = StoreNative(z, NativeScalarType(width), z);
      final zero = step(entry, store, [anywhere, n(0)]).normal!;
      expect(zero.storedValue(owner, reference).constant?.type, ValueType.nullType);
      expect(zero.storedValue(owner, marker).constant, isNull);
      final changed = step(entry, store, [anywhere, n(1)]).normal!;
      final again = step(changed, store, [anywhere, n(0)]).normal!;
      expect(again.storedValue(owner, reference).constant, isNull);
    }
  });

  for (final releasing in [false, true]) {
    for (final withNative in [false, true]) {
      for (final mode in [
        'intact',
        'replaceRegionOnly',
        'giveManaged',
        'giveNative',
        'globalRelease',
        'cross',
        'summaryExtra',
        'stale',
        'staleRetired',
        'retireHolder',
        'retireViaSummary',
        'arbitraryHolder',
        'writeHolder',
        'nestedStale',
        'projectRetired',
        'projectLive',
        'projectStale',
        'summaryPost',
        'managedArg',
      ]) {
        if (mode == 'giveNative' && !withNative) continue;
        test('unwritten module slots $mode data=$withNative release=$releasing', () {
          final t = ClassType(null, 'Holder'),
              callback = ClassType(null, 'Callback');
          final flag = InstanceField(t, 'flag', callback.nullable),
              marker = InstanceField(t, 'marker', .integer);
          final fixed = ModuleObject(
            t,
            initialFields: {flag: nv, marker: const Constant.integer(1009)},
          );
          final neighbour = ModuleObject(
            t,
            initialFields: {flag: nv, marker: const Constant.integer(19)},
          );
          final native = NativeData(List.filled(64, 0), alignment: 8);
          final g = GlobalVariable(
                Uri.parse('memory:slot'),
                'value',
                callback.nullable,
              ),
              ptrGlobal = GlobalVariable(
                Uri.parse('memory:slot'),
                'heap',
                t.nullable,
              );
          final root = FunctionTarget(null, 'use', .integer, []);
          final b = Block(),
              m = b.emit(ModuleObjectReference(fixed)),
              m2 = b.emit(ModuleObjectReference(neighbour));
          final data = withNative ? b.emit(NativeDataAddress(native)) : null;
          final newHeap = b.emit(NewPayload(t, z));
          b.finish(const Return(z));
          final graph = IrProgram(
            [
              IrClass(t, [flag, marker]),
              IrClass(callback, []),
            ],
            [
              IrFunction(root, [b]),
            ],
            globals: [g, ptrGlobal],
          );
          final layout = ProgramLayout(
            graph.classes,
            nativeLayout: NativeLayout(Target.host()),
          );
          var s = FlowState(graph, memoryLayout: layout);
          final fixedValue = step(s, m, []).value,
              secondValue = step(s, m2, []).value;
          final first = region(), second = region();
          final own = FlowValue.address(
            FlowAddress(secondValue.objects.single, layout.fieldOffset(marker)),
          );
          if (mode == 'retireHolder' ||
              mode == 'retireViaSummary' ||
              mode == 'writeHolder' ||
              mode == 'projectRetired') {
            final entry = s.copy(resetWrites: true);
            final updated = entry.overwriteNative(
              own,
              n(8),
              release: mode != 'writeHolder',
            );
            s = mode == 'retireViaSummary'
                ? s.applySummary(
                    entry,
                    updated,
                    mapObject: (x) => x,
                    mapValue: (x) => x,
                    currentInput: true,
                  )
                : updated;
          } else if (mode == 'arbitraryHolder' || mode == 'managedArg') {
            s.invalidate([mode == 'managedArg' ? secondValue : own]);
          }
          s = s
              .allocateMemory(first, n(4096), repeated: false)
              .normal!
              .allocateMemory(second, n(4096), repeated: false)
              .normal!;
          final h = step(s, newHeap, [n(0)]);
          s = step(h.normal!, StoreField(marker, newHeap, z), [
            h.value,
            n(37),
          ]).normal!;
          s = step(s, StoreGlobal(ptrGlobal, newHeap), [h.value]).normal!;
          if (mode == 'giveManaged' ||
              mode == 'giveNative' ||
              mode == 'globalRelease') {
            final address = mode == 'giveNative'
                ? step(s, data!, []).value
                : FlowValue.address(FlowAddress(secondValue.objects.single, 0));
            if (mode == 'globalRelease') {
              s = s.overwriteNative(address, n(4096), release: true);
            } else {
              s.recordEscape([address]);
              s.publishMappingCapabilities();
            }
          }
          // Establish known post-publication values; a later historical store can overwrite them only after a replacement.
          s = step(s, StoreField(flag, m, nv), [
            fixedValue,
            FlowValue.constant(nv),
          ]).normal!;
          s = step(s, StoreField(marker, m2, z), [secondValue, n(19)]).normal!;
          s = step(s, StoreGlobal(g, nv), [FlowValue.constant(nv)]).normal!;
          final a = s.overwriteNative(ptr(first), n(4096), release: true);
          final c = s.overwriteNative(ptr(second), n(4096), release: true);
          final merged = a..join(c);
          final base = merged.copy(resetWrites: true);
          final range = ranged(
            first,
            mode == 'cross' ? 4090 : 4032,
          ).join(ranged(second, mode == 'cross' ? 4090 : 4032));
          FlowState update(FlowState state) => releasing
              ? state.overwriteNative(range, n(8), release: true)
              : step(state, StoreNative(z, width, z), [range, n(81)]).normal!;
          final written = update(base);
          var result = written;
          if (mode == 'summaryExtra' ||
              mode == 'stale' ||
              mode == 'staleRetired' ||
              mode == 'nestedStale') {
            var caller = merged
                .allocateMemory(region(), n(4096), repeated: false)
                .normal!;
            if (mode == 'staleRetired') {
              caller = caller.overwriteNative(
                FlowValue.address(FlowAddress(secondValue.objects.single, 0)),
                n(4096),
                release: true,
              );
            }
            // Caller-owned module state must not be restored from an irrelevant exit.
            result = caller.applySummary(
              base,
              written,
              mapObject: (x) => x,
              mapValue: (x) => x,
              currentInput: mode == 'summaryExtra',
            );
            if (mode == 'nestedStale') {
              final outer = caller.copy(resetWrites: true);
              final inner = outer.applySummary(
                base,
                written,
                mapObject: (x) => x,
                mapValue: (x) => x,
                currentInput: false,
              );
              final client = caller
                  .allocateMemory(region(), n(128), repeated: false)
                  .normal!;
              result = client.applySummary(
                outer,
                inner,
                mapObject: (x) => x,
                mapValue: (x) => x,
                currentInput: true,
              );
            }
          } else if (mode == 'summaryPost') {
            final out = step(written, StoreField(marker, newHeap, z), [
              h.value,
              n(49),
            ]).normal!;
            final caller = merged
                .allocateMemory(region(), n(128), repeated: false)
                .normal!;
            result = caller.applySummary(
              base,
              out,
              mapObject: (x) => x,
              mapValue: (x) => x,
              currentInput: true,
            );
          } else if (mode.startsWith('project')) {
            final thin = merged
                .project(
                  [ptr(first), ptr(second)],
                  access: (
                    fields: {},
                    globals: {},
                    data: {},
                    modules: {},
                    context: false,
                    cells: false,
                    memory: true,
                    writes: true,
                    exposed: false,
                    rawWrites: false,
                  ),
                )
                .copy(resetWrites: true);
            final after = update(thin);
            if (mode == 'projectStale') {
              // A callee that has only a projected outer context cannot mark private module slots here.
              final outer = thin.copy(resetWrites: true);
              final stale = outer.applySummary(
                thin,
                after,
                mapObject: (x) => x,
                mapValue: (x) => x,
                currentInput: false,
              );
              var wider = merged
                  .allocateMemory(region(), n(128), repeated: false)
                  .normal!;
              result = wider.applySummary(
                outer,
                stale,
                mapObject: (x) => x,
                mapValue: (x) => x,
                currentInput: true,
              );
            } else {
              result = merged.applySummary(
                thin,
                after,
                mapObject: (x) => x,
                mapValue: (x) => x,
                currentInput: true,
              );
            }
          } else if (mode == 'replaceRegionOnly') {
            final caller = merged
                .allocateMemory(region(), n(4096), repeated: false)
                .normal!;
            result = update(caller);
          }
          final actual = step(result, LoadField(flag, m), [fixedValue]).value;
          final neighbourVal = step(result, LoadField(marker, m2), [
            secondValue,
          ]).value;
          final global = step(result, LoadGlobal(g), []).value;
          final heapGlobal = step(result, LoadGlobal(ptrGlobal), []).value;
          final heap = step(result, LoadField(marker, newHeap), [
            h.value,
          ]).value;
          final keep = [
            'intact',
            'replaceRegionOnly',
            'summaryExtra',
            'retireHolder',
            'retireViaSummary',
            'arbitraryHolder',
            'writeHolder',
            'projectRetired',
            'projectLive',
            'summaryPost',
            'managedArg',
          ].contains(mode);
          print(
            '$mode data=$withNative onlyNull=${nullOnly(actual)}/${nullOnly(global)} neighbour=${neighbourVal.integers?.constant} heapRef=${heapGlobal.objects.contains(h.value.objects.single)} heap=${heap.integers?.constant}',
          );
          expect(nullOnly(actual), keep);
          expect(nullOnly(global), keep);
          expect(
            neighbourVal.integers?.constant,
            keep &&
                    ![
                      'retireHolder',
                      'retireViaSummary',
                      'arbitraryHolder',
                      'projectRetired',
                    ].contains(mode)
                ? 19
                : null,
          );
          expect(heap.integers?.constant, mode == 'summaryPost' ? 49 : null);
          if (keep) {
            expect(heapGlobal.objects, orderedEquals([h.value.objects.single]));
          }
        });
      }
    }
  }
}
