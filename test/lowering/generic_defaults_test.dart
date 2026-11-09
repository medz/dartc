import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:dartc/src/lowering/analyzer_metadata.dart';
import 'package:dartc/src/lowering/bindings.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/generic_defaults.dart' as sdk;

void main() {
  late IrProgram program;
  late FunctionType structuralMethod;
  late bool structuralDefaultAbsent;
  setUpAll(() async {
    await AnalysisSession([
      'test/lowering/fixtures/generic_defaults.dart',
    ]).use((input) {
      final unit = input.libraries.single.units.single;
      final declaration = unit.unit.declarations
          .whereType<ast.FunctionDeclaration>()
          .singleWhere((node) => node.name.lexeme == 'methodTearoff');
      final body =
          declaration.functionExpression.body as ast.ExpressionFunctionBody;
      final type = body.expression.staticType! as dart.FunctionType;
      structuralDefaultAbsent =
          typeParameterDefault(type.typeParameters.single) == null;
      structuralMethod = Bindings().valueType(type, unit, body) as FunctionType;
      program = Lowering().lower(input).program;
    });
  });

  FunctionTarget target(String name) => program.functions
      .singleWhere((function) => function.target.name == name)
      .target;
  FunctionType signature(String name) => target(name).signature;
  FunctionConstant constructor(String name) {
    final function = program.functions.singleWhere(
      (function) => function.target.name == name,
    );
    return (function.blocks.single.end as Return).value! as FunctionConstant;
  }

  String defaultNames(FunctionType type) =>
      type.defaultTypeArguments.map((argument) => argument.dartName).join('|');

  test('implicit and explicit nullable bounds keep distinct SDK defaults', () {
    for (final (name, function) in <(String, dynamic)>[
      ('implicitBound', sdk.implicitBound),
      ('explicitNullableBound', sdk.explicitNullableBound),
      ('numBound', sdk.numBound),
    ]) {
      expect(defaultNames(signature(name)), function(), reason: name);
      expect(signature(name).instantiateToBounds().typeParameters, isEmpty);
    }
    expect(
      signature('implicitBound').typeParameters.single.bound,
      ValueType.object.nullable,
    );
    expect(
      signature('explicitNullableBound').typeParameters.single.bound,
      ValueType.object.nullable,
    );
    expect(signature('implicitBound').defaultTypeArguments, [
      ValueType.dynamicType,
    ]);
    expect(signature('explicitNullableBound').defaultTypeArguments, [
      ValueType.object.nullable,
    ]);
  });

  test(
    'dependent and reordered defaults use the recorded closed templates',
    () {
      for (final (name, function) in <(String, dynamic)>[
        ('dependentBounds', sdk.dependentBounds),
        ('reorderedBounds', sdk.reorderedBounds),
      ]) {
        final type = signature(name);
        expect(defaultNames(type), function(), reason: name);
        expect(type.instantiateToBounds().typeParameters, isEmpty);
        expect(
          type.defaultTypeArguments.expand((t) => t.freeTypeParameters),
          isEmpty,
        );
      }
      final dependent = signature('dependentBounds').typeParameters;
      expect(
        (dependent[1].bound as ClassType).typeArguments.single,
        same(dependent[0]),
      );
      final reordered = signature('reorderedBounds').typeParameters;
      expect(
        (reordered[0].bound as ClassType).typeArguments.single,
        same(reordered[1]),
      );
    },
  );

  test('recursive defaults are recorded without eager bound validation', () {
    for (final (name, expected, function) in <(String, String, dynamic)>[
      ('recursiveBound', 'RecursiveBound<dynamic>', sdk.recursiveBound),
      ('contravariantBound', 'void Function(Never)', sdk.contravariantBound),
      ('mixedBound', 'dynamic Function(Never)', sdk.mixedBound),
    ]) {
      final type = signature(name);
      expect(defaultNames(type), expected, reason: name);
      // The metadata API reports an invalid application as ArgumentError. The
      // SDK oracle is a guest dynamic call and must instead raise TypeError.
      expect(type.instantiateToBounds, throwsArgumentError, reason: name);
      expect(() => function(), throwsA(isA<TypeError>()), reason: name);
    }
  });

  test(
    'method defaults retain owner parameters and substitute the receiver',
    () {
      final method = target('method');
      final owner = method.owner!;
      expect(
        method.typeParameters.single.defaultType,
        same(owner.typeParameters.single),
      );
      final applied = method.signatureFor(
        owner.instantiate([ValueType.integer]),
      );
      expect(
        applied.typeParameters.single,
        isNot(same(method.typeParameters.single)),
      );
      expect(applied.defaultTypeArguments, [ValueType.integer]);
      final dynamic oracle = sdk.DefaultOwner<int>().method;
      expect('int|${defaultNames(applied)}', oracle());
      expect(applied.instantiateToBounds().typeParameters, isEmpty);
    },
  );

  test('local and anonymous defaults retain the captured owner template', () {
    final owner = target('method').owner!;
    for (final (name, function) in <(String, dynamic)>[
      ('localDefault', sdk.DefaultOwner<int>().local()),
      ('<anonymous>', sdk.DefaultOwner<int>().anonymous()),
    ]) {
      final type = signature(name);
      expect(
        type.typeParameters.single.defaultType,
        same(owner.typeParameters.single),
      );
      final applied = type.substitute({
        owner.typeParameters.single: ValueType.integer,
      }) as FunctionType;
      expect(applied.defaultTypeArguments, [ValueType.integer]);
      expect('int|${defaultNames(applied)}', function(), reason: name);
    }
  });

  test('nested defaults retain enclosing generic and owner environments', () {
    final nested = target('nested');
    final local = target('nestedDefault');
    final ownerParameter = nested.owner!.typeParameters.single;
    final enclosingParameter = nested.typeParameters.single;
    expect(enclosingParameter.defaultType, same(ownerParameter));
    expect(local.typeParameters.single.defaultType, same(enclosingParameter));
    final applied = local.signature.substitute({
      ownerParameter: ValueType.integer,
      enclosingParameter: ValueType.integer,
    }) as FunctionType;
    expect(applied.defaultTypeArguments, [ValueType.integer]);
    final dynamic outer = sdk.DefaultOwner<int>().nested;
    final dynamic inner = outer();
    expect('int|int|${defaultNames(applied)}', inner());
  });

  test('constructor aliases use their own defaults and owner mapping', () {
    for (final (name, expected, function) in <(String, String, dynamic)>[
      ('constructorTearoff', 'num', sdk.DefaultConstruct.new),
      ('aliasTearoff', 'int', sdk.DefaultAlias.new),
      ('listAliasTearoff', 'num', sdk.DefaultListAlias.new),
      ('constantConstructorTearoff', 'num', sdk.savedConstructor),
      ('constantAliasTearoff', 'int', sdk.savedAlias),
      ('constantListAliasTearoff', 'num', sdk.savedListAlias),
    ]) {
      final value = constructor(name);
      final type = value.type as FunctionType;
      expect(defaultNames(type), expected, reason: name);
      expect(
        type.instantiateToBounds().result.dartName,
        function().runtimeType.toString(),
        reason: name,
      );
    }
    final alias = constructor('aliasTearoff');
    expect(
      alias.target.owner!.typeParameters.single.defaultType,
      ValueType.number,
    );
    expect(
      (alias.type as FunctionType).typeParameters.single.defaultType,
      ValueType.integer,
    );
    final listAlias = constructor('listAliasTearoff');
    expect(
      listAlias.target.owner!.typeParameters.single.defaultType,
      ValueType.dynamicType,
    );
    expect(
      (listAlias.type as FunctionType).typeParameters.single.defaultType,
      ValueType.number,
    );
  });

  test('MapEntry constructor tearoffs retain shared core dynamic defaults', () {
    final dynamic oracle = MapEntry.new;
    for (final name in ['mapEntryTearoff', 'constantMapEntryTearoff']) {
      final value = constructor(name);
      final type = value.type as FunctionType;
      expect(type.defaultTypeArguments, [
        ValueType.dynamicType,
        ValueType.dynamicType,
      ]);
      expect(
        type.instantiateToBounds().result.dartName,
        oracle('key', 1).runtimeType.toString(),
      );
      expect(
        type.instantiate([ValueType.string, ValueType.integer]).result.dartName,
        oracle<String, int>('key', 1).runtimeType.toString(),
      );
      expect(value.target.owner!.typeParameters.map((p) => p.defaultType), [
        ValueType.dynamicType,
        ValueType.dynamicType,
      ]);
    }
  });

  test(
    'lossy structural defaults fail only when omitted arguments are needed',
    () {
      expect(structuralDefaultAbsent, isTrue);
      expect(structuralMethod.typeParameters.single.defaultType, isNull);
      expect(structuralMethod.typeParameters.single.bound, ValueType.integer);
      expect(() => structuralMethod.defaultTypeArguments, throwsStateError);
      expect(structuralMethod.instantiateToBounds, throwsStateError);
      final explicit = structuralMethod.instantiate([ValueType.integer]);
      expect(explicit.typeParameters, isEmpty);
      final method = target('method');
      final declarationType = method.signatureFor(
        method.owner!.instantiate([ValueType.integer]),
      );
      expect(structuralMethod, declarationType);
      expect(structuralMethod.hashCode, declarationType.hashCode);
      expect(structuralMethod.accepts(declarationType), isTrue);
      expect(declarationType.accepts(structuralMethod), isTrue);
    },
  );

  test('unsupported analyzer binder implementations fail clearly', () {
    expect(
      () => typeParameterDefault(_ForeignTypeParameter()),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('type parameter default metadata unavailable'),
        ),
      ),
    );
  });

  test('explicit applications retain their existing behavior', () {
    final function = program.functions.singleWhere(
      (function) => function.target.name == 'explicitApplications',
    );
    expect(
      IrInterpreter(program, {}).run(function, []),
      sdk.explicitApplications(),
    );
    expect(
      signature('numBound').instantiate([ValueType.integer]).typeParameters,
      isEmpty,
    );
    expect(
      () => signature('numBound').instantiate([ValueType.string]),
      throwsArgumentError,
    );
    final dynamic oracle = sdk.numBound;
    expect(oracle<int>(), 'int');
    expect(() => oracle<String>(), throwsA(isA<TypeError>()));
  });
}

class _ForeignTypeParameter() implements TypeParameterElement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
