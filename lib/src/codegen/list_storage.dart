import 'package:dartc/ir.dart';

/// Permitted List changes encoded in constant storage.
enum ListMutability() {
  immutable,
  fixed,
  growable,
}

/// Binds List storage and construction to checked SDK declarations.
final class ListStorage(Iterable<IrClass> classes) {
  final _classes = classes.toList();
  late final declaration = _storage();
  IrClass _storage() {
    final storage = _classes.singleWhere(
      (type) => type.listStorage != null,
      orElse: () => throw ArgumentError('Lists require checked SDK storage.'),
    );
    if (!_classes.any(
      (type) =>
          type.type == storage.listStorage!.data.type && type.referencePayload,
    )) {
      throw ArgumentError('List elements require traced payload storage.');
    }
    return storage;
  }

  ClassType get type => declaration.type;
  ClassType get buffer => data.type as ClassType;
  InstanceField get length => declaration.listStorage!.length;
  InstanceField get data => declaration.listStorage!.data;
  InstanceField get mutability => declaration.listStorage!.mutability;

  FunctionTarget? callFor(Instruction operation) {
    if (operation case CollectionSpread(isMethodCall: false, :final collection)
        when CoreTypes.view(collection.type, CoreTypes.list) != null) {
      return declaration.listStorage!.spread;
    }
    final name = switch (operation) {
      NewCollection(:final collectionType)
          when collectionType.declaration == CoreTypes.list =>
        'empty',
      ListFilled() => 'filled',
      ListFrom() => 'from',
      _ => null,
    };
    return name == null
        ? null
        : _classes
              .singleWhere(
                (c) => c.type == CoreTypes.list,
                orElse: () =>
                    throw ArgumentError('Lists require checked SDK factories.'),
              )
              .constructors[name]!;
  }
}
