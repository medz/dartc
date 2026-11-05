import 'block.dart';
import 'signature.dart';
import 'type.dart';
import 'value.dart';

/// Checks control flow, argument and return types, and SSA definition dominance.
({Set<FunctionTarget> closures, Set<GlobalVariable> globals}) verifyFunction(
  FunctionTarget target,
  List<Block> blocks, [
  Iterable<Constant> defaults = const [],
]) {
  Set<FunctionTarget>? closures;
  Set<GlobalVariable>? globals;
  final scope = <TypeParameterType>{};
  for (
    FunctionTarget? lexical = target;
    lexical != null;
    lexical = lexical.enclosing
  ) {
    scope.addAll(lexical.typeParameters);
    if (lexical.kind.hasReceiver || lexical.kind == .factory) {
      scope.addAll(lexical.owner?.typeParameters ?? const []);
    }
  }
  void checkTypeScope(ValueType type) {
    if (typeParametersIn(type).any((parameter) => !scope.contains(parameter))) {
      throw StateError('Type parameter used outside its lexical scope.');
    }
  }

  void constant(Constant value) {
    checkTypeScope(value.type);
    if (value case FunctionConstant(
      :final ownerType,
      :final typeArguments,
      :final constructorSignature,
    )) {
      if (constructorSignature != null) checkTypeScope(constructorSignature);
      if (ownerType != null) checkTypeScope(ownerType);
      for (final type in typeArguments ?? const <ValueType>[]) {
        checkTypeScope(type);
      }
    }
    final children = switch (value) {
      RecordConstant(:final fields) => fields,
      SequenceConstant(:final elements) => elements,
      MapConstant(:final entries) => entries.expand(
        (entry) => [entry.$1, entry.$2],
      ),
      ObjectConstant(:final fields) => fields.values,
      _ => const <Constant>[],
    };
    for (final child in children) {
      constant(child);
    }
  }

  for (final value in defaults) {
    constant(value);
  }
  checkTypeScope(target.signature);
  for (final parameter in target.typeParameters) {
    checkTypeScope(parameter.bound);
    if (parameter.defaultType case final defaultType?) {
      checkTypeScope(defaultType);
    }
  }
  for (final capture in target.captures) {
    checkTypeScope(capture);
  }
  if (blocks.isEmpty) throw StateError('Function has no entry.');
  final entry = blocks.first;
  if (target.parameterTypes.length != entry.parameters.length ||
      entry.parameters.indexed.any(
        (p) => p.$2.type != target.parameterTypes[p.$1],
      )) {
    throw ArgumentError(
      'Entry parameters do not match the function signature.',
    );
  }
  final predecessors = {for (final b in blocks) b: <Block>[]};
  if (predecessors.length != blocks.length) {
    throw StateError('Repeated block.');
  }
  final definitions = <Value, (Block, int)>{};
  for (final block in blocks) {
    void define(Value value, int position) {
      checkTypeScope(value.type);
      if (definitions.containsKey(value)) {
        throw StateError('Repeated SSA definition.');
      }
      definitions[value] = (block, position);
    }

    for (final parameter in block.parameters) {
      define(parameter, -1);
    }
    for (var i = 0; i < block.instructions.length; i++) {
      define(block.instructions[i], i);
    }
    if (block.end case Invoke(:final operation)) {
      define(operation, block.instructions.length);
    }
    for (final next in block.successors) {
      final incoming = predecessors[next.target];
      if (incoming == null || next.target == entry) {
        throw StateError('Invalid control-flow edge.');
      }
      incoming.add(block);
    }
  }
  final idom = _dominators(entry, predecessors);
  for (final block in blocks) {
    void use(Value value, int position) {
      if (value is Constant) {
        constant(value);
        return;
      }
      final definition = definitions[value];
      if (definition == null) {
        throw StateError('Value defined outside this function.');
      }
      final (owner, index) = definition;
      if (index == owner.instructions.length) {
        throw StateError('Invoke result used outside its normal edge.');
      }
      if (owner == block) {
        if (index >= position) {
          throw StateError('Value used before its definition.');
        }
      } else {
        var ancestor = block;
        while (ancestor != owner && ancestor != entry) {
          ancestor = idom[ancestor]!;
        }
        if (ancestor != owner) {
          throw StateError('Value does not dominate its use.');
        }
      }
    }

    final count = block.instructions.length;
    final end = block.end;
    void useEdge(
      Jump edge, {
      TypeTest? test,
      bool? outcome,
      Instruction? result,
      bool unwinding = false,
    }) {
      for (final value in edge.arguments) {
        if (identical(value, result) || (unwinding && value is UnwindValue)) {
          continue;
        }
        if (value is TestedValue &&
            value.test == test &&
            value.outcome == outcome) {
          use(value.test, count);
        } else {
          use(value, count);
        }
      }
    }

    void checkOperation(Instruction op, int position) {
      checkTypeScope(op.type);
      if (op case ReifyType(:final template)) checkTypeScope(template);
      if (op case TypeTest(:final testedType)) checkTypeScope(testedType);
      if (op
          case DirectCall(:final ownerType?) ||
              InstanceCall(:final ownerType?) ||
              BindMethod(:final ownerType?)) {
        checkTypeScope(ownerType);
      }
      final typeArguments = switch (op) {
        DirectCall(:final typeArguments) ||
        InstanceCall(:final typeArguments) ||
        DynamicDispatch(:final typeArguments) ||
        FunctionCall(:final typeArguments) ||
        InstantiateFunction(:final typeArguments) => typeArguments,
        _ => const <ValueType>[],
      };
      for (final type in typeArguments) {
        checkTypeScope(type);
      }
      switch (op) {
        case LoadGlobal(:final global) || StoreGlobal(:final global):
          (globals ??= {}).add(global);
        case MakeClosure(target: final child):
          if (child.enclosing != target) {
            throw StateError('Closure created outside its lexical parent.');
          }
          (closures ??= {}).add(child);
        case StoreField(:final field, :final receiver)
            when field.isFinal && !field.isLate:
          if (target.kind != .initializer ||
              target.owner != field.owner ||
              receiver != entry.parameters.first) {
            throw StateError(
              'Final field write outside its declaring initializer.',
            );
          }
        case DirectCall(target: final callee, :final inputs)
            when callee.kind == .initializer:
          if (target.kind != .initializer ||
              inputs.first != entry.parameters.first ||
              (callee.owner != target.owner &&
                  callee.owner != target.owner!.superclass?.declaration)) {
            throw StateError(
              'An initializer can only delegate on its own receiver.',
            );
          }
        default:
          break;
      }
      for (final input in op.inputs) {
        checkTypeScope(input.type);
        if (input.type is CellType &&
            op is! ReadCell &&
            op is! CopyCell &&
            op is! WriteCell &&
            op is! MakeClosure) {
          throw StateError('Capture storage used as a Dart value.');
        }
        use(input, position);
      }
    }

    for (var i = 0; i < count; i++) {
      final op = block.instructions[i];
      if (op.type == .never &&
          (i + 1 != count || end is! Unreachable || end.cause != op)) {
        throw StateError('A Never instruction must end its block.');
      }
      checkOperation(op, i);
    }
    switch (end) {
      case Return(:final value):
        if (!target.returnType.accepts(value?.type ?? .nullType)) {
          throw StateError(
            'Return type ${value?.type.dartName} does not match ${target.returnType.dartName} in ${target.owner?.dartName}.${target.name}.',
          );
        }
        if (value != null) use(value, count);
      case Throw(:final exception, :final stackTrace, :final onThrow):
        use(exception, count);
        if (stackTrace != null) use(stackTrace, count);
        if (onThrow != null) useEdge(onThrow, unwinding: true);
      case Unreachable(:final cause):
        use(cause, count);
      case ExhaustivenessFailure(:final onThrow):
        if (onThrow != null) useEdge(onThrow, unwinding: true);
      case Invoke(:final operation, :final onReturn, :final onThrow):
        checkOperation(operation, count);
        if (onReturn != null) useEdge(onReturn, result: operation);
        useEdge(onThrow, unwinding: true);
      case Branch(:final condition, :final ifTrue, :final ifFalse):
        use(condition, count);
        final test = condition is TypeTest ? condition : null;
        useEdge(ifTrue, test: test, outcome: true);
        useEdge(ifFalse, test: test, outcome: false);
      case final Jump edge:
        useEdge(edge);
    }
  }
  return (
    closures: closures == null ? const {} : Set.unmodifiable(closures!),
    globals: globals == null ? const {} : Set.unmodifiable(globals!),
  );
}

