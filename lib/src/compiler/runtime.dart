import 'dart:ffi';

import 'package:dartc/frontend.dart';

import 'package:dartc/runtime/contracts.dart';

import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';

/// Binds the bundled runtime's external memory operations to trusted IR.
HeapRuntime bindRuntime(LoweringResult lowered) {
  var program = lowered.program;
  final annotations = lowered.runtime;
  final bodies = <IrFunction>[];
  final primitives = <FunctionTarget, MemoryPrimitive>{};
  for (final external in program.externals) {
    final target = external.target;
    final operation = annotations.primitives[target];
    if (operation == null) continue;
    final block = Block(target.parameterTypes);
    final args = block.parameters;
    final Value? value;
    switch (operation) {
      case .map:
        primitives[target] = .map;
        continue;
      case .unmap:
        primitives[target] = .unmap;
        continue;
      case .fail:
        primitives[target] = .fail;
        continue;
      case .context:
        primitives[target] = .context;
        continue;
      case .writeBytes:
        primitives[target] = .writeBytes;
        continue;
      case .clock:
        primitives[target] = .clock;
        continue;
      case .sleep:
        primitives[target] = .sleep;
        continue;
      case .read:
        value = block.emit(LoadNative(args.single, .new(Int64)));
      case .readByte:
        value = block.emit(LoadNative(args.single, .new(Uint8)));
      case .write:
        block.emit(StoreNative(args.first, .new(Int64), args.last));
        value = null;
      case .writeByte:
        block.emit(StoreNative(args.first, .new(Uint8), args.last));
        value = null;
      case .addressOf:
        value = block.emit(ReferenceAddress(args.single));
      case .objectAt:
        value = block.emit(
          ReferenceFromAddress(args.single, target.returnType),
        );
    }
    block.finish(Return(value));
    bodies.add(IrFunction(target, [block]));
  }
  final supplied = bodies.map((body) => body.target).toSet();
  program = IrProgram(
    program.classes,
    [...program.functions, ...bodies],
    globals: program.globals,
    externals: program.externals.where(
      (external) => !supplied.contains(external.target),
    ),
  );
  final allocate = annotations.entries[RuntimeRole.allocate],
      release = annotations.entries[RuntimeRole.release],
      runEvents = annotations.entries[RuntimeRole.runEvents],
      eventAccess = annotations.entries[RuntimeRole.events],
      copyBytes = annotations.entries[RuntimeRole.copyBytes];
  if (allocate == null ||
      release == null ||
      runEvents == null ||
      eventAccess == null ||
      copyBytes == null) {
    throw ArgumentError('Missing runtime entry contract.');
  }
  final required = program.reachableFrom([allocate, release, runEvents]);
  final libraries = {
    for (final function in program.functions)
      if (required.contains(function.target)) function.target.library,
    for (final primitive in annotations.primitives.keys) primitive.library,
  };
  final functions = program.functions
      .where((f) => libraries.contains(f.target.library))
      .toList();
  final externals = program.externals
      .where((f) => libraries.contains(f.target.library))
      .toList();
  final classes = <ClassType>{};
  void include(ClassType type) {
    if (!classes.add(type.declaration)) return;
    if (type.superclass case final parent?) include(parent);
    for (final interface in type.interfaces) {
      include(interface);
    }
  }

  for (final body in [...functions, ...externals]) {
    body.referencedClasses.forEach(include);
    if (body.target.owner case final owner?) include(owner);
  }
  final globals = {for (final body in functions) ...body.globals};
  final source = IrProgram(
    program.classes.where(
      (c) =>
          classes.contains(c.type) &&
          (libraries.contains(c.type.library) ||
              c.type == CoreTypes.enumeration),
    ),
    functions,
    globals: globals,
    externals: externals,
  );
  return HeapRuntime(
    source,
    allocate: allocate,
    release: release,
    runEvents: runEvents,
    eventAccess: eventAccess,
    copyBytes: copyBytes,
    primitives: primitives,
    nonAllocating: annotations.nonAllocating,
  );
}
