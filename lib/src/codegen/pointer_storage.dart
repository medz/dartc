import 'package:dartc/ir.dart';

/// Stores a Dart pointer's address in an untraced field of a managed object.
final class PointerStorage() {
  final address = InstanceField(
    FfiTypes.pointer,
    'address',
    .integer,
    isFinal: true,
  );
  final initializer = FunctionTarget(
    null,
    'new',
    .voidType,
    [.integer],
    owner: FfiTypes.pointer,
    kind: .initializer,
  );

  late final declaration = IrClass(
    FfiTypes.pointer,
    [address],
    constructors: [initializer],
  );

  late final function = _initialize();

  IrFunction _initialize() {
    final entry = Block(initializer.parameterTypes);
    entry.emit(StoreField(address, entry.parameters[0], entry.parameters[1]));
    entry.finish(const Return());
    return IrFunction(initializer, [entry]);
  }
}
