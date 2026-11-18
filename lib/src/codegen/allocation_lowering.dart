import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

import 'heap_plan.dart';
import 'heap_runtime.dart';

/// Makes retained allocation and initialization part of the analyzed program.
///
/// Each call keeps its actual arguments, lexical types and exception edges.
/// Newly reached allocation sites are lowered after the next semantic solve;
/// unreachable runtime bodies are not expanded into artificial entry points.
final class AllocationLowering(
  final HeapRuntime runtime, {
  final NativeData? managedContext,
}) extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final heap = HeapPlan(runtime: runtime, managedContext: managedContext);
    final recipes = <Object, ProgramRealization>{};
    void remember(IrFunction body, Instruction operation) {
      final source = body.originOf(operation).source;
      final key = (AllocationLowering, source, operation.runtimeType);
      recipes.putIfAbsent(
        key,
        () => ProgramRealization(
          key,
          (canonical) => _lower(
            canonical,
            canonical.functions.map((f) => f.target).toSet(),
            heap,
            requested: {source},
          ),
        ),
      );
    }

    return ProgramTransform((facts) {
      facts.checkProgram(facts.program);
      return _lower(
        facts.program,
        facts.definitions,
        heap,
        demanded: facts.reachesOperation,
        realized: remember,
      );
    }, realizations: () => recipes.values);
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);

  /// Expands the supplied definitions without changing their callers' roots.
  IrProgram lower(IrProgram program, Iterable<FunctionTarget> definitions) =>
      _lower(
        program,
        definitions.toSet(),
        HeapPlan(runtime: runtime, managedContext: managedContext),
      );

  IrProgram _lower(
    IrProgram program,
    Set<FunctionTarget> definitions,
    HeapPlan heap, {
    bool Function(Instruction)? demanded,
    Set<IrOrigin>? requested,
    void Function(IrFunction, Instruction)? realized,
  }) {
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      if (!definitions.contains(function.target)) {
        functions.add(function);
        continue;
      }
      final implementations =
          <
            Instruction,
            ({
              IrFunction body,
              List<Value> arguments,
              Map<TypeParameterType, ValueType> environment,
              Jump? handler,
            })
          >{};
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (demanded != null && !demanded(operation)) continue;
          if (requested != null &&
              !requested.contains(function.originOf(operation).source))
            continue;
          final IrFunction body;
          final Map<TypeParameterType, ValueType> environment;
          switch (operation) {
            case MaterializeValue(:final value):
              body = heap.materialization(value.type);
              environment = {
                for (final parameter in body.target.typeParameters)
                  parameter: parameter,
              };
            case ProjectValue(:final value, :final shape):
              body = heap.projection(value.type, shape);
              environment = {
                for (final parameter in body.target.typeParameters)
                  parameter: parameter,
              };
            case Construct(callableStorage: final storage?):
              body = heap.callableConstruction(storage, operation.type);
              environment = {
                for (final parameter in body.target.typeParameters)
                  parameter: parameter,
              };
            case Construct(
              :final initializer,
              :final instantiatedType,
              :final storageView,
            ):
              body = heap.construction(initializer, storageView: storageView);
              final sourceEnvironment = initializer.environmentFor(
                instantiatedType,
              );
              environment = {
                for (final parameter in body.target.typeParameters)
                  parameter: sourceEnvironment[parameter] ?? parameter,
              };
            case NewPayload(type: final ClassType type, :final storageView):
              body = heap.payload(type, storageView: storageView);
              environment = {
                for (final parameter in body.target.typeParameters) parameter: parameter,
              };
            default:
              continue;
          }
          realized?.call(function, operation);
          implementations[operation] = (
            body: body,
            arguments: operation.inputs.toList(),
            environment: environment,
            handler: switch (block.end) {
              Invoke(operation: final invoked, :final onThrow)
                  when identical(invoked, operation) =>
                onThrow,
              _ => null,
            },
          );
        }
      }
      final rewritten = implementations.isEmpty
          ? function
          : FunctionRewrite(function, executionShapes: program.executionShapes, lowered: implementations).run();
      changed |= !identical(rewritten, function);
      functions.add(rewritten);
    }
    if (!changed) return program;
    return IrProgram(
      program.classes,
      functions,
      globals: program.globals,
      nativeBoundaries: program.nativeBoundaries,
      executionShapes: program.executionShapes,
      externals: program.externals,
    );
  }
}
