import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

/// Makes constructor function values call ordinary, analyzed implementation bodies.
///
/// Extraction keeps the source declaration and alias identity. Its allocation,
/// initializer and factory calls enter the program before semantic specialization.
final class const ConstructorTearOffLowering() extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final bridges = _ConstructorBridges();
    return ProgramTransform(bridges.lower, rebindEntryConstant: bridges.rebind);
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}

final class _ConstructorBridges() {
  final _entries = <Object, FunctionTarget>{};
  final _bodies = <FunctionTarget, IrFunction>{};
  Map<Constant, Constant> _constants = const {};

  Constant rebind(Constant value) => _constants[value] ?? value;

  IrProgram lower(ProgramFlowFacts facts) {
    final program = facts.program;
    facts.checkProgram(program);
    var changed = false;
    final constants = _constants = <Constant, Constant>{};

    late Constant Function(Constant) rewrite;
    FunctionTarget bridge(FunctionConstant value) {
      final signature = value.genericSignature;
      final key = (value.target, value.ownerType, signature);
      if (_entries[key] case final entry?) return entry;
      final entry = FunctionTarget(
        null,
        'constructor${_entries.length}',
        signature.result,
        signature.parameters,
        typeParameters: signature.typeParameters,
        optionalPositional: signature.optionalPositional,
        namedParameters: signature.namedParameters,
      );
      // A constructor default may contain this same constructor's tear-off.
      _entries[key] = entry;
      final applied = value.target.resolveConstruction(
        signature.result as ClassType,
      );
      final destination = applied.target.signature;
      final declaration = program.implementationOf(applied.target);
      if (declaration == null) {
        throw ArgumentError(
          'Missing constructor implementation: ${applied.target.name}',
        );
      }
      final defaults = {
        for (final defaultValue in declaration.defaults.entries)
          defaultValue.key: rewrite(defaultValue.value),
      };
      final block = Block(entry.parameterTypes);
      final inputs = destination.bind<Value>(
        block.parameters.take(signature.positionalCount).toList(),
        {
          for (final MapEntry(:key, :value) in signature.named.entries)
            key: block.parameters[value.slot],
        },
        (slot) => defaults[slot]!,
      );
      final operation = applied.target.kind == .initializer
          ? Construct(
              applied.target,
              inputs,
              instantiatedType: applied.ownerType,
            )
          : DirectCall(applied.target, inputs, ownerType: applied.ownerType);
      block.finish(Return(block.emit(operation)));
      _bodies[entry] = IrFunction(
        entry,
        [block],
        defaults: {
          for (
            var slot = signature.requiredPositional;
            slot < signature.positionalCount;
            slot++
          )
            slot: defaults[slot]!,
          for (final MapEntry(:key, :value) in signature.named.entries)
            if (!value.required)
              value.slot: defaults[destination.named[key]!.slot]!,
        },
      );
      return entry;
    }

    rewrite = (constant) {
      if (constants[constant] case final known?) return known;
      var updated = false;
      Constant child(Constant value) {
        final result = rewrite(value);
        updated |= !identical(result, value);
        return result;
      }

      final Constant result;
      switch (constant) {
        case FunctionConstant(:final target, invocationEntry: null)
            when target.kind == .initializer || target.kind == .factory:
          result = constant.withInvocationEntry(bridge(constant));
        case ObjectConstant(:final type, :final fields, :final payload):
          final values = {
            for (final field in fields.entries) field.key: child(field.value),
          };
          final elements = payload.map(child).toList();
          result = updated
              ? ObjectConstant(type as ClassType, values, payload: elements)
              : constant;
        case SequenceConstant(:final type, :final elements):
          final values = elements.map(child).toList();
          result = updated
              ? SequenceConstant(type as ClassType, values)
              : constant;
        case RecordConstant(:final type, :final fields):
          final values = fields.map(child).toList();
          result = updated
              ? RecordConstant(type as RecordType, values)
              : constant;
        case MapConstant(:final type, :final entries):
          final values = [
            for (final (key, value) in entries) (child(key), child(value)),
          ];
          result = updated ? MapConstant(type as ClassType, values) : constant;
        default:
          result = constant;
      }
      constants[constant] = result;
      return result;
    };

    // Precise external inputs are part of the program's execution contract.
    // Discover their implementations without specializing parameter uses before
    // all actual implementation callers have entered the graph.
    for (final entry in facts.entries) {
      for (final argument in entry.arguments) {
        argument.rebindConstants(rewrite);
      }
    }

    final functions = <IrFunction>[];
    for (final function in program.functions) {
      final rewritten = facts.definitions.contains(function.target)
          ? FunctionRewrite(function, executionShapes: program.executionShapes, constants: rewrite).run()
          : function;
      functions.add(rewritten);
      changed |= !identical(rewritten, function);
    }
    final externals = <IrExternal>[];
    for (final external in program.externals) {
      if (!facts.definitions.contains(external.target)) {
        externals.add(external);
        continue;
      }
      final defaults = {
        for (final entry in external.defaults.entries)
          entry.key: rewrite(entry.value),
      };
      final updated = defaults.entries.any(
        (entry) => !identical(entry.value, external.defaults[entry.key]),
      );
      changed |= updated;
      externals.add(
        updated
            ? IrExternal(
                external.target,
                defaults: defaults,
                effects: external.effects,
                terminates: external.terminates,
                memory: external.memory,
                capturesArguments: external.capturesArguments,
              )
            : external,
      );
    }
    for (final entry in _bodies.entries) {
      if (program.implementationOf(entry.key) == null) {
        functions.add(entry.value);
        changed = true;
      }
    }
    return changed
        ? IrProgram(
            program.classes,
            functions,
            globals: program.globals,
            nativeBoundaries: program.nativeBoundaries,
            executionShapes: program.executionShapes,
            externals: externals,
          )
        : program;
  }
}
