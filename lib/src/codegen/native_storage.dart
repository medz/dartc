import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Managed ownership of FFI views; native bytes are never traced as Dart fields.
final class NativeStorage(final NativeLayout layout) {
  final buffer = ClassType(null, '_NativeBytes');
  final _views = <ClassType, NativeViewStorage>{};
  final _copies = <(ClassType, bool), IrFunction>{};

  NativeViewStorage view(ClassType type) =>
      _views.putIfAbsent(type, () => NativeViewStorage(type));
  Iterable<IrClass> get classes => [
    IrClass(buffer, []),
    for (final view in _views.values) view.declaration,
  ];
  Iterable<IrFunction> get functions => [
    for (final view in _views.values) view.function,
    ..._copies.values,
  ];

  FunctionTarget owned(
    ClassType type,
    FunctionTarget allocate, {
    required bool copy,
  }) => _copies.putIfAbsent((type, copy), () {
    final view = this.view(type);
    final target = FunctionTarget(
      null,
      'native${copy ? 'Copy' : 'Create'}',
      type,
      [.integer, .object.nullable],
    );
    final entry = Block(target.parameterTypes);
    final backing = entry.emit(
      DirectCall(allocate, [
        Constant.integer(layout.of(type.nativeType!).size),
      ]),
    );
    final address = entry.emit(
      IntBinary(
        .add,
        entry.emit(ReferenceAddress(backing)),
        const Constant.integer(ObjectHeader.fieldsOffset),
      ),
    );
    if (copy) {
      entry.emit(CopyNative(address, entry.parameters.first, type.nativeType!));
    }
    final result = entry.emit(Construct(view.initializer, [address, backing]));
    entry.emit(KeepAlive(entry.parameters.last));
    entry.finish(Return(result));
    return IrFunction(target, [entry]);
  }).target;
}

final class NativeViewStorage(final ClassType type) {
  late final address = InstanceField(
    type,
    '_nativeAddress',
    .integer,
    isFinal: true,
  );
  late final owner = InstanceField(
    type,
    '_nativeOwner',
    .object.nullable,
    isFinal: true,
  );
  late final initializer = FunctionTarget(
    null,
    'nativeView',
    .voidType,
    [.integer, .object.nullable],
    owner: type,
    kind: .initializer,
  );
  late final declaration = IrClass(
    type,
    [address, owner],
    constructors: [initializer],
  );
  late final function = _initialize();

  IrFunction _initialize() {
    final entry = Block(initializer.parameterTypes);
    entry.emit(StoreField(address, entry.parameters[0], entry.parameters[1]));
    entry.emit(StoreField(owner, entry.parameters[0], entry.parameters[2]));
    entry.finish(const Return());
    return IrFunction(initializer, [entry]);
  }
}
