import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'dispatch.dart';
import 'function.dart';
import 'output.dart';
import 'system.dart';

/// The function that starts the program and returns its exit code.
const entrySymbol = '.start';

/// Lowers a program to a closed machine-level module.
LirModule lowerProgram(HirModule module) {
  verifyHir(module);
  // Numbers keep functions apart, and apart from system functions.
  final symbols = <HirCallable, String>{
    for (final (i, function) in module.functions.indexed)
      function: 'dart.$i.${function.name}',
  };
  final output = OutputData();
  final layout = ObjectLayout(module, symbols);
  final bodies = [
    for (final function in module.functions)
      FunctionLowering(function, symbols, output, layout).lower(),
  ];
  final start = LirBlock();
  if (output.isUsed) ignoreBrokenPipes(start);
  start.add(Call(symbols[module.main]!, signatureOf(module.main), const []));
  start.end(Return(start.add(ConstInt(0))));
  final functions = [
    ...bodies,
    ...layout.functions,
    if (output.isUsed) writeFunction(),
    LirFunction(entrySymbol, LirSignature([], .i64), [start]),
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
    data: output.data,
    tables: layout.tables,
  );
}
