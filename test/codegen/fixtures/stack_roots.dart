import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import '../../support/runtime.dart';

ObjectModule stackRoots(Target target) {
  final uri = Uri.parse('memory:stack-roots');
  final base = ClassType(uri, 'Base');
  final type = ClassType(uri, 'Item', superclass: base);
  final field = InstanceField(base, 'value', .integer, isFinal: true);
  final functions = <IrFunction>[];
  final value = FunctionTarget(uri, 'original', type, []);
  for (final (declaration, number) in [
    (value, 41),
    (FunctionTarget(uri, 'replacement', type, []), 99),
  ]) {
    functions.add(
      IrFunction(declaration, [
        Block()
          ..finish(Return(ObjectConstant(type, {field: .integer(number)}))),
      ]),
    );
  }
  final signature = NativeSignature(Int64, [Int64]);
  final external = FunctionTarget(uri, 'native_probe', .integer, [.integer]);
  final bridge = FunctionTarget(
    uri,
    'bridge',
    .integer,
    List.filled(3, .integer),
  );
  final entry = Block(bridge.parameterTypes),
      indirect = Block(),
      direct = Block();
  final [probe, callback, mode] = entry.parameters;
  entry.finish(
    Branch(
      entry.emit(Equals(mode, const Constant.integer(0))),
      Jump(direct),
      Jump(indirect),
    ),
  );
  direct.finish(Return(direct.emit(DirectCall(external, [callback]))));
  final pointer = indirect.emit(
    PointerFromAddress(
      probe,
      FfiTypes.resolve(NativePointerType(NativeFunctionType(signature))),
    ),
  );
  indirect.finish(Return(indirect.emit(NativeCall(pointer, [callback]))));
  functions.add(IrFunction(bridge, [entry, direct, indirect]));

  final middle = FunctionTarget(uri, 'middle', .integer, [
    ...bridge.parameterTypes,
    ...List.filled(9, type),
  ]);
  final start = Block(middle.parameterTypes), call = Block(), finish = Block();
  start.finish(Jump(call));
  final called = call.emit(DirectCall(bridge, start.parameters.take(3)));
  call.finish(Jump(finish));
  Value sum = called;
  for (final reference in start.parameters.skip(3)) {
    sum = finish.emit(
      IntBinary(.add, sum, finish.emit(LoadField(field, reference))),
    );
  }
  finish.finish(Return(sum));
  functions.add(IrFunction(middle, [start, call, finish]));

  final run = FunctionTarget(
    uri,
    'roots_run',
    .integer,
    List.filled(4, .integer),
  );
  final body = Block(run.parameterTypes), valid = Block(), invalid = Block();
  final [address, visit, bits, route] = body.parameters;
  final original = body.emit(DirectCall(value, []));
  final alias = body.emit(TypeView(original, base));
  body.emit(
    TypeView(original, .object),
  ); // A dead alias must not become a root.
  final cell = body.emit(NewCell(CellType(type), original));
  final nullCell = body.emit(
    NewCell(CellType(type.nullable), const Constant.nullValue()),
  );
  final raw = body.emit(
    PointerFromAddress(
      bits,
      FfiTypes.resolve(NativePointerType(NativeScalarType(Uint8))),
    ),
  );
  sum = body.emit(
    DirectCall(middle, [address, visit, route, ...List.filled(9, original)]),
  );
  for (final reference in [original, alias, body.emit(ReadCell(cell))]) {
    sum = body.emit(
      IntBinary(.add, sum, body.emit(LoadField(field, reference))),
    );
  }
  sum = body.emit(IntBinary(.add, sum, bits));
  sum = body.emit(IntBinary(.add, sum, body.emit(PointerAddress(raw))));
  body.finish(
    Branch(
      body.emit(
        Equals(body.emit(ReadCell(nullCell)), const Constant.nullValue()),
      ),
      Jump(valid),
      Jump(invalid),
    ),
  );
  valid.finish(Return(sum));
  invalid.finish(Return(const Constant.integer(-1)));
  functions.add(IrFunction(run, [body, valid, invalid]));

  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  final module = generator.generate(
    IrProgram(
      [
        IrClass(base, [field]),
        IrClass(type, []),
      ],
      functions,
      externals: [IrExternal(external)],
    ),
    runtime: heapRuntime,
    definitions: [...functions.map((f) => f.target), external],
    exports: {
      run: NativeExport(
        'roots_run',
        NativeSignature(Int64, List.filled(4, Int64)),
      ),
    },
    imports: {external: NativeImport('roots_probe', signature)},
  );
  final aliases = {
    for (final (i, function) in module.symbols.take(2).indexed)
      module.relocations
          .whereType<InstructionRelocation>()
          .where(
            (r) =>
                r.section == function.section &&
                r.offset >= function.offset &&
                r.offset < function.offset + function.size!,
          )
          .map((r) => r.symbol)
          .toSet()
          .single: i == 0
          ? 'roots_original'
          : 'roots_replacement',
  };
  return ObjectModule(
    target,
    module.sections,
    [
      for (final (i, symbol) in module.symbols.indexed)
        if (symbol.name == '.dartc.roots')
          Symbol(
            target.nativeSymbol('roots_table'),
            symbol.section,
            symbol.offset,
            symbol.size,
            kind: .data,
            exported: true,
          )
        else if (aliases[i] case final name?)
          Symbol(
            target.nativeSymbol(name),
            symbol.section,
            symbol.offset,
            symbol.size,
            kind: .data,
            exported: true,
          )
        else
          symbol,
    ],
    imports: module.imports,
    relocations: module.relocations,
  );
}

ObjectModule rootsProbe(Target target) {
  final List<int> bytes;
  if (target.architecture == .arm64) {
    final abi = Arm64Abi(target), code = arm.Assembler();
    final frame = abi.frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: 0,
    );
    abi.emitPrologue(code, frame);
    code
      ..move(.x2, .x0)
      ..load(.x0, .sp, frame.returnAddressOffset)
      ..addImmediate(.x1, .sp, frame.incomingStackOffset)
      ..callRegister(.x2);
    abi.emitEpilogue(code, frame);
    bytes = code.finish();
  } else {
    final abi = X64Abi(target), code = x64.Assembler();
    final frame = abi.frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: 0,
    );
    abi.emitPrologue(code, frame);
    code
      ..move(.rax, .rdi)
      ..load(.rdi, .rsp, frame.returnAddressOffset)
      ..move(.rsi, .rsp)
      ..addImmediate(.rsi, frame.incomingStackOffset)
      ..callRegister(.rax);
    abi.emitEpilogue(code, frame);
    bytes = code.finish();
  }
  return ObjectModule(
    target,
    [Section.code(bytes)],
    [
      Symbol(
        target.nativeSymbol('roots_probe'),
        0,
        0,
        bytes.length,
        exported: true,
      ),
    ],
  );
}
