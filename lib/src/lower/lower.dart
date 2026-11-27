import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

import 'callbacks.dart';
import 'dispatch.dart';
import 'exports.dart';
import 'function.dart';
import 'isolates.dart';
import 'machine.dart';
import 'output.dart';
import 'runtime.dart';
import 'statics.dart';
import 'system.dart';
import 'system_calls.dart';

/// The function that starts the program and returns its exit code.
///
/// It may take the number of arguments and their address.
const entrySymbol = '.start';

/// The symbol of each function of [module]. Allocations call that of the
/// runtime directly.
Map<HirFunction, String> functionSymbols(HirModule module) => {
  // Numbers keep functions apart, and apart from system functions.
  for (final (i, function) in module.functions.indexed)
    function: function == module.allocate
        ? allocateSymbol
        : 'dart.$i.${function.name}',
};

/// The exit code of a program that throws what nothing catches.
const _uncaughtCode = 255;

/// Lowers a program, or a library if it exports functions, to a closed
/// machine-level module for [system].
///
/// If [collectsAlways], its collector runs before every allocation.
LirModule lowerProgram(
  HirModule module, {
  bool collectsAlways = false,
  OperatingSystem system = .macos,
}) {
  verifyHir(module);
  final Map<HirCallable, String> symbols = functionSymbols(module);
  final layout = ObjectLayout(module, symbols);
  final statics = StaticData(module, layout);
  final calls = SystemCalls.of(system);
  final machine = MachineLowering(
    statics,
    calls,
    collectsAlways: collectsAlways,
  );
  final bodies = [
    for (final function in module.functions)
      FunctionLowering(function, symbols, layout, statics, machine).lower(),
  ];
  final exports = module.exports.isEmpty
      ? null
      : _exports(module, symbols, calls);
  final functions = [
    ...bodies,
    ...layout.functions,
    ...runtimeFunctions(module, symbols),
    if (machine.writesOutput) writeFunction(calls),
    if (module.callback case final callback?)
      ...callbackFunctions(symbols[callback]!, signatureOf(callback), calls),
    if (module.spawned case final spawned?)
      isolateEntry(
        symbols[spawned]!,
        signatureOf(spawned),
        checksStack: module.stackOverflow != null,
        system: calls,
      ),
    if (exports == null)
      _startFunction(module, symbols, machine, calls)
    else
      ...exports.functions,
  ];
  final data = _data(module, statics, machine, calls, exports != null);
  final objects = [
    ...statics.objects,
    if (module.stackOverflow != null) stackLimit(),
  ];
  if (module.spawned != null) {
    final (:template, :function) = isolateTemplate(data, objects);
    functions.add(function);
    objects.add(template);
  }
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
    data: data,
    tables: layout.tables,
    statics: objects,
    exports: exports?.names ?? const {},
  );
}

/// The data that the program needs, once its functions are lowered.
List<LirData> _data(
  HirModule module,
  StaticData statics,
  MachineLowering machine,
  SystemCalls calls,
  bool isLibrary,
) => [
  ...statics.tables,
  if (machine.usesBuffer)
    LirData(
      bufferSymbol,
      List.filled(bufferBytes, 0),
      writable: true,
      isolated: true,
    ),
  if (module.callback != null || isLibrary) mainThread(),
  if (isLibrary) ...exportData(),
  ...calls.data,
  if (module.callback != null) ...[...callbackData(calls), callbackMessage],
  if (machine.keepsNativeFrame)
    LirData(
      nativeFrameSymbol,
      List.filled(8, 0),
      writable: true,
      isolated: true,
    ),
  if (machine.callsNative)
    LirData(
      callBlockSymbol,
      List.filled(CallBlock.size, 0),
      writable: true,
      isolated: true,
    ),
  if (machine.usesArguments)
    LirData(argumentsSymbol, List.filled(argumentsBytes, 0), writable: true),
  if (module.allocate != null) statics.classTable(),
];

({List<LirFunction> functions, Map<String, String> names}) _exports(
  HirModule module,
  Map<HirCallable, String> symbols,
  SystemCalls system,
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
    system: system,
  );
}

/// Starts the program and reports what nothing catches.
LirFunction _startFunction(
  HirModule module,
  Map<HirCallable, String> symbols,
  MachineLowering machine,
  SystemCalls system,
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
  if (module.stackOverflow != null) setStackLimit(start, system);
  final main = Call(symbols[module.main]!, signatureOf(module.main), const []);
  if (module.uncaught case final uncaught?) {
    final failed = LirBlock([.ref, .ref]);
    start.end(Invoke(main, LirEdge(done), LirEdge(failed)));
    failed
      ..add(Call(symbols[uncaught]!, signatureOf(uncaught), failed.parameters))
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
  return LirFunction(entrySymbol, signature, blocks, isEntered: true);
}
