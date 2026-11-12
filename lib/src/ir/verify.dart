import 'block.dart';
import 'core_types.dart';
import 'ffi_types.dart';
import 'signature.dart';
import 'type.dart';
import 'value.dart';

typedef FunctionReferences = ({
  Set<FunctionTarget> closures,
  Set<FunctionTarget> callees,
  Set<({ValueType receiver, FunctionTarget target})> virtualMembers,
  Set<({ValueType receiver, FunctionTarget method, bool direct})>
  methodTearOffs,
  Set<({ValueType receiver, MemberSelector selector})> implicitMembers,
  Set<ClassType> instantiatedClasses,
  Set<GlobalVariable> globals,
  Set<InstanceField> fields,
  Set<ObjectConstant> objects,
  Set<FunctionConstant> functionConstants,
  Set<SequenceConstant> sequenceConstants,
  Set<ClassType> classes,
  Set<DeferredImport> deferredImports,
});

/// Checks declaration scope and defaults, then verifies a supplied SSA graph.
FunctionReferences verifyCallable(
  FunctionTarget target,
  Iterable<Constant> defaults, {
  List<Block>? blocks,
  FunctionBodyKind bodyKind = .synchronous,
  ValueType? yieldType,
  ValueType? completionType,
}) {
  Set<FunctionTarget>? closures;
  Set<FunctionTarget>? callees;
  Set<({ValueType receiver, FunctionTarget target})>? virtualMembers;
  Set<({ValueType receiver, FunctionTarget method, bool direct})>?
  methodTearOffs;
  Set<({ValueType receiver, MemberSelector selector})>? implicitMembers;
  Set<ClassType>? instantiatedClasses;
  Set<GlobalVariable>? globals;
  Set<InstanceField>? fields;
  Set<ObjectConstant>? objects;
  Set<FunctionConstant>? functionConstants;
  Set<SequenceConstant>? sequenceConstants;
  Set<ClassType>? classes;
  Set<DeferredImport>? deferredImports;
  final scope = <TypeParameterType>{};
  // Structural equality omits generic default metadata; scope checks cannot.
  final checkedTypes = Set<ValueType>.identity();
  FunctionReferences references() {
    sealTypes([
      ...checkedTypes,
      ...scope,
      ?target.owner,
      for (final callee in [
        ...?callees,
        for (final member in virtualMembers ?? const {}) member.target,
      ]) ...[callee.signature, ?callee.owner],
    ]);
    return (
      closures: _snapshot(closures),
      callees: _snapshot(callees),
      virtualMembers: _snapshot(virtualMembers),
      methodTearOffs: _snapshot(methodTearOffs),
      implicitMembers: _snapshot(implicitMembers),
      instantiatedClasses: _snapshot(instantiatedClasses),
      globals: _snapshot(globals),
      fields: _snapshot(fields),
      objects: _snapshot(objects),
      functionConstants: _snapshot(functionConstants),
      sequenceConstants: _snapshot(sequenceConstants),
      classes: _snapshot(classes),
      deferredImports: _snapshot(deferredImports),
    );
  }

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
    if (checkedTypes.contains(type)) return;
    for (final declaration in typeDeclarationsIn(type)) {
      if (declaration is ClassType) {
        (classes ??= {}).add(declaration);
      } else if (!scope.contains(declaration)) {
        throw StateError('Type parameter used outside its lexical scope.');
      }
    }
    if (type == ValueType.integer || type == ValueType.floating) {
      (instantiatedClasses ??= {}).add(type as ClassType);
    }
    checkedTypes.add(type);
  }

  void constant(Constant value) {
    checkTypeScope(value.type);
    if (value.type == ValueType.string) {
      (instantiatedClasses ??= {}).add(ValueType.string);
    }
    if (value is TypeConstant) checkTypeScope(value.representedType);
    if (value is SequenceConstant) {
      (sequenceConstants ??= {}).add(value);
    }
    if (value case FunctionConstant(
      target: final callee,
      :final ownerType,
      :final typeArguments,
      :final constructorSignature,
      :final constructorTypeArguments,
    )) {
      (functionConstants ??= {}).add(value);
      (callees ??= {}).add(callee);
      if (callee.implementation.kind == .initializer) {
        (instantiatedClasses ??= {}).add(callee.implementation.owner!);
      }
      if (constructorSignature != null) checkTypeScope(constructorSignature);
      if (constructorTypeArguments != null) {
        checkTypeScope(
          FunctionType(
            ValueType.voidType,
            constructorTypeArguments,
            typeParameters: constructorSignature!.typeParameters,
          ),
        );
      }
      if (ownerType != null) checkTypeScope(ownerType);
      for (final type in typeArguments ?? const <ValueType>[]) {
        checkTypeScope(type);
      }
    }
    if (value is ObjectConstant) {
      (instantiatedClasses ??= {}).add((value.type as ClassType).declaration);
      (objects ??= {}).add(value);
      (fields ??= {}).addAll(value.fields.keys);
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
  if (yieldType != null) checkTypeScope(yieldType);
  if (completionType != null) checkTypeScope(completionType);
  for (final parameter in target.typeParameters) {
    checkTypeScope(parameter.bound);
    if (parameter.defaultType case final defaultType?) {
      checkTypeScope(defaultType);
    }
  }
  for (final capture in target.captures) {
    checkTypeScope(capture);
  }
  if (blocks == null) return references();
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
  // A one-block graph cannot have a valid edge: entry and missing targets fail.
  final predecessors = blocks.length == 1
      ? null
      : {for (final b in blocks) b: <Block>[]};
  if (predecessors != null && predecessors.length != blocks.length) {
    throw StateError('Repeated block.');
  }
  final definitions = Map<Value, (Block, int)>.identity();
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
    switch (block.end) {
      case Invoke(:final operation):
        define(operation, block.instructions.length);
      case Await(:final result):
        define(result, block.instructions.length);
      default:
        break;
    }
    for (final next in block.successors) {
      final incoming = predecessors?[next.target];
      if (incoming == null || next.target == entry) {
        throw StateError('Invalid control-flow edge.');
      }
      incoming.add(block);
    }
  }
  final idom = predecessors == null
      ? const <Block, Block>{}
      : _dominators(entry, predecessors);
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
        throw StateError('Control-flow result used outside its normal edge.');
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
      Value? result,
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
        MakeInvocation(:final typeArguments) ||
        FunctionCall(:final typeArguments) ||
        InstantiateFunction(:final typeArguments) => typeArguments,
        _ => const <ValueType>[],
      };
      for (final type in typeArguments) {
        checkTypeScope(type);
      }
      if (op.implicitMember case final member?) {
        (implicitMembers ??= {}).add(member);
      }
      switch (op) {
        case LoadLibrary(:final reference) ||
            CheckLibraryLoaded(:final reference):
          (deferredImports ??= {}).add(reference);
        case InstanceCall(member: final callee, :final receiver) ||
            BindMethod(method: final callee, :final receiver, direct: false):
          (virtualMembers ??= {}).add((
            receiver: receiver.unviewedType,
            target: callee,
          ));
        case DirectCall(target: final callee) ||
            BindMethod(method: final callee) ||
            Construct(initializer: final callee):
          (callees ??= {}).add(callee);
        case LoadField(:final field) || StoreField(:final field):
          (fields ??= {}).add(field);
          if (field.initializer case final initializer? when op is LoadField) {
            (callees ??= {}).add(initializer);
          }
        default:
          break;
      }
      switch (op) {
        case BindMethod(:final method, :final direct, :final receiver):
          (methodTearOffs ??= {}).add((
            receiver: receiver.unviewedType,
            method: method,
            direct: direct,
          ));
        case NativeView(type: final ClassType type) ||
            NewPayload(type: final ClassType type):
          (instantiatedClasses ??= {}).add(type.declaration);
        case Construct(:final instantiatedType):
          (instantiatedClasses ??= {}).add(instantiatedType.declaration);
        case StringFromCharCode() || StringFromCharCodes() || StringConcat():
          (instantiatedClasses ??= {}).add(ValueType.string);
        case PointerFromAddress() || PointerOffset() || NativeCall()
            when FfiTypes.isPointer(op.type):
          (instantiatedClasses ??= {}).add(FfiTypes.pointer);
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
            op is! KeepAlive &&
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
        final resultType = completionType != null
            ? ValueType.futureOr(completionType)
            : yieldType == null
            ? target.returnType
            : ValueType.nullType;
        if (!resultType.accepts(value?.type ?? .nullType)) {
          throw StateError(
            'Return type ${value?.type.dartName} does not match ${resultType.dartName} in ${target.owner?.dartName}.${target.name}.',
          );
        }
        if (value != null) use(value, count);
      case Await(
        :final operand,
        :final result,
        :final onResume,
        :final onThrow,
      ):
        if (bodyKind != .asynchronous && bodyKind != .asyncGenerator) {
          throw StateError('Await outside an async body.');
        }
        use(operand, count);
        if (onResume != null) useEdge(onResume, result: result);
        if (onThrow != null) useEdge(onThrow, unwinding: true);
      case Yield(:final value, :final onResume, :final onCancel):
        if (yieldType == null ||
            (bodyKind == .asyncGenerator) != (onCancel != null) ||
            !isDartType(value.type) ||
            !yieldType.accepts(value.type)) {
          throw StateError('Yield outside a compatible generator body.');
        }
        use(value, count);
        useEdge(onResume);
        if (onCancel != null) useEdge(onCancel);
      case YieldStream(
        :final stream,
        :final onResume,
        :final onCancel,
        :final onThrow,
      ):
        if (bodyKind != .asyncGenerator ||
            !CoreTypes.streamOf(yieldType!).accepts(stream.type)) {
          throw StateError(
            'Stream delegation requires a compatible async generator.',
          );
        }
        use(stream, count);
        useEdge(onResume);
        useEdge(onCancel);
        if (onThrow != null) useEdge(onThrow, unwinding: true);
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
  return references();
}

Set<T> _snapshot<T>(Set<T>? values) => Set<T>.unmodifiable(values ?? const []);

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
