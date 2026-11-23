import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'dispatch.dart';
import 'function.dart';
import 'machine.dart';
import 'output.dart';
import 'runtime.dart';
import 'statics.dart';
import 'system.dart';

/// The function that starts the program and returns its exit code.
const entrySymbol = '.start';

/// The exit code of a program that throws what nothing catches.
const _uncaughtCode = 255;

/// Lowers a program to a closed machine-level module.
///
/// If [collectsAlways], its collector runs before every allocation.
LirModule lowerProgram(HirModule module, {bool collectsAlways = false}) {
  verifyHir(module);
  // Numbers keep functions apart, and apart from system functions.
  final symbols = <HirCallable, String>{
    for (final (i, function) in module.functions.indexed)
      function: 'dart.$i.${function.name}',
  };
  final output = OutputData();
  final layout = ObjectLayout(module, symbols);
  final statics = StaticData(module, layout);
  final machine = MachineLowering(
    statics,
    output,
    collectsAlways: collectsAlways,
  );
  final bodies = [
    for (final function in module.functions)
      FunctionLowering(
        function,
        symbols,
        output,
        layout,
        statics,
        machine,
      ).lower(),
  ];
  final functions = [
    ...bodies,
    ...layout.functions,
    ...runtimeFunctions(module, symbols),
    if (output.isUsed) writeFunction(),
    _startFunction(module, symbols, output),
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
    ],
    data: [
      ...output.data,
      ...statics.tables,
      if (module.allocate != null) statics.classTable(),
    ],
    tables: layout.tables,
    statics: [
      ...statics.objects,
      if (module.stackOverflow != null) stackLimit(),
    ],
  );
}

/// Starts the program and reports what nothing catches.
LirFunction _startFunction(
  HirModule module,
  Map<HirCallable, String> symbols,
  OutputData output,
) {
  final start = LirBlock(), done = LirBlock();
  final blocks = [start, done];
  if (output.isUsed) ignoreBrokenPipes(start);
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
  return LirFunction(entrySymbol, LirSignature([], .i64), blocks);
}
