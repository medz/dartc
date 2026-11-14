import 'package:dartc/ir.dart';

/// Binds constant List layout to checked SDK storage declarations.
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
}
