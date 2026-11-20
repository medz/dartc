import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final target = Target.host(), word = NativeScalarType(Int64);
  for (final mode in [
    'local',
    'reachable',
    'borrow',
    'release64',
    'releasePage',
    'published',
  ]) {
    test('module neighbor value across actually supplied $mode authority', () {
      final t = ClassType(null, 'ModuleState'),
          field = InstanceField(t, 'writable', .integer);
      final m = ModuleObject(
        t,
        initialFields: {field: const Constant.integer(7)},
      );
      final ext = FunctionTarget(null, 'foreign', .voidType, [
            .integer,
            .integer,
          ]),
          root = FunctionTarget(null, 'root', .integer, []),
          reader = FunctionTarget(null, 'reader', .integer, []);
      final data = NativeData(List.filled(64, 1), alignment: 8);
      final b = Block(), a = b.emit(NativeDataAddress(data));
      if (mode == 'reachable') {
        final v = b.emit(ReferenceAddress(b.emit(ModuleObjectReference(m))));
        b.emit(StoreNative(a, word, v));
      }
      final release = mode.startsWith('release');
      if (mode != 'local' && mode != 'published') {
        b.emit(
          DirectCall(ext, [
            a,
            Constant.integer(mode == 'releasePage' ? 16384 : 64),
          ]),
        );
      }
      final seen = b.emit(LoadField(field, b.emit(ModuleObjectReference(m))));
      b.finish(Return(mode == 'published' ? a : seen));
      final rb = Block();
      rb.finish(
        Return(rb.emit(LoadField(field, rb.emit(ModuleObjectReference(m))))),
      );
      final p = IrProgram(
        [
          IrClass(t, [field]),
        ],
        [
          IrFunction(root, [b]),
          IrFunction(reader, [rb]),
        ],
        externals: [
          IrExternal(
            ext,
            effects: {Effect.writesStorage},
            capturesArguments: false,
            memory: release
                ? const ExternalMemory.release(0, 1)
                : const ExternalMemory.arbitrary(),
          ),
        ],
      );
      final facts = ProgramFlow(
        p,
        [if (mode != 'published') (target: root, arguments: [])],
        openEntries: mode == 'published' ? [root, reader] : [],
        memoryLayout: ProgramLayout(
          p.classes,
          nativeLayout: NativeLayout(target),
        ),
      ).facts;
      final value = facts.returnedBy(mode == 'published' ? reader : root);
      print(
        'mode=$mode field scalar=${value.integers?.constant} range=${value.integers?.lower}..${value.integers?.upper} unknown=${value.unknownTypes}',
      );
      expect(
        value.integers?.constant,
        (mode == 'reachable' || mode == 'releasePage' || mode == 'published')
            ? isNull
            : 7,
      );
    });
  }
  for (final giveCallable in [false, true]) {
    test(
      'module data custody preserves private callback admission (explicit=$giveCallable)',
      () {
        final callback = FunctionTarget(null, 'hidden', .integer, []);
        final target = FunctionTarget(null, 'giveData', .integer, []);
        final outside = FunctionTarget(
          null,
          'giveCallable',
          callback.signature,
          [],
        );
        final hideType = ClassType(null, 'Holder'),
            slot = InstanceField(hideType, 'private', callback.signature);
        final holder = ModuleObject(
          hideType,
          initialFields: {slot: FunctionConstant(callback)},
        );
        final address = NativeData(List.filled(64, 1), alignment: 8);
        final b = Block(), c = Block(), pub = Block();
        b.emit(ModuleObjectReference(holder));
        b.finish(Return(b.emit(NativeDataAddress(address))));
        c.finish(const Return(Constant.integer(91)));
        pub.finish(
          Return(
            pub.emit(LoadField(slot, pub.emit(ModuleObjectReference(holder)))),
          ),
        );
        final p = IrProgram(
          [
            IrClass(hideType, [slot]),
          ],
          [
            IrFunction(target, [b]),
            IrFunction(callback, [c]),
            IrFunction(outside, [pub]),
          ],
        );
        final f = ProgramFlow(
          p,
          [],
          openEntries: [target, if (giveCallable) outside],
          memoryLayout: ProgramLayout(
            p.classes,
            nativeLayout: NativeLayout(Target.host()),
          ),
        ).facts;
        print(
          'explicit=$giveCallable hidden callback contexts=${f.activationsOf(callback).length}',
        );
        expect(f.activationsOf(callback).isNotEmpty, giveCallable);
      },
    );
  }
}
