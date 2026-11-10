import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

/// Selects the IR operation for a resolved SDK core member.
Instruction? lowerCoreMember(
  ExecutableElement member,
  Value receiver,
  List<Value> arguments,
) {
  if (!member.library.isDartCore || member.isStatic) return null;
  if (member.name == 'remainder' &&
      arguments.length == 1 &&
      ['num', 'int', 'double'].any(
        (name) =>
            member.baseElement ==
            member.library.getClass(name)?.getMethod('remainder'),
      )) {
    final right = arguments.single;
    return receiver.type == .integer && right.type == .integer
        ? IntBinary(.remainder, receiver, right)
        : NumericBinary(.remainder, receiver, right);
  }
  if (member.baseElement ==
          member.library.getClass('num')?.getMethod('toDouble') &&
      arguments.isEmpty) {
    return NumericToDouble(receiver);
  }
  return switch ((member.enclosingElement?.name, member.name, arguments)) {
    ('MapEntry', 'key', []) => LoadField(CoreTypes.mapEntryKey, receiver),
    ('MapEntry', 'value', []) => LoadField(CoreTypes.mapEntryValue, receiver),
    ('Iterable' || 'List' || 'Set' || 'Map', 'length', []) => CollectionLength(
      receiver,
    ),
    ('List', 'sublist', [final start]) => ListSublist(receiver, start),
    ('List', 'sublist', [final start, final end]) => ListSublist(
      receiver,
      start,
      end,
    ),
    ('Map', 'containsKey', [final key]) => MapContainsKey(receiver, key),
    ('Map', 'entries', []) => MapEntries(receiver),
    ('Iterable' || 'List' || 'Set', 'iterator', []) => GetIterator(receiver),
    ('Iterator', 'current', []) => IteratorCurrent(receiver),
    ('Iterator', 'moveNext', []) => IteratorMoveNext(receiver),
    ('List' || 'Map', '[]', [final key]) => CollectionGet(receiver, key),
    ('List', '[]=', [final key, final value]) => ListSet(receiver, key, value),
    ('Map', '[]=', [final key, final value]) => MapPut(receiver, key, value),
    ('List' || 'Set', 'add', [final value]) => CollectionAdd(receiver, value),
    ('List' || 'Set' || 'Map', 'addAll', [final source]) => CollectionSpread(
      receiver,
      source,
      isMethodCall: true,
    ),
    _ => null,
  };
}

/// Resolves only the public SDK enum protocols, not user members of the same name.
InstanceField? coreEnumField(ExecutableElement? member) {
  if (member is! GetterElement || !member.library.isDartCore) return null;
  return switch ((member.enclosingElement, member.name)) {
    (ClassElement(name: 'Enum'), 'index') => CoreTypes.enumIndex,
    (ExtensionElement(name: 'EnumName'), 'name') => CoreTypes.enumName,
    _ => null,
  };
}

/// Identifies SDK runtimeType getters without intercepting user overrides.
bool coreRuntimeType(ExecutableElement? member) =>
    member is GetterElement &&
    member.library.isDartCore &&
    (member.enclosingElement.name == 'Object' ||
        member.enclosingElement.name == 'Record') &&
    member.name == 'runtimeType';

/// Whether this SDK member has a supported runtime-backed virtual protocol.
///
/// Keep these public protocols virtual: user implementations need not carry
/// the SDK implementation's storage, and subclasses may inherit or override
/// their concrete getters.
bool coreRuntimeMember(ExecutableElement member) {
  if (!member.library.isDartCore || member.isStatic) return false;
  return switch ((member, member.enclosingElement?.name, member.name)) {
    (GetterElement(), 'Symbol', 'hashCode') => true,
    (
      GetterElement(),
      'Invocation',
      'memberName' ||
          'typeArguments' ||
          'positionalArguments' ||
          'namedArguments' ||
          'isMethod' ||
          'isGetter' ||
          'isSetter' ||
          'isAccessor',
    ) =>
      true,
    (MethodElement(), 'Object', 'toString') => true,
    _ => false,
  };
}
