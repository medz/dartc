import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

import 'callbacks.dart';
import 'dispatch.dart';
import 'exports.dart';
import 'function.dart';
import 'machine.dart';
import 'output.dart';
import 'runtime.dart';
import 'statics.dart';
import 'system.dart';

/// The function that starts the program and returns its exit code.
///
/// It may take the number of arguments and their address.
const entrySymbol = '.start';

/// The exit code of a program that throws what nothing catches.
const _uncaughtCode = 255;

/// Lowers a program, or a library if it exports functions, to a closed
/// machine-level module.
///
/// If [collectsAlways], its collector runs before every allocation.
LirModule lowerProgram(HirModule module, {bool collectsAlways = false}) {
  verifyHir(module);
  // Numbers keep functions apart, and apart from system functions.
  final symbols = <HirCallable, String>{
    for (final (i, function) in module.functions.indexed)
      function: 'dart.$i.${function.name}',
  };
  final layout = ObjectLayout(module, symbols);
  final statics = StaticData(module, layout);
  final machine = MachineLowering(statics, collectsAlways: collectsAlways);
  final bodies = [
    for (final function in module.functions)
      FunctionLowering(function, symbols, layout, statics, machine).lower(),
  ];
  final exports = module.exports.isEmpty ? null : _exports(module, symbols);
  final needsThread = module.callback != null || exports != null;
  final functions = [
    ...bodies,
    ...layout.functions,
    ...runtimeFunctions(module, symbols),
    if (machine.writesOutput) writeFunction(),
    if (module.callback case final callback?)
      ...callbackFunctions(symbols[callback]!, signatureOf(callback)),
    if (exports == null)
      _startFunction(module, symbols, machine)
    else
      ...exports.functions,
  ];
  final called = {
    for (final function in functions)
      for (final block in function.blocks)
        for (final call in block.instructions.whereType<Call>()) call.symbol,
  };
  return LirModule(
    functions: functions,
    externals: [
      for (final MapEntry(key: name, value: signature)
          in systemFunctions.entries)
        if (called.contains(name)) LirExternal(name, signature),
      for (final name in machine.nativeFunctions)
        if (!called.contains(name)) LirExternal(name, LirSignature([])),
      if (machine.callsNative)
        LirExternal(callNativeSymbol, callNativeSignature),
    ],
    data: [
      ...statics.tables,
      if (machine.usesBuffer)
        LirData(bufferSymbol, List.filled(bufferBytes, 0), writable: true),
      if (needsThread) mainThread(),
      if (exports != null) ...exportData(),
      if (module.callback != null) ...[...callbackData(), callbackMessage],
      if (machine.keepsNativeFrame)
        LirData(nativeFrameSymbol, List.filled(8, 0), writable: true),
      if (machine.callsNative)
        LirData(
          callBlockSymbol,
          List.filled(CallBlock.size, 0),
          writable: true,
        ),
      if (machine.usesArguments)
        LirData(
          argumentsSymbol,
          List.filled(argumentsBytes, 0),
          writable: true,
        ),
      if (module.allocate != null) statics.classTable(),
    ],
    tables: layout.tables,
    statics: [
      ...statics.objects,
      if (module.stackOverflow != null) stackLimit(),
    ],
    exports: exports?.names ?? const {},
  );
}

({List<LirFunction> functions, Map<String, String> names}) _exports(
  HirModule module,
  Map<HirCallable, String> symbols,
) {
  ({String symbol, LirSignature signature})? find(HirFunction? function) =>
      function == null
      ? null
      : (symbol: symbols[function]!, signature: signatureOf(function));
  return exportFunctions(
    {
      for (final MapEntry(key: name, value: function) in module.exports.entries)
        name: find(function)!,
    },
    uncaught: find(module.uncaught),
    eventLoop: find(module.eventLoop),
    checksStack: module.stackOverflow != null,
  );
}

/// Starts the program and reports what nothing catches.
LirFunction _startFunction(
  HirModule module,
  Map<HirCallable, String> symbols,
  MachineLowering machine,
) {
  final start = LirBlock([
    if (machine.usesArguments) ...const [LirType.i64, LirType.ptr],
  ]);
  final done = LirBlock();
  final blocks = [start, done];
  if (machine.usesArguments) {
    final [count, address] = start.parameters;
    final place = start.add(SymbolAddress(argumentsSymbol));
    start
      ..add(Store(.i64, place, count))
      ..add(Store(.ptr, place, address, offset: 8));
  }
  if (module.callback != null) setMainThread(start);
  if (machine.writesOutput) ignoreBrokenPipes(start);
  if (module.stackOverflow != null) setStackLimit(start);
  final main = Call(symbols[module.main]!, signatureOf(module.main), const []);
  if (module.uncaught case final uncaught?) {
    final failed = LirBlock([.ref, .ref]);
    start.end(Invoke(main, LirEdge(done), LirEdge(failed)));
    failed
      ..add(
        Call(symbols[uncaught]!, signatureOf(uncaught), [
          failed.parameters.first,
        ]),
      )
      ..add(callSystem('exit', [failed.add(ConstInt(_uncaughtCode))]))
      ..end(Unreachable());
    blocks.add(failed);
  } else {
    start
      ..add(main)
      ..end(Jump(LirEdge(done)));
  }
  done.end(Return(done.add(ConstInt(0))));
  final signature = LirSignature(start.parameters.map((p) => p.type), .i64);
  return LirFunction(entrySymbol, signature, blocks);
}
