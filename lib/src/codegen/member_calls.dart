import 'package:dartc/ir.dart';

/// Resolves native member entries for the concrete classes in a compilation.
final class MemberCalls(
  final IrProgram program,
  final Set<FunctionTarget> definitions, {
  Iterable<ClassType> instantiatedTypes = const [],
}) {
  final _instances = {
    ...instantiatedTypes,
    for (final target in definitions)
      ...?program.implementationOf(target)?.instantiatedClasses,
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

  Set<FunctionTarget> get tearOffTargets => {
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

  Map<ClassType, FunctionTarget> targetsFor(
    ValueType receiver,
    MemberSelector selector, {
    bool hasBuiltin = false,
  }) {
    final targets = <ClassType, FunctionTarget>{};
    for (final type in _instances) {
      if (hasBuiltin &&
          (type == FfiTypes.pointer ||
              type == ValueType.string ||
              type == ValueType.integer ||
              type == ValueType.floating ||
              type == ValueType.boolean)) {
        continue;
      }
      if (receiver.classBound case final owner?
          when type.asInstanceOf(owner.declaration) == null) {
        continue;
      }
      if (receiver.freeTypeParameters.isEmpty &&
          type.freeTypeParameters.isEmpty &&
          !receiver.accepts(type)) {
        continue;
      }
      final lookup = program.lookupMember(type, selector);
      if (lookup.target case final target?) {
        if (hasBuiltin && target.owner == ValueType.object) continue;
        if (!definitions.contains(target)) {
          throw ArgumentError('Missing member definition: ${target.name}');
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
