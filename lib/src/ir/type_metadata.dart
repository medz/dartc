import 'signature.dart';
import 'type.dart';

/// Canonical storage read by the Dart implementation of reified types.
abstract final class TypeMetadata() {
  static final type = ClassType(
    null,
    '_Type',
    interfaces: [ValueType.typeType],
  );
  static final list = ClassType(null, '_TypeArguments');
  static final functionShape = ClassType(null, '_FunctionShape');
  static final namedParameter = ClassType(null, '_NamedParameter');
  static final signature = InstanceField(
    type,
    'signature',
    functionShape.nullable,
    isFinal: true,
  );
  static final binderCount = InstanceField(
    functionShape,
    'binders',
    .integer,
    isFinal: true,
  );
  static final positionalCount = InstanceField(
    functionShape,
    'positional',
    .integer,
    isFinal: true,
  );
  static final requiredCount = InstanceField(
    functionShape,
    'required',
    .integer,
    isFinal: true,
  );
  static final named = InstanceField(
    functionShape,
    'named',
    namedParameter.nullable,
    isFinal: true,
  );
  static final name = InstanceField(
    namedParameter,
    'name',
    .integer,
    isFinal: true,
  );
  static final nameSlot = InstanceField(
    namedParameter,
    'slot',
    .integer,
    isFinal: true,
  );
  static final requiredName = InstanceField(
    namedParameter,
    'required',
    .boolean,
    isFinal: true,
  );
  static final nextName = InstanceField(
    namedParameter,
    'next',
    namedParameter.nullable,
    isFinal: true,
  );
  static final nameText = InstanceField(
    namedParameter,
    'text',
    .string,
    isFinal: true,
  );
  static final kind = InstanceField(type, 'kind', .integer, isFinal: true);
  static final shape = InstanceField(type, 'shape', .integer, isFinal: true);
  static final className = InstanceField(
    type,
    'className',
    .string,
    isFinal: true,
  );
  static final allowsNull = InstanceField(
    type,
    'allowsNull',
    .boolean,
    isFinal: true,
  );
  static final parts = InstanceField(
    type,
    'parts',
    list.nullable,
    isFinal: true,
  );
  static final head = InstanceField(list, 'head', type, isFinal: true);
  static final tail = InstanceField(list, 'tail', list.nullable, isFinal: true);

  static final Map<ClassType, List<InstanceField>> fields = .unmodifiable(
    <ClassType, List<InstanceField>>{
      type: .unmodifiable([
        kind,
        shape,
        allowsNull,
        parts,
        signature,
        className,
      ]),
      list: .unmodifiable([head, tail]),
      functionShape: .unmodifiable([
        binderCount,
        positionalCount,
        requiredCount,
        named,
      ]),
      namedParameter: .unmodifiable([
        name,
        nameSlot,
        requiredName,
        nextName,
        nameText,
      ]),
    },
  );
}
