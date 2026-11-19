import 'dart:ffi' show Int64, Void;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  for (final raw in [false, true]) {
    test(
      'native callback updates its global while private storage is preserved (raw=$raw)',
      () {
        final uri = Uri.parse('memory:native-boundary');
        final secret = GlobalVariable(uri, 'secret', .integer, isLate: true);
        final seen = GlobalVariable(uri, 'seen', .integer, isLate: true);
        final callbackTarget = FunctionTarget(uri, 'record', .integer, []);
        final callbackBlock = Block();
        callbackBlock.emit(StoreGlobal(seen, const Constant.integer(23)));
        callbackBlock.finish(const Return(Constant.integer(0)));
        final callback = StaticCallbackTarget(
          callbackTarget,
          FunctionType(FfiTypes.int64, []),
          exceptionalReturn: const Constant.integer(0),
        );
        final pointerType = NativePointerType(
          NativeFunctionType(NativeSignature(Int64, [])),
        );
        final signature = NativeSignature.types(NativeTypeRef.of(Void), [
          pointerType,
        ]);
        final root = FunctionTarget(uri, 'root', .integer, []);
        final entry = Block();
        entry.emit(StoreGlobal(secret, const Constant.integer(7)));
        entry.emit(StoreGlobal(seen, const Constant.integer(1)));
        final host = entry.emit(
          NativeSymbolAddress(
            NativeReference('fixture', 'invoke', NativeFunctionType(signature)),
          ),
        );
        final address = entry.emit(NativeCallbackAddress(callback));
        if (raw) {
          entry.emit(RawNativeCall(host, signature, [address]));
        } else {
          final type = FfiTypes.resolve(pointerType);
          entry.emit(
            NativeCall.symbol(host, FunctionType(.voidType, [type]), [
              entry.emit(PointerFromAddress(address, type)),
            ]),
          );
        }
        final callbackEffect = entry.emit(LoadGlobal(seen));
        final preserved = entry.emit(LoadGlobal(secret));
        entry.finish(Return(preserved));
        final facts = ProgramFlow(
          IrProgram(
            [],
            [
              IrFunction(callbackTarget, [callbackBlock]),
              IrFunction(root, [entry]),
            ],
            globals: [secret, seen],
          ),
          [(target: root, arguments: <FlowValue>[])],
        ).facts;
        final values = facts.valueOf(callbackEffect).integers!;
        expect((values.lower, values.upper), (1, 23));
        expect(facts.returnedBy(root).constant, const Constant.integer(7));
      },
    );
  }
}
