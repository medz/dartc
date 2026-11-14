import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

import 'record_storage.dart';
import 'type_values.dart';

/// Resolves native member entries for the concrete classes in a compilation.
final class MemberCalls(
  final IrProgram program,
  final Set<FunctionTarget> definitions, {
  Iterable<ClassType> instantiatedTypes = const [],
  final RecordStorage? records,
  final CallTypeFacts? callTypes,
}) {
  this {
    if (callTypes case final facts?) {
      final source = facts.program;
      facts.checkProgram(source);
      // Preparation may append helpers, but cannot replace analyzed definitions.
      if (!identical(source, program) &&
          (!program.classes.toSet().containsAll(source.classes) ||
              !program.globals.toSet().containsAll(source.globals) ||
              [...source.functions, ...source.externals].any(
                (body) =>
                    !identical(program.implementationOf(body.target), body),
              ))) {
        throw ArgumentError('Member selection requires unchanged source IR.');
      }
    }
  }

  final _instances = {
    ...instantiatedTypes,
    for (final target in definitions)
      ...?program.implementationOf(target)?.instantiatedClasses,
    if (records != null && records.shapes.isNotEmpty) records.type,
  };
  final _builtins = <(ValueType, bool), IrFunction>{};

  Iterable<IrFunction> get functions => _builtins.values;

  FunctionTarget builtin(
    ValueType type, {
    required bool hash,
  }) => _builtins.putIfAbsent((type, hash), () {
    final target = FunctionTarget(
      null,
      '${type.dartName}.${hash ? 'hash' : 'equals'}',
      hash ? .integer : .boolean,
      [type, if (!hash) .object.nullable],
    );
    final entry = Block(target.parameterTypes);
    if (hash) {
      entry.finish(Return(entry.emit(ObjectHashCode(entry.parameters.first))));
      return IrFunction(target, [entry]);
    }
    final blocks = [entry];
    var current = entry;
    for (final other
        in type == .boolean
            ? [ValueType.boolean]
            : FfiTypes.isPointer(type)
            ? [FfiTypes.pointerRuntimeType]
            : [ValueType.integer, ValueType.floating]) {
      final yes = Block([other]), no = Block();
      blocks.addAll([yes, no]);
      final test = current.emit(TypeTest(entry.parameters[1], other));
      current.finish(
        Branch(test, Jump(yes, [test.refinement(true)!]), Jump(no)),
      );
      yes.finish(
        Return(yes.emit(Equals(entry.parameters.first, yes.parameters.single))),
      );
      current = no;
    }
    current.finish(const Return(Constant.boolean(false)));
    return IrFunction(target, blocks);
  }).target;

  Iterable<DynamicDispatch> get dynamicCalls sync* {
    for (final target in definitions) {
      final body = program.implementationOf(target);
      if (body is! IrFunction) continue;
      for (final block in body.blocks) {
        yield* block.instructions.whereType<DynamicDispatch>();
        if (block.end case Invoke(operation: final DynamicDispatch call)) {
          yield call;
        }
      }
    }
  }

  Map<ClassType, FunctionTarget> dynamicTargets(
    DynamicDispatch call, {
    TypeValues? types,
  }) => {
    for (final type in _receivers(call.receiver.unviewedType))
      if ((callTypes?.allows(call.receiver, type) ?? true) &&
          program.classes.any((declaration) => declaration.type == type))
        type:
            ?(type == records?.declaration?.type && types != null
                ? records!.getter(call.selector, types)
                : null) ??
            program.lookupMember(type, call.selector).target ??
            (call.selector.kind == .setter
                ? null
                : program.lookupMember(type, (
                    kind: call.selector.kind == .getter
                        ? FunctionKind.method
                        : FunctionKind.getter,
                    name: call.selector.name,
                    privateScope: call.selector.privateScope,
                  )).target),
  };

  Set<FunctionTarget> get tearOffTargets => {
    for (final call in dynamicCalls)
      if (call.selector.kind == .getter)
        for (final target in dynamicTargets(call).values)
          if (target.kind == .method) target,

    for (final target in definitions)
      for (final tearOff
          in program.implementationOf(target)?.methodTearOffs ??
              const <
                ({ValueType receiver, FunctionTarget method, bool direct})
              >{})
        if (tearOff.direct)
          tearOff.method
        else
          ...targetsFor(tearOff.receiver, tearOff.method.selector).values,
  };

  Iterable<ClassType> _receivers(ValueType receiver) =>
      _instances.where(receiver.mayHaveInstance);

  Map<ClassType, FunctionTarget> targetsFor(
    ValueType receiver,
    MemberSelector selector, {
    bool hasBuiltin = false,
    Value? receiverValue,
  }) {
    final targets = <ClassType, FunctionTarget>{};
    for (final type in _receivers(receiver)) {
      if (receiverValue != null &&
          !(callTypes?.allows(receiverValue, type) ?? true)) {
        continue;
      }
      if (hasBuiltin &&
          (type == FfiTypes.pointer ||
              type == ValueType.string ||
              type == ValueType.integer ||
              type == ValueType.floating ||
              type == ValueType.boolean)) {
        continue;
      }
      final lookup = program.lookupMember(type, selector);
      if (lookup.target case final target?) {
        if (hasBuiltin && target.owner == ValueType.object) continue;
        // String content operations enter through the backend support closure.
        if (program.implementationOf(target) == null &&
            !(hasBuiltin && target.owner == ValueType.string)) {
          throw ArgumentError(
            'Missing member definition: ${type.dartName}.${target.name} '
            '(receiver ${receiver.dartName}).',
          );
        }
        targets[type] = target;
      } else if (!hasBuiltin ||
          lookup.unmodeledBoundary != null ||
          lookup.unsupportedForwarder) {
        throw UnsupportedError(
          'Native member unavailable: ${type.dartName}.${selector.name}',
        );
      }
    }
    // No constructed receiver means this call cannot execute in the closed program.
    return targets;
  }
}
