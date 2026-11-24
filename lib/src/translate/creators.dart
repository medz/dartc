import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'conversions.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

/// What is [given] to a redirecting factory, by the parameters that it is
/// passed on to.
Map<FormalParameterElement, HirValue> redirected(
  Map<FormalParameterElement, HirValue> given,
) => {
  for (final MapEntry(:key, :value) in given.entries)
    redirectedParameter(key)!: value,
};

/// Functions that create objects, as values of the program do.
final class CreatorTable(final ProgramScope _scope, final SourceUnit _unit) {
  final _functions = <ConstructorElement, HirFunction>{};

  Iterable<HirFunction> get functions => _functions.values;

  /// A function taking the type arguments and parameters of [element].
  HirFunction of(ConstructorElement element) {
    if (redirectionOf(element) case final target?) {
      return _functions[element] ??= _redirect(element, target);
    }
    if (!isInitializerElement(element)) return _scope.factoryOf(element);
    return _functions[element] ??= _generative(element);
  }

  HirFunction _generative(ConstructorElement element) {
    final initializer = _scope.initializerOf(element);
    final class_ = element.enclosingElement;
    final function = HirFunction(
      'create ${initializer.name}',
      initializer.parameters.skip(1),
      .reference,
    );
    final builder = FunctionBuilder(_unit, function, const []);
    final object = builder.create(_scope.createdClass(class_));
    builder
      ..call(HirCall(initializer, [object, ...builder.inputs]))
      ..end(HirReturn(object))
      ..finish();
    return function;
  }

  HirFunction _redirect(ConstructorElement element, ConstructorElement target) {
    final owner = takesTypes(element);
    final function = HirFunction('redirect ${element.displayName}', [
      if (owner != null) .reference,
      for (final parameter in element.formalParameters)
        valueType(parameter.type)!,
    ], valueType(element.returnType));
    final builder = FunctionBuilder(
      _unit,
      function,
      element.formalParameters,
      typeOwners: [?owner],
    );
    final conversions = Conversions(_scope, builder);
    final given = redirected({
      for (final parameter in element.formalParameters)
        parameter: builder.read(parameter),
    });
    final types = target.returnType.typeArguments;
    final base = target.baseElement, creator = of(base);
    final result = conversions.call(creator, [
      if (types.isNotEmpty) _scope.typeList(builder, types)!,
      for (final parameter in base.formalParameters)
        given[parameter] ?? builder.add(_scope.defaultOf(parameter)),
    ]);
    builder
      ..end(HirReturn(conversions.coerce(result!, function.result!)))
      ..finish();
    return function;
  }
}
