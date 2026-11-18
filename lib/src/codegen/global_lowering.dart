import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

/// Gives reachable global bindings ordinary typed storage and executable bodies.
///
/// A bound transform preserves slot and helper identities as implementation
/// closure discovers more globals. Growing its module object replaces every old
/// reference in the program; no old execution facts survive that replacement.
final class GlobalLowering({final IrCallable? lateError}) extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final state = _GlobalBindings(lateError?.target);
    return ProgramTransform((facts) {
      facts.checkProgram(facts.program);
      return state.lower(
        facts.program,
        facts.definitions,
        demanded: facts.reachesOperation,
      );
    });
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);

  /// Lowers one supplied implementation set with fresh module ownership.
  IrProgram lower(IrProgram program, Iterable<FunctionTarget> definitions) =>
      _GlobalBindings(lateError?.target).lower(program, definitions.toSet());
}

final class _GlobalBindings(FunctionTarget? lateError) {
  FunctionTarget? _lateError = lateError;
  final _type = ClassType(null, 'Root');
  final _fields = <GlobalVariable, (InstanceField?, InstanceField?)>{};
  final _getters = <GlobalVariable, FunctionTarget>{};
  final _setters = <GlobalVariable, FunctionTarget>{};
  ModuleObject? _holder;

  IrProgram lower(
    IrProgram program,
    Set<FunctionTarget> definitions, {
    bool Function(Instruction)? demanded,
  }) {
    final discovered = {
      for (final body in program.functions)
        if (definitions.contains(body.target))
          for (final block in body.blocks)
            for (final operation in [
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ])
              if (demanded == null || demanded(operation))
                if (operation
                    case LoadGlobal(:final global) ||
                        StoreGlobal(:final global))
                  global,
    }.difference(_fields.keys.toSet());
    final extended = discovered.isNotEmpty;
    if (!extended && _holder == null) return program;
    final previous = extended ? _holder : null;
    var changed = extended || program.globals.any(_fields.containsKey);
    for (final global in discovered) {
      if (global.isFinal && global.type != .never ||
          global.isLate && global.initializer == null) {
        _lateError ??= program.classes
            .where(
              (declaration) =>
                  declaration.type.library == Uri.parse('dart:_internal') &&
                  declaration.type.name == 'LateError',
            )
            .firstOrNull
            ?.constructors['new'];
        if (_lateError == null ||
            program.implementationOf(_lateError!) == null) {
          throw UnsupportedError(
            'Global final/late storage requires the SDK LateError constructor.',
          );
        }
      }
      final index = _fields.length;
      _fields[global] = (
        global.type == .never
            ? null
            : InstanceField(_type, 'value.$index', global.type),
        global.type == .never || global.isInitiallyBound
            ? null
            : InstanceField(_type, 'bound.$index', .boolean),
      );
      _getters[global] = FunctionTarget(null, 'get.$index', global.type, []);
      _setters[global] = FunctionTarget(null, 'set.$index', .voidType, [
        global.type,
      ]);
    }
    final declaration = IrClass(_type, [
      for (final (value, bound) in _fields.values) ...[?value, ?bound],
    ]);
    if (extended) {
      _holder = ModuleObject(
        _type,
        initialFields: {
          for (final MapEntry(key: global, value: (value, bound))
              in _fields.entries) ...{
            ?bound: const Constant.boolean(false),
            if (value != null && global.isInitiallyBound)
              value: const Constant.nullValue(),
          },
        },
      );
    }
    final generated = {..._getters.values, ..._setters.values};
    final needed = <GlobalVariable>{};
    final functions = <IrFunction>[];
    for (final body in program.functions) {
      if (extended && generated.contains(body.target)) continue;
      final operations = <Instruction, Instruction>{};
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          switch (operation) {
            case LoadGlobal(:final global) when _getters.containsKey(global):
              operations[operation] = DirectCall(_getters[global]!, []);
              needed.add(global);
            case StoreGlobal(:final global, :final value)
                when _setters.containsKey(global):
              operations[operation] = DirectCall(_setters[global]!, [value]);
              needed.add(global);
            case ModuleObjectReference(:final declaration)
                when identical(declaration, previous):
              operations[operation] = ModuleObjectReference(_holder!);
            default:
              break;
          }
        }
      }
      changed |= operations.isNotEmpty;
      functions.add(
        operations.isEmpty
            ? body
            : FunctionRewrite(body, executionShapes: program.executionShapes, operations: operations).run(),
      );
    }
    if (!changed) return program;
    for (final global in _fields.keys) {
      if (extended ||
          needed.contains(global) &&
              program.implementationOf(_getters[global]!) == null) {
        functions.add(_getter(global, _setters[global]!));
      }
      if (extended ||
          needed.contains(global) &&
              program.implementationOf(_setters[global]!) == null) {
        functions.add(_setter(global));
      }
    }
    return IrProgram(
      [
        ...program.classes.where((existing) => existing.type != _type),
        declaration,
      ],
      functions,
      globals: program.globals.where((global) => !_fields.containsKey(global)),
      nativeBoundaries: program.nativeBoundaries,
      executionShapes: program.executionShapes,
      externals: program.externals,
    );
  }

  IrFunction _getter(GlobalVariable global, FunctionTarget setter) {
    final target = _getters[global]!;
    final entry = Block();
    if (global.type == .never) {
      // There is no successful value to store or commit for bottom-typed slots.
      if (global.initializer case final initializer?) {
        entry.finish(Unreachable(entry.emit(DirectCall(initializer, []))));
      } else {
        _throwLateError(
          entry,
          "Field '${global.name}' has not been initialized.",
        );
      }
      return IrFunction(target, [entry]);
    }
    final base = entry.emit(ModuleObjectReference(_holder!));
    final (valueSlot, boundSlot) = _fields[global]!;
    final valueField = valueSlot!, boundField = boundSlot;
    if (boundField == null) {
      entry.finish(Return(entry.emit(LoadField(valueField, base))));
      return IrFunction(target, [entry]);
    }
    final bound = Block(), initialize = Block();
    final flag = entry.emit(LoadField(boundField, base));
    entry.finish(Branch(flag, Jump(bound), Jump(initialize)));
    bound.finish(Return(bound.emit(LoadField(valueField, base))));
    if (global.initializer case final initializer?) {
      final value = initialize.emit(DirectCall(initializer, []));
      // Commit only after success; writes by a throwing initializer survive.
      initialize.emit(DirectCall(setter, [value]));
      initialize.finish(Return(value));
    } else {
      _throwLateError(
        initialize,
        "Field '${global.name}' has not been initialized.",
      );
    }
    return IrFunction(target, [entry, bound, initialize]);
  }

  IrFunction _setter(GlobalVariable global) {
    final target = _setters[global]!;
    final entry = Block(target.parameterTypes);
    if (global.type == .never) {
      // No well-typed execution can supply this argument. Keep that obligation
      // explicit instead of manufacturing a value or changing a binding flag.
      entry.finish(Unreachable(entry.parameters.single));
      return IrFunction(target, [entry]);
    }
    final blocks = [entry];
    final (valueSlot, boundSlot) = _fields[global]!;
    final valueField = valueSlot!, boundField = boundSlot;
    final base = entry.emit(ModuleObjectReference(_holder!));
    Block commit = entry;
    if (global.isFinal) {
      commit = Block();
      final failed = Block();
      blocks.addAll([commit, failed]);
      final flag = entry.emit(LoadField(boundField!, base));
      entry.finish(Branch(flag, Jump(failed), Jump(commit)));
      _throwLateError(
        failed,
        global.initializer != null
            ? "Field '${global.name}' has been assigned during initialization."
            : "Field '${global.name}' has already been initialized.",
      );
    }
    commit.emit(StoreField(valueField, base, entry.parameters.single));
    if (boundField != null) {
      commit.emit(StoreField(boundField, base, const Constant.boolean(true)));
    }
    commit.finish(const Return());
    return IrFunction(target, blocks);
  }

  void _throwLateError(Block block, String message) {
    block.finish(
      Throw(block.emit(Construct(_lateError!, [Constant.string(message)]))),
    );
  }
}
