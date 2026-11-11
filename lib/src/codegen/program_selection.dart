import 'package:dartc/ir.dart';

import 'checked_casts.dart';
import 'frame_lookup.dart';
import 'function_representation.dart';
import 'global_storage.dart';
import 'heap_plan.dart';
import 'instance_storage.dart';
import 'member_calls.dart';
import 'native_invocation.dart';
import 'numeric_operations.dart';
import 'program_layout.dart';
import 'stack_traces.dart';

/// Selects function bodies and closes generated call dependencies before emission.
final class ProgramSelection(
  final ProgramLayout layouts,
  final HeapPlan heap,
  final FrameLookup frames,
  final StackTraces traces,
  final CheckedCasts casts,
  final MemberCalls members,
  final NumericOperations arithmetic,
  final GlobalStorage globals,
  final InstanceStorage instances,
) {
  final functions = <FunctionTarget, FunctionRepresentation>{};
  var capture = false, managed = false;
  Set<FunctionTarget> primitives = {};

  /// Checks a runtime closure entered with raw native pointer arguments.
  ///
  /// Caller-side boxing, allocation, exceptions and foreign calls are rejected.
  void checkNonAllocating(FunctionTarget entry) {
    for (final (i, type) in entry.parameterTypes.indexed) {
      if (FfiTypes.isPointer(type) &&
          !layouts.pointerParameters.contains(entry, i)) {
        throw UnsupportedError(
          'Runtime pointer parameter requires a managed object: ${entry.name}',
        );
      }
    }
    final pending = [(entry, <FunctionTarget>[])], checked = <FunctionTarget>{};
    while (pending.isNotEmpty) {
      final (target, path) = pending.removeLast();
      if (!checked.add(target)) continue;
      if (heap.runtime?.primitives.containsKey(target) == true) continue;
      final body = functions[target];
      if (body == null ||
          target == heap.allocate ||
          heap.allocates([target]) ||
          body.ends.values.any((end) => end is Throw || end is Invoke) ||
          body.instructions.values.any(
            (values) => values.any((value) => value is NativeInvocation),
          )) {
        throw UnsupportedError(
          'Runtime call must not allocate, throw or enter foreign code: '
          '${[...path, target].map((t) => t.name).join(' -> ')} (${target.signature.dartName})',
        );
      }
      pending.addAll(
        body.invocations.values.map((callee) => (callee, [...path, target])),
      );
    }
  }

  void include(IrFunction function) {
    if (functions.containsKey(function.target)) return;
    final body = FunctionRepresentation(
      function,
      layouts,
      casts,
      members,
      heap,
      captureTrace: traces.capture,
    );
    for (final instruction
        in body.instructions.values.expand((v) => v).whereType<Instruction>()) {
      if (body.aliases.contains(instruction)) continue;
      final box = body.boxes[instruction];
      final target = box != null
          ? heap.box(body.typeOf(box))
          : body.invocations[instruction] ??
                arithmetic.callFor(instruction) ??
                layouts.strings.callFor(instruction) ??
                globals.callFor(instruction) ??
                switch (instruction) {
                  DirectCall(:final target) => target,
                  TypeCast() ||
                  NullCheck() => casts.targetFor(instruction, layouts).target,
                  Construct(:final initializer) => heap.constructorFor(
                    initializer,
                    layouts,
                  ),
                  TypeTest() when body.tests[instruction] == .subtype =>
                    layouts.relations.test,
                  Equals(:final left, :final right)
                      when (left is TypeConstant ||
                              left is ReifyType ||
                              left is ObjectRuntimeType && left.direct) &&
                          layouts.representation(right.type) == .reference =>
                    layouts.types.equality,
                  _ => null,
                };
      if (target != null) body.invocations[instruction] = target;
    }
    functions[function.target] = body;
  }

  /// Returns source dependencies that require preparing storage and bindings again.
  Set<FunctionTarget> close({required bool persistent}) {
    var traceFunctions = <IrFunction>[];
    Iterable<IrFunction> supportFunctions() => [
      ...members.functions,
      ...layouts.closures.functions,
      ...layouts.strings.functions,
      ...arithmetic.functions,
      ...globals.functions,
      ...instances.functions,
      ...casts.functions,
      ...layouts.relations.functions,
      ...layouts.types.functions,
      if (heap.initializers.contains(layouts.pointers.initializer))
        layouts.pointers.function,
      if (capture) frames.function,
      ...traceFunctions,
    ];
    final calls = {
      for (final body in functions.values) ...body.invocations.values,
    };
    var exceptions = functions.values.any(
      (body) => body.ends.values.any((end) => end is Throw || end is Invoke),
    );
    var support = <IrFunction>[];
    while (true) {
      support = supportFunctions().toList();
      final pending = [
        for (final function in support)
          if (!functions.containsKey(function.target)) function,
      ];
      for (final function in pending) {
        include(function);
        final body = functions[function.target]!;
        calls.addAll(body.invocations.values);
        exceptions |= body.ends.values.any(
          (end) => end is Throw || end is Invoke,
        );
      }
      final needsTrace = calls.contains(traces.capture);
      final needsHeap =
          managed || persistent || heap.allocates(calls) || exceptions;
      if (pending.isEmpty && capture == needsTrace && managed == needsHeap) {
        break;
      }
      if (!capture && needsTrace) {
        traceFunctions = traces.functions(heap.invalid);
      }
      capture = needsTrace;
      managed = needsHeap;
    }
    if (managed) {
      calls.addAll([heap.allocate, heap.release]);
      if (calls.contains(heap.eventAccess)) calls.add(heap.runEvents);
    }
    heap.retain(calls);
    calls.addAll(heap.initializers);
    primitives = managed
        ? heap.primitives.intersection({...calls, heap.invalid})
        : {if (calls.contains(heap.invalid)) heap.invalid};
    final missing = calls.difference({
      ...functions.keys,
      ...primitives,
      ...members.definitions,
      if (capture) traces.capture,
      if (!globals.isEmpty) globals.address,
    });
    if (missing.isNotEmpty) return missing;
    IrProgram(
      [
        if (casts.functions.isNotEmpty) ...casts.classes,
        if (!globals.isEmpty) globals.declaration,
        ...arithmetic.classes,
        ...layouts.closures.classes,
        layouts.strings.declaration,
        ...layouts.lists.classes,
        ...layouts.maps.classes,
        ...layouts.types.classes,
        if (functions.containsKey(layouts.pointers.initializer))
          layouts.pointers.declaration,
        ...layouts.relations.classes,
        if (capture) traces.declaration,
      ],
      support.map((body) => functions[body.target]!.function),
      externals: [
        for (final target in heap.primitives) IrExternal(target),
        // Source bodies were verified already; this boundary owns generated bodies.
        for (final declaration in [
          layouts.strings.declaration,
          ...layouts.lists.classes,
          ...layouts.maps.classes,
        ])
          for (final target in {
            ...declaration.members.values,
            ...declaration.implementations.values,
            ...declaration.constructors.values,
          })
            if (!target.isAbstract)
              IrExternal(
                target,
                defaults: members.program.implementationOf(target)!.defaults,
              ),
        if (!globals.isEmpty) IrExternal(globals.address),
      ],
    );
    return {};
  }
}