Map<Block, Block> _dominators(
  Block entry,
  Map<Block, List<Block>> predecessors,
) {
  final visited = <Block>{};
  final order = <Block, int>{};
  final stack = [(entry, false)];
  while (stack.isNotEmpty) {
    final (block, leaving) = stack.removeLast();
    if (leaving) {
      order[block] = order.length;
    } else if (visited.add(block)) {
      stack.add((block, true));
      for (final next in block.successors) {
        stack.add((next.target, false));
      }
    }
  }
  if (order.length != predecessors.length) {
    throw StateError('Unreachable block.');
  }
  final reversePostorder = order.keys.toList().reversed.skip(1);
  final idom = {entry: entry};
  bool changed;
  do {
    changed = false;
    for (final block in reversePostorder) {
      Block? parent;
      for (var incoming in predecessors[block]!) {
        if (!idom.containsKey(incoming)) continue;
        parent ??= incoming;
        // A strict dominator has a larger DFS postorder number than its descendants.
        while (parent != incoming) {
          if (order[parent]! < order[incoming]!) {
            parent = idom[parent]!;
          } else {
            incoming = idom[incoming]!;
          }
        }
      }
      if (parent != idom[block]) {
        idom[block] = parent!;
        changed = true;
      }
    }
  } while (changed);
  return idom;
}
