import 'contracts.dart';

/// The type descriptor shared by generated code and Dart runtime algorithms.
@TypeStorage(0)
final class TypeInfo(
  final int kind,
  final int shape,
  final bool allowsNull,
  final TypeArguments? parts,
  final FunctionInfo? signature,
  final String className,
) implements Type {
  @Primitive(.typeView)
  external static TypeInfo of(Type value);

  @override
  String toString() => _text(const []);

  String _text(List<String> variables) {
    final arguments = <TypeInfo>[];
    for (var node = parts; node != null; node = node.tail) {
      arguments.add(node.head);
    }
    String text(TypeInfo type) => type._text(variables);
    switch (TypeKind.values[kind]) {
      case .nominal:
        return arguments.isEmpty
            ? className
            : '$className<${arguments.map(text).join(', ')}>';
      case .nullable:
        final base = arguments.single;
        return base.kind == TypeKind.function.index
            ? '(${text(base)})?'
            : '${text(base)}?';
      case .futureOr:
        return 'FutureOr<${text(arguments.single)}>';
      case .parameter:
        return variables[shape];
      case .dynamicType:
        return 'dynamic';
      case .voidType:
        return 'void';
      case .never:
        return 'Never';
      case .nullType:
        return 'Null';
      case .record:
      case .function:
        final info = signature!;
        final parameters = [
          for (var i = 0; i < info.binders; i++) 'X${variables.length + i}',
        ];
        final scope = [...parameters, ...variables];
        final children = arguments.map((type) => type._text(scope)).toList();
        final record = kind == TypeKind.record.index;
        final offset = record ? 0 : info.binders + 1;
        final positional = children.sublist(offset, offset + info.positional);
        final entries = <String>[];
        if (info.required < positional.length) {
          entries.addAll(positional.take(info.required));
          entries.add('[${positional.skip(info.required).join(', ')}]');
        } else {
          entries.addAll(positional);
        }
        final named = <String>[];
        for (var node = info.named; node != null; node = node.next) {
          named.add(
            '${node.required ? 'required ' : ''}${children[node.slot]} ${node.text}',
          );
        }
        if (named.isNotEmpty) entries.add('{${named.join(', ')}}');
        final argumentsText = entries.join(', ');
        if (record) {
          return '($argumentsText${positional.length == 1 && named.isEmpty ? ',' : ''})';
        }
        final bounds = <String>[];
        for (var i = 0; i < parameters.length; i++) {
          bounds.add(
            children[i] == 'Object?'
                ? parameters[i]
                : '${parameters[i]} extends ${children[i]}',
          );
        }
        return '${children[info.binders]} Function${bounds.isEmpty ? '' : '<${bounds.join(', ')}>'}($argumentsText)';
    }
  }
}

/// Ordered child types without a dependency on managed List storage.
@TypeStorage(1)
final class TypeArguments(final TypeInfo head, final TypeArguments? tail);

/// Function or record parameter names and positional boundaries.
@TypeStorage(2)
final class FunctionInfo(
  final int binders,
  final int positional,
  final int required,
  final NamedParameter? named,
);

/// One named field or parameter in canonical name order.
@TypeStorage(3)
final class NamedParameter(
  final int name,
  final int slot,
  final bool required,
  final NamedParameter? next,
  final String text,
);
