import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:global-owner-scope'),
      native = NativeLayout(Target.host());
  for (final lateSlot in [false, true]) {
    for (final mode in [
      'private',
      'borrow',
      'reachable',
      'release64',
      'releasePage',
      'published',
    ]) {
      test('global isLate=$lateSlot after $mode', () {
        final init = FunctionTarget(uri, 'init', .integer, []);
        final g = GlobalVariable(
          uri,
          'value',
          lateSlot ? ValueType.integer : ValueType.integer.nullable,
          isLate: lateSlot,
          initializer: lateSlot ? init : null,
        );
        final a = NativeData(List.filled(64, 1), alignment: 8);
        final read = FunctionTarget(uri, 'read', g.type, []),
            handoff = FunctionTarget(uri, 'publish', .integer, []),
            touch = FunctionTarget(uri, 'helper', .voidType, [.integer]),
            ext = FunctionTarget(uri, 'host', .voidType, [.integer, .integer]);
        final b = Block(), h = Block();
        if (mode != 'published') {
          b.emit(StoreGlobal(g, const Constant.integer(31)));
          b.emit(DirectCall(touch, [b.emit(NativeDataAddress(a))]));
        }
        b.finish(Return(b.emit(LoadGlobal(g))));
        h.finish(Return(h.emit(NativeDataAddress(a))));
        final p = IrProgram(
          [],
          [
            IrFunction(read, [b]),
            IrFunction(handoff, [h]),
            IrFunction(touch, [
              Block(touch.parameterTypes)..finish(const Return()),
            ]),
            if (lateSlot)
              IrFunction(init, [
                Block()..finish(const Return(Constant.integer(37))),
              ]),
          ],
          globals: [g],
          externals: [
            IrExternal(
              ext,
              effects: {Effect.writesStorage},
              capturesArguments: false,
              memory: mode.startsWith('release')
                  ? const ExternalMemory.release(0, 1)
                  : const ExternalMemory.arbitrary(),
            ),
          ],
        );
        final lower = GlobalLowering().lower(
          p,
          p.functions.map((f) => f.target),
        );
        final holder = lower.functions
            .expand((f) => f.moduleObjects)
            .toSet()
            .single;
        final body = Block(touch.parameterTypes);
        if (mode == 'reachable') {
          final address = body.emit(
            ReferenceAddress(body.emit(ModuleObjectReference(holder))),
          );
          body.emit(
            StoreNative(
              body.parameters.single,
              NativeScalarType(Int64),
              address,
            ),
          );
        }
        if (mode != 'private' && mode != 'published') {
          body.emit(
            DirectCall(ext, [
              body.parameters.single,
              Constant.integer(mode == 'releasePage' ? 16384 : 64),
            ]),
          );
        }
        body.finish(const Return());
        final lowered = IrProgram(
          lower.classes,
          [
            ...lower.functions.where((f) => f.target != touch),
            IrFunction(touch, [body]),
          ],
          externals: lower.externals,
          globals: lower.globals,
        );
        final facts = ProgramFlow(
          lowered,
          [if (mode != 'published') (target: read, arguments: [])],
          openEntries: mode == 'published' ? [handoff, read] : [],
          memoryLayout: ProgramLayout(lowered.classes, nativeLayout: native),
        ).facts;
        final value = facts.returnedBy(read);
        final slot = value.constant;
        final fields = lowered.classes
            .singleWhere((c) => c.type == holder.type)
            .fields;
        print(
          'late=$lateSlot mode=$mode fields=${fields.map((f) => f.name)} constant=${slot is ScalarConstant ? slot.value : "-"} unknownTypes=${value.unknownTypes.map((t) => t.dartName)}',
        );
        if (mode == 'published') {
          expect(slot, isNull);
          expect(value.unknownTypes, isNotEmpty);
        } else if (mode == 'reachable' || mode == 'releasePage') {
          expect(slot, isNull);
        } else {
          expect(value.integers?.constant, 31);
        }
      });
    }
  }
}
