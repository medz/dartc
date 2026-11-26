import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'captures.dart';
import 'closure.dart';
import 'conversions.dart';
import 'coroutine.dart';
import 'environment.dart';
import 'scope.dart';
import 'types.dart';

/// Translates `async` functions and generators.
///
/// What such a function does is a function of its own, which the runtime calls
/// each time that it can go on.
final class CoroutineTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  late final _conversions = Conversions(_scope, _builder);

  /// Lets the function return what does [body], as [declared], with
  /// [parameters].
  void start(
    FunctionBody body,
    CoroutineKind kind,
    DartType declared,
    List<FormalParameterElement> parameters,
  ) {
    final type = _valueTypeOf(kind, declared);
    final types =
        _scope.typeList(_builder, [type]) ??
        (throw _builder.unit.unsupported(body, 'a result of type $declared'));
    final made = switch (kind) {
      .syncStar => _starter(body, type, parameters),
      _ => _create(_builder, body, kind, type, const []),
    };
    final name = switch (kind) {
      .async => 'startAsync',
      .asyncStar => 'startAsyncStar',
      .syncStar => 'startSyncStar',
    };
    final result = _builder.call(HirCall(_scope.runtime(name), [types, made]))!;
    _builder.end(
      HirReturn(_conversions.coerce(result, _builder.function.result!)),
    );
  }

  /// The type of the values that a function which is declared to return
  /// [declared] gives.
  DartType _valueTypeOf(CoroutineKind kind, DartType declared) {
    final types = _conversions.types;
    final owner = switch (kind) {
      .async => null,
      .asyncStar => types.streamElement,
      .syncStar => types.iterableElement,
    };
    if (owner == null) {
      return _builder.library.typeSystem.futureValueType(declared);
    }
    final bound = boundOf(declared);
    final found = bound.isDartAsyncFutureOr
        ? boundOf((bound as InterfaceType).typeArguments.single)
        : bound;
    return found is InterfaceType
        ? found.asInstanceOf(owner)?.typeArguments.single ?? types.dynamicType
        : types.dynamicType;
  }

  /// A function without parameters that creates what does [body], each time
  /// anew.
  HirValue _starter(
    FunctionBody body,
    DartType type,
    List<FormalParameterElement> parameters,
  ) {
    final environment = _environmentOf(_builder, body);
    final class_ = HirClass('starter of ${_builder.function.name}', null, [
      ...environment.fields,
    ]);
    final function = HirFunction('start ${_builder.function.name}', const [
      .reference,
    ], .reference);
    _addClosure(class_, function, 'Starter');
    _scope.schedule(() {
      final builder = environment.build(function, const []);
      final made = _create(builder, body, .syncStar, type, parameters);
      builder
        ..end(HirReturn(made))
        ..finish();
    });
    final object = _builder.create(class_);
    environment.store(object);
    return object;
  }

  Environment _environmentOf(FunctionBuilder builder, FunctionBody body) =>
      Environment.of(builder, body, _scope.capturesOf(declarationOf(body)));

  /// Makes objects of [class_] functions that do what [function] does, as the
  /// runtime says [type] does.
  void _addClosure(HirClass class_, HirFunction function, String type) {
    final found = _scope.runtimeFunctionType(type);
    _scope
      ..addLocalFunction(function)
      ..addClosure(
        Closure(
          class_,
          found.formalParameters,
          () => function,
          (_, self) => [self],
          typeValue: (builder) => _scope.typeValue(builder, found)!,
        ),
      );
  }

  /// An object that does [body], whose [own] variables it does not share.
  HirValue _create(
    FunctionBuilder outer,
    FunctionBody body,
    CoroutineKind kind,
    DartType type,
    List<FormalParameterElement> own,
  ) {
    final name = outer.function.name;
    final environment = _environmentOf(outer, body);
    final state = HirField('state', .integer);
    final frame = HirField('frame', .reference);
    final class_ = HirClass('body of $name', null, [
      ...environment.fields,
      state,
      frame,
    ]);
    final function = HirFunction('$name.body', [
      .reference,
      for (final _ in _scope.runtimeFunctionType('Body').formalParameters)
        .reference,
    ], .reference);
    _addClosure(class_, function, 'Body');
    _scope.schedule(() {
      final suspend = HirFunction('suspend', const [.reference], .reference);
      final types = _conversions.types;
      final builder = environment.build(
        function,
        const [],
        returnType: switch (kind) {
          .async => types.futureOrType(type),
          _ => type,
        },
      );
      builder
        ..coroutine = Coroutine(kind, suspend, builder.inputs[1])
        ..frameName = outer.frameName;
      for (final parameter in own) {
        if (builder.typeOf(parameter) != null) builder.renew(parameter);
      }
      _scope.translateBody(
        builder,
        body,
        HirCoroutine(suspend: suspend, state: state, frame: frame),
      );
    });
    final object = outer.create(class_);
    environment.store(object);
    outer.add(HirStore(state, object, outer.add(HirConst(0))));
    return object;
  }
}
