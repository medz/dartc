import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

import 'arm64/backend.dart';
import 'backend.dart';
import 'code.dart';
import 'function.dart';
import 'stack_maps.dart';
import 'support.dart';
import 'x64/backend.dart';

/// What Linux starts in programs.
const linuxEntrySymbol = '.linuxEntry';

/// Translates a module to machine code, throwing [EmitUnsupported] where it
/// cannot.
///
/// [entry] is the function that a program starts with.
///
/// External functions are C functions taking and returning 64-bit words; their
/// convention agrees with the one used between functions here.
EmittedCode emitCode(
  LirModule module, {
  Target target = .macosArm64,
  String? entry,
}) {
  verifyModule(module);
  checkSupported(module);
  final externals = {for (final external in module.externals) external.name};
  final backend = switch (target.architecture) {
    .arm64 => Arm64Backend(),
    .x64 => X64Backend(Set.of(externals)),
  };
  final machine = backend.machine;
  final functions = <String, int>{textSymbol: 0};
  final maps = <StackMap>[], targets = <ThrowTarget>[];
  for (final function in module.functions) {
    functions[function.name] = machine.offset;
    final emitter = FunctionEmitter(function, machine)..emit();
    maps.addAll(emitter.stackMaps);
    targets.addAll(emitter.throwTargets);
  }
  if (functions.containsKey(callbackEntrySymbol)) {
    functions[callbacksSymbol] = machine.offset;
    backend.emitCallbacks();
  }
  for (final MapEntry(key: name, value: target) in module.exports.entries) {
    functions[_exported(name)] = machine.offset;
    backend.emitExport(target);
  }
  if (entry != null && target.system == .linux) {
    functions[linuxEntrySymbol] = machine.offset;
    backend.emitLinuxEntry(entry);
    externals.add(linuxMainSymbol);
  }
  if (externals.remove(callNativeSymbol)) {
    functions[callNativeSymbol] = machine.offset;
    backend.emitNativeCall();
  }
  return EmittedCode(
    backend.finish(),
    functions,
    backend.relocations,
    externals: externals,
    data: {
      for (final data in module.data)
        if (!data.writable) data.name: data.bytes,
      if (_uses(module, stackMapSymbol)) stackMapSymbol: encodeStackMaps(maps),
      if (_uses(module, handlerSymbol))
        handlerSymbol: encodeThrowTargets(targets),
    },
    tables: {for (final table in module.tables) table.name: table.functions},
    objects: {
      for (final data in module.data)
        if (data.writable)
          data.name: EmittedObject(data.bytes, const {}, writable: true),
      for (final object in module.statics)
        object.name: EmittedObject(
          object.bytes,
          object.references,
          writable: object.writable,
        ),
    },
    stackMaps: maps,
    throwTargets: targets,
    exports: {for (final name in module.exports.keys) name: _exported(name)},
    architecture: target.architecture,
  );
}

/// The function that C calls for what is called [name].
String _exported(String name) => '.exported.$name';

bool _uses(LirModule module, String symbol) => module.functions.any(
  (function) => function.blocks.any(
    (block) => block.instructions.any(
      (instruction) =>
          instruction is SymbolAddress && instruction.symbol == symbol,
    ),
  ),
);
