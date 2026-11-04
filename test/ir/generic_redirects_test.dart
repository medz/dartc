import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final library = Uri.parse('package:example/redirects.dart');

  test('redirect signatures substitute destination type variables', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final u = TypeParameterType('U')
      ..initializeBound(ValueType.object.nullable);
    final source = ClassType(
      library,
      'Source',
      typeParameters: [t],
      isAbstract: true,
    );
    final destination = ClassType(
      library,
      'Destination',
      typeParameters: [u],
      interfaces: [
        source.instantiate([u]),
      ],
    );
    final ctor = FunctionTarget(
      library,
      '',
      .voidType,
      [u],
      owner: destination,
      kind: .initializer,
    );
    final redirect = FunctionTarget(
      library,
      '',
      source,
      [t],
      owner: source,
      kind: .factory,
      redirect: ctor,
      redirectOwnerType: destination.instantiate([t]),
    );
    final resolved = redirect.resolveConstruction(
      source.instantiate([ValueType.string]),
    );
    expect(resolved.target, same(ctor));
    expect(resolved.ownerType, destination.instantiate([ValueType.string]));
    expect(redirect.implementation, same(ctor));
    expect(
      () => FunctionTarget(
        library,
        'wrong',
        source,
        [ValueType.integer],
        owner: source,
        kind: .factory,
        redirect: ctor,
        redirectOwnerType: destination.instantiate([t]),
      ),
      throwsArgumentError,
    );
    expect(
      () => redirect.resolveConstruction(
        destination.instantiate([ValueType.string]),
      ),
      throwsArgumentError,
    );
  });

  test('destination bounds are checked after redirect substitution', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final u = TypeParameterType('U')..initializeBound(ValueType.number);
    final source = ClassType(
      library,
      'Source',
      typeParameters: [t],
      isAbstract: true,
    );
    final destination = ClassType(
      library,
      'Destination',
      typeParameters: [u],
      interfaces: [
        source.instantiate([u]),
      ],
    );
    final ctor = FunctionTarget(
      library,
      '',
      .voidType,
      [],
      owner: destination,
      kind: .initializer,
    );
    final redirect = FunctionTarget(
      library,
      '',
      source,
      [],
      owner: source,
      kind: .factory,
      redirect: ctor,
      redirectOwnerType: destination.instantiate([t]),
    );
    expect(
      () =>
          redirect.resolveConstruction(source.instantiate([ValueType.string])),
      throwsArgumentError,
    );
    expect(
      redirect
          .resolveConstruction(source.instantiate([ValueType.integer]))
          .ownerType,
      destination.instantiate([ValueType.integer]),
    );
  });

  test('a redirect owner requires a matching destination declaration', () {
    final source = ClassType(library, 'Source', isAbstract: true);
    final destination = ClassType(library, 'Destination', interfaces: [source]);
    final ctor = FunctionTarget(
      library,
      '',
      .voidType,
      [],
      owner: destination,
      kind: .initializer,
    );
    expect(
      () => FunctionTarget(
        library,
        '',
        source,
        [],
        owner: source,
        kind: .factory,
        redirectOwnerType: destination,
      ),
      throwsArgumentError,
    );
    expect(
      () => FunctionTarget(
        library,
        '',
        source,
        [],
        owner: source,
        kind: .factory,
        redirect: ctor,
        redirectOwnerType: source,
      ),
      throwsArgumentError,
    );
  });
}
