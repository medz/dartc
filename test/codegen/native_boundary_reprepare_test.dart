import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

Iterable<Instruction> _operations(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

NativeData _context(PreparedProgram prepared) => _operations(
  prepared.program.implementationOf(heapRuntime.context!) as IrFunction,
).whereType<NativeDataAddress>().single.declaration;

void main() {
  setUpAll(prepareRuntime);
  const target = Target(.linux, .arm64);
  final compiler = Compiler(target);
  for (final kind in ['export', 'process', 'import', 'callback']) {
    test('default reprepare preserves the actual $kind boundary owner', () {
      final signature = NativeSignature(
        Int64,
        List.filled(kind == 'process' ? 2 : 1, Int64),
      );
      final root = FunctionTarget(
        null,
        'root',
        .integer,
        List.filled(signature.parameters.length, ValueType.integer),
      );
      final foreign = FunctionTarget(null, 'foreign', .integer, [.integer]);
      final reference = NativeReference(
        'review',
        'foreign',
        NativeFunctionType(signature),
      );
      final body = Block(root.parameterTypes);
      final callbackBody = FunctionTarget(null, 'callbackBody', .integer, [
        .integer,
      ]);
      final callback = StaticCallbackTarget(
        callbackBody,
        FunctionType(FfiTypes.int64, [FfiTypes.int64]),
        exceptionalReturn: const Constant.integer(-1),
      );
      final value = kind == 'callback'
          ? body.emit(NativeCallbackAddress(callback))
          : kind == 'import'
          ? body.emit(DirectCall(foreign, body.parameters))
          : body.emit(
              NativeCall.symbol(
                body.emit(NativeSymbolAddress(reference)),
                root.signature,
                body.parameters,
              ),
            );
      body.finish(Return(value));
      final callbackEntry = Block(callbackBody.parameterTypes);
      callbackEntry.finish(
        Return(
          callbackEntry.emit(
            IntBinary(
              .add,
              callbackEntry.parameters.single,
              const Constant.integer(1),
            ),
          ),
        ),
      );
      final source = IrProgram(
        [],
        [
          IrFunction(root, [body]),
          if (kind == 'callback') IrFunction(callbackBody, [callbackEntry]),
        ],
        externals: [if (kind == 'import') IrExternal(foreign)],
      );
      final imports = {
        if (kind == 'import') foreign: NativeImport('foreign', signature),
      };
      final exports = {
        if (kind == 'export' || kind == 'import')
          root: NativeExport('root', signature),
      };
      PreparedProgram prepare(IrProgram program) => compiler.prepare(
        program,
        roots: [root],
        exports: exports,
        imports: imports,
        nativeSymbols: {reference: 'foreign'},
        entryPoint: kind == 'process'
            ? (function: root, symbol: 'start')
            : null,
        runtime: heapRuntime,
      );
      final first = prepare(source);
      final second = prepare(first.program);
      expect(_context(second), same(_context(first)));
      final previous = first.program.nativeBoundaries!;
      final current = second.program.nativeBoundaries!;
      expect(current.exports, previous.exports);
      expect(current.imports, previous.imports);
      expect(current.callbacks, previous.callbacks);
      expect(current.processes, previous.processes);
      expect(current.cleanup, same(previous.cleanup));
      for (final prepared in [first, second]) {
        expect(
          Arm64CodeGenerator(target).generate(prepared).sections,
          isNotEmpty,
        );
      }
    });
  }
}
