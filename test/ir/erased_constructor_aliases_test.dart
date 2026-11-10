import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final library = Uri.parse('memory:erased-aliases');
  final t = TypeParameterType('T')..initializeBound(ValueType.number);
  final target = FunctionTarget(
    library,
    'construct',
    t,
    [t],
    typeParameters: [t],
  );

  test('erased aliases retain a checked argument mapping without a body', () {
    final x = TypeParameterType('X')..initializeBound(ValueType.number);
    final signature = FunctionType(x, [x], typeParameters: [x]);
    final arguments = <ValueType>[x];
    final alias = FunctionConstant(
      target,
      constructorSignature: signature,
      constructorAlias: (library, 'Alias'),
      constructorTypeArguments: arguments,
    );
    arguments.clear();
    expect(alias.constructorTypeArguments, [x]);
    expect(
      () => alias.constructorTypeArguments!.clear(),
      throwsUnsupportedError,
    );
    expect(
      InstantiateFunction(alias, [ValueType.integer]).type,
      FunctionType(ValueType.integer, [ValueType.integer]),
    );
    final caller = FunctionTarget(library, 'f', alias.type, []);
    final function = IrFunction(caller, [Block([])..finish(Return(alias))]);
    final output = StringBuffer();
    function.writeTo(output);
    expect(
      output.toString(),
      contains('=> memory:erased-aliases::construct<X>'),
    );
    expect(() => x.initializeDefaultType(ValueType.integer), throwsStateError);
  });

  test(
    'erased aliases reject missing identity, wrong arity, bounds and signature',
    () {
      final x = TypeParameterType('X')..initializeBound(ValueType.number);
      final signature = FunctionType(x, [x], typeParameters: [x]);
      expect(
        () => FunctionConstant(target, constructorTypeArguments: [x]),
        throwsArgumentError,
      );
      for (final arguments in <List<ValueType>>[
        [],
        [ValueType.string],
        [x, x],
      ]) {
        expect(
          () => FunctionConstant(
            target,
            constructorSignature: signature,
            constructorAlias: (library, 'Invalid'),
            constructorTypeArguments: arguments,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => FunctionConstant(
          target,
          constructorSignature: FunctionType(
            ValueType.integer,
            [x],
            typeParameters: [x],
          ),
          constructorAlias: (library, 'Invalid'),
          constructorTypeArguments: [x],
        ),
        throwsArgumentError,
      );
    },
  );

  test('unused target arguments cannot introduce free types in constants', () {
    final phantom = FunctionTarget(
      library,
      'phantom',
      ValueType.integer,
      [],
      typeParameters: [t],
    );
    final x = TypeParameterType('X')..initializeBound(ValueType.number);
    final foreign = TypeParameterType('Foreign')
      ..initializeBound(ValueType.number);
    expect(
      () => FunctionConstant(
        phantom,
        constructorSignature: FunctionType(
          ValueType.integer,
          [],
          typeParameters: [x],
        ),
        constructorAlias: (library, 'Phantom'),
        constructorTypeArguments: [foreign],
      ),
      throwsArgumentError,
    );
  });
}
