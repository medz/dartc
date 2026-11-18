import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';

import 'checked_casts.dart';
import 'function_representation.dart';
import 'selected_function.dart';
import 'heap_plan.dart';
import 'instance_storage.dart';
import 'member_calls.dart';
import 'native_invocation.dart';
import 'indirect_invocation.dart';
import 'program_layout.dart';
import 'program_normalization.dart';
import 'storage_access.dart';

/// Selects function bodies and closes generated call dependencies before emission.
final class ProgramSelection(
  final ProgramLayout layouts,
  final HeapPlan heap,
  final CheckedCasts casts,
  final MemberCalls members,
  final InstanceStorage instances, {
  final Map<FunctionTarget, NativeImport> imports = const {},
  final Map<NativeCallbackTarget, FunctionTarget> callbacks = const {},
}) {
  final functions = <FunctionTarget, SelectedFunction>{};
  late final _normalization = ProgramNormalization(
    members.program,
    runtime: heap.runtime,
  );
  var capture = false, managed = false, failures = false;
  Set<FunctionTarget> primitives = {};

  /// Source entries reached through generated code rather than checked call sites.
  final implicitCalls = <FunctionTarget>{};

  /// Selected call sites whose execution is absent from their source contract.
  final unobservedCalls =
      <Instruction, ({FunctionTarget caller, FunctionTarget target})>{};

  /// Checks the selected operations and transitive call effects of a closure.
  void checkNonAllocating(FunctionTarget entry) {
    const forbidden = {Effect.allocates, Effect.mayThrow, Effect.callsUserCode};
    bool invalid(Set<Effect> effects) => effects.any(forbidden.contains);
    for (final (i, type) in entry.parameterTypes.indexed) {
      if (FfiTypes.isPointer(type) &&
          !layouts.pointerRepresentation.contains(entry, i)) {
        throw UnsupportedError(
          'Critical pointer parameter requires a managed object: ${entry.name}',
        );
      }
    }
    final pending = [(entry, <FunctionTarget>[])], checked = <FunctionTarget>{};
    while (pending.isNotEmpty) {
      final (target, path) = pending.removeLast();
      if (!checked.add(target)) continue;
      Never reject([Value? operation]) => throw UnsupportedError(
        'Critical call must not allocate, throw or enter foreign code with unknown effects: '
        '${[...path, target].map((t) => t.name).join(' -> ')} (${target.signature.dartName})'
        '${operation == null ? '' : ': ${operation.runtimeType}'}',
      );
      if (heap.runtime?.primitives[target] case final primitive?) {
        if (invalid(primitive.effects)) reject();
        continue;
      }
      if (imports[target] case final native?) {
        if (!native.isNonAllocating) reject();
        continue;
      }
      final body = functions[target];
      if (body == null ||
          target == heap.allocate ||
          heap.allocates([target]) ||
          body.ends.values.any((end) => end is Throw)) {
        reject();
      }
      for (final operation in body.instructions.values.expand(
        (values) => values,
      )) {
        if (body.aliases.contains(operation) ||
            body.invocations.containsKey(operation)) {
          continue;
        }
        if (operation is NativeInvocation) {
          if (operation.address case NativeSymbolAddress(:final reference)
              when heap.runtime?.nonAllocatingNatives.contains(reference) ==
                  true) {
            continue;
          }
          reject();
        }
        if (operation is TypeTest &&
            switch (body.tests[operation]) {
              .constantTrue || .constantFalse || .isNull || .isNotNull => true,
              _ => false,
            }) {
          continue;
        }
        if (operation is Instruction && invalid(operation.effects)) {
          reject(operation);
        }
      }
      pending.addAll(body.callees.map((callee) => (callee, [...path, target])));
    }
  }

  void include(IrFunction function) {
    if (functions.containsKey(function.target)) return;
    final body = FunctionRepresentation(
      identical(members.program.implementationOf(function.target), function)
          ? function
          : _normalization.normalizeBody(function),
      layouts,
      casts,
      members,
      heap,
    );
    _bind(body);
    functions[function.target] = body;
  }

  void _bind(SelectedFunction body) {
    body.prune();
    final owner = body.target.owner;
    final context = heap.runtime?.stackContext;
    if (body.target.awaiterCapture != null ||
        body.target.kind.hasReceiver &&
            owner != null &&
            context != null &&
            owner.asInstanceOf(context) != null) {
      body.stackContext = body.entryParameters.first;
    }

    for (final instruction
        in body.instructions.values.expand((v) => v).whereType<Instruction>()) {
      if (body.aliases.contains(instruction)) continue;
      if (instruction
          case IntBinary(
                checked: true,
                operator: IntOperator(mayThrow: true),
              ) ||
              NumericToInt(
                checked: true,
                operand: Value(type: != ValueType.integer),
              ) ||
              NumericRoundToDouble(
                operand: Value(type: != ValueType.integer),
              )) {
        throw StateError(
          'Numeric checks must be normalized before target preparation.',
        );
      }
      final target = body.invocations[instruction] ??
                layouts.strings.callFor(instruction) ??
                switch (instruction) {
                  NativeCallbackAddress(:final target) => callbacks[target],
                  DirectCall(:final target) ||
                  InitializeObject(initializer: final target) => target,
                  TypeCast() ||
                  NullCheck() => casts.targetFor(instruction).target,
                  Construct(:final initializer) => heap.constructorFor(
                    initializer,
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
  }

  /// Returns source dependencies that require preparing storage and bindings again.
  Set<FunctionTarget> close({
    required bool persistent,
    required Set<FunctionTarget> roots,
  }) {
    final calls = {for (final body in functions.values) ...body.callees};
    Iterable<IrFunction> supportFunctions() => [
      ..._normalization.supportFunctions,
      ...heap.functions(calls),
      ...members.functions,
      ...layouts.closures.functions,
      ...layouts.records.functions,
      ...instances.functions,
      ...casts.functions,
      ...layouts.relations.functions,
      ...layouts.types.functions,
      if (heap.initializersFor(calls).contains(layouts.pointers.initializer))
        layouts.pointers.function,
    ];
    var support = <IrFunction>[];
    while (true) {
      calls.addAll(heap.initializersFor(calls.toList()));
      support = supportFunctions().toList();
      final pending = [
        for (final function in support)
          if (calls.contains(function.target) &&
              !functions.containsKey(function.target))
            function,
      ];
      for (final function in pending) {
        include(function);
        final body = functions[function.target]!;
        calls.addAll(body.callees);
      }
      if (pending.isEmpty) break;
    }
    failures = functions.values.any(
      (body) => body.ends.values.any((end) => end is Throw || end is Invoke),
    );
    capture =
        calls.contains(heap.runtime?.captureTrace) ||
        calls.contains(heap.runtime?.captureStackTrace);
    managed =
        capture ||
        persistent ||
        heap.allocates(calls) ||
        _requiresNativeContext(roots) ||
        unwindsTo(roots);
    for (final body in functions.values) {
      // Factory inputs are accounted for at their originating construction sites.
      if (heap.allocates([body.target])) continue;
      final source = (members.callTypes?.program ?? members.program)
          .implementationOf(body.sourceTarget);
      final observed = {
        if (source is IrFunction)
          for (final block in source.blocks) ...[
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ],
      };
      Value unview(Value value) {
        while (value is TypeView) {
          value = value.operand;
        }
        return value;
      }

      Value physicalAlias(Value value) {
        final visited = <Value>{};
        while (visited.add(value)) {
          value = unview(value);
          if (!body.aliases.contains(value)) return value;
          final inputs = body.operands[value];
          if (inputs == null || inputs.length != 1) return value;
          value = inputs.single;
        }
        throw StateError('Cyclic selected operand aliases.');
      }

      bool sameArgument(
        FunctionTarget callee,
        int slot,
        Value source,
        Value selected,
      ) {
        if (identical(physicalAlias(source), physicalAlias(selected))) {
          return true;
        }
        if (!FfiTypes.isPointer(source.type) ||
            !layouts.pointerRepresentation.contains(callee, slot)) {
          return false;
        }
        final actual = physicalAlias(selected);
        // An address-only entry may receive a pointer stored by its caller.
        // Reading that immutable representation slot is ABI transport, not a
        // new Dart call, check, allocation or user-defined property access.
        return actual is StorageRead &&
            identical(actual.field, layouts.pointers.address) &&
            identical(physicalAlias(actual.receiver), physicalAlias(source));
      }

      for (final MapEntry(key: operation, value: callee)
          in body.invocations.entries) {
        final origin = body.callOrigins[operation] ?? operation;
        final initializer = heap.initializersFor([callee]).firstOrNull;
        if (origin is NativeCallbackAddress &&
            identical(operation, origin) &&
            observed.contains(origin)) {
          final binding =
              members.program.nativeBoundaries?.callbacks[origin.target];
          final inputs = body.operands[operation] ?? operation.inputs;
          if (binding != null &&
              identical(binding.address, callee) &&
              identical(callbacks[origin.target], callee) &&
              inputs.isEmpty) {
            // The verified graph owns this exact native entry address. Its
            // provider only materializes a machine address; the callback body
            // and lifecycle are ordinary source definitions in that binding.
            continue;
          }
        }
        if (origin is RawNativeCall &&
            operation is DirectCall &&
            observed.contains(origin)) {
          final abi = layouts.nativeCalls.entries[callee];
          final inputs = body.operands[operation] ?? operation.inputs;
          final original = origin.inputs.toList();
          if (abi != null &&
              abi.signature == origin.signature &&
              abi.isLeaf == origin.isLeaf &&
              inputs.length == original.length &&
              original.indexed.every(
                (entry) =>
                    identical(unview(entry.$2), unview(inputs[entry.$1])),
              )) {
            // The source already owns this exact external C operation. This
            // target only lays out its explicit scalar/address carriers.
            continue;
          }
        }
        if (observed.contains(origin) &&
            origin is Construct &&
            initializer == origin.initializer) {
          continue;
        }
        if (origin is ManagedStorageAllocation &&
            identical(origin, operation) &&
            observed.contains(origin) &&
            identical(origin.allocator, callee) &&
            identical(heap.runtime?.allocate, callee) &&
            (members.callTypes?.executionTargetsOf(origin).contains(callee) ??
                false)) {
          final inputs = body.operands[operation] ?? origin.inputs;
          if (inputs.length == origin.inputs.length &&
              origin.inputs.indexed.every(
                (entry) =>
                    sameArgument(callee, entry.$1, entry.$2, inputs[entry.$1]),
              )) {
            continue;
          }
        }
        if (origin is DirectCall &&
            operation is DirectCall &&
            observed.contains(origin) &&
            origin.target.implementation == callee.implementation) {
          final inputs = body.operands[operation] ?? operation.inputs;
          if (inputs.length >= origin.inputs.length &&
              origin.inputs.indexed.every(
                (entry) =>
                    sameArgument(callee, entry.$1, entry.$2, inputs[entry.$1]),
              )) {
            continue;
          }
        }
        final sourceSelector = origin is InstanceCall
            ? origin.member.selector
            : origin.implicitMember?.selector;
        if (origin case InstanceCall(entryBinding: final binding?)
            when operation is DirectCall && observed.contains(origin) &&
                binding.entries.containsValue(callee) &&
                (members.callTypes?.executionTargetsOf(origin).contains(callee) ?? false)) {
          final expected = [origin.receiver, ...origin.positional,
            for (final name in binding.names) origin.named[name]!,
            ...origin.executionTypes];
          final inputs = (body.operands[operation] ?? operation.inputs).toList();
          if (inputs.length == expected.length && expected.indexed.every(
              (entry) => sameArgument(callee, entry.$1, entry.$2, inputs[entry.$1]))) {
            continue;
          }
        }
        final selectedSelector = operation is InstanceCall
            ? operation.member.selector
            : operation.implicitMember?.selector;
        if (sourceSelector != null &&
            selectedSelector == sourceSelector &&
            callee.kind.isVirtual &&
            callee.selector == sourceSelector &&
            observed.contains(origin) &&
            (members.callTypes?.executionTargetsOf(origin).contains(callee) ??
                false)) {
          final original = origin.inputs.toList();
          final definition = members.program.implementationOf(callee)!;
          final expected = [
            original.first,
            ...callee.signature.bind<Value>(
              origin is InstanceCall
                  ? origin.positional
                  : original.skip(1).toList(),
              origin is InstanceCall ? origin.named : const {},
              (i) => definition.defaults[i]!,
            ),
          ];
          final inputs = body.operands[operation] ?? operation.inputs.toList();
          if (inputs.length == expected.length &&
              expected.indexed.every(
                (entry) =>
                    sameArgument(callee, entry.$1, entry.$2, inputs[entry.$1]),
              )) {
            continue;
          }
        }
        if (origin is CheckedTypeArgument &&
            identical(operation, origin) &&
            observed.contains(origin) &&
            origin.implementation == callee &&
            (members.callTypes?.executionTargetsOf(origin).contains(callee) ??
                false)) {
          final inputs = body.operands[operation] ?? origin.inputs.toList();
          final original = origin.inputs.toList();
          if (inputs.length == original.length &&
              original.indexed.every(
                (entry) => identical(inputs[entry.$1], entry.$2),
              )) {
            continue;
          }
        }
        if (origin is DynamicDispatch && operation is DirectCall &&
            observed.contains(origin) && origin.methodBindings.containsValue(callee) &&
            (members.callTypes?.executionTargetsOf(origin).contains(callee) ?? false)) {
          final inputs = body.operands[operation] ?? operation.inputs;
          if (inputs.length == 1 && identical(inputs.single, origin.receiver)) {
            continue;
          }
        }
        if (origin is FunctionCall &&
            operation is FunctionCall &&
            observed.contains(origin) &&
            (members.callTypes?.executionTargetsOf(origin).contains(callee) ??
                false)) {
          // Captures and supplied arguments are wired by this source operation;
          // casts, boxes and reification helpers have their own call identities.
          continue;
        }
        implicitCalls.add(initializer ?? callee);
        unobservedCalls[origin] = (
          caller: body.sourceTarget,
          target: initializer ?? callee,
        );
      }
    }
    calls.addAll(implicitCalls);
    heap.retain(calls);
    primitives = heap.primitives.intersection(calls);
    final missing = calls.difference({
      ...callbacks.values,
      ...functions.keys,
      ...primitives,
      ...layouts.nativeCalls.entries.keys,
      ...members.definitions,
    });
    if (missing.isNotEmpty) return missing;
    IrProgram(
      [
        ...layouts.closures.classes,
        ?layouts.records.generatedClass,
        layouts.strings.declaration,
        ...layouts.types.classes,
        if (functions.containsKey(layouts.pointers.initializer))
          layouts.pointers.declaration,
      ],
      support,
      externals: [
        for (final target in [
          ...heap.primitives,
          ...layouts.nativeCalls.entries.keys,
        ])
          IrExternal(target),
        // Source bodies were verified already; this boundary owns generated bodies.
        for (final target in {
          for (final declaration in [
            layouts.strings.declaration,
            ...layouts.types.classes,
          ]) ...{
            ...declaration.members.values,
            ...declaration.implementations.values,
            ...declaration.constructors.values,
          },
          ...?heap.runtime?.types?.entries,
        })
          if (!target.isAbstract &&
              !support.any((body) => body.target == target))
            IrExternal(
              target,
              defaults: members.program.implementationOf(target)!.defaults,
            ),
      ],
    );
    return {};
  }

  // Calls inherit a context until their own activation binds one. The binding
  // expires at that activation's exit; a callee cannot initialize its caller.
  bool _requiresNativeContext(Set<FunctionTarget> roots) {
    final pending = roots.toList(), visited = <FunctionTarget>{};
    while (pending.isNotEmpty) {
      final target = pending.removeLast();
      if (!visited.add(target)) continue;
      final body = functions[target];
      if (body == null) continue;
      final blocks = [(body.entry, false)], reached = <(Block, bool)>{};
      while (blocks.isNotEmpty) {
        final state = blocks.removeLast();
        if (!reached.add(state)) continue;
        final (block, initiallyBound) = state;
        var bound = initiallyBound;
        for (final operation in body.instructions[block]!) {
          if (body.aliases.contains(operation)) continue;
          if (operation is BindNativeContext) bound = true;
          if (!bound) {
            if (operation is ReadNativeContext) return true;
            pending.addAll(body.targetsOf(operation));
          }
        }
        blocks.addAll(
          body.successors(block).map((edge) => (edge.target, bound)),
        );
      }
    }
    return false;
  }

  /// Whether an uncaught Dart failure can escape one of the supplied entries.
  bool unwindsTo(Set<FunctionTarget> roots) {
    final callers = <FunctionTarget, Set<FunctionTarget>>{};
    final pending = <FunctionTarget>[];
    for (final body in functions.values) {
      for (final block in body.blocks) {
        final end = body.ends[block];
        if (end is Throw && end.onThrow == null) pending.add(body.target);
        for (final operation in body.instructions[block]!) {
          if (end is Invoke &&
              (identical(end.operation, operation) ||
                  operation is IndirectInvocation &&
                      identical(end.operation, operation.origin))) {
            continue;
          }
          for (final target in body.targetsOf(operation)) {
            (callers[target] ??= {}).add(body.target);
          }
        }
      }
    }
    final visited = <FunctionTarget>{};
    while (pending.isNotEmpty) {
      final target = pending.removeLast();
      if (!visited.add(target)) continue;
      if (roots.contains(target)) return true;
      pending.addAll(callers[target] ?? const {});
    }
    return false;
  }
}
