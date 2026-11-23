import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'conversions.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

typedef _Shape = ({int positional, List<String> named});

/// All functions that are values, and the calls of such.
///
/// A call gives and gets objects, whatever the types of the function are. Its
/// selector says how many arguments it has and how they are named.
final class ClosureTable(
  final ProgramScope _scope,
  final SourceUnit _unit,

  /// Makes the function of a constructor that creates the object, too.
  final HirFunction Function(ConstructorElement element) _creatorOf,
) {
  final closures = <Closure>[];
  final _shapes = <HirSelector, _Shape>{};
  final _selectors = <String, HirSelector>{};
  final _entries = <HirSelector, Map<HirClass, HirFunction>>{};
  final _static = <ExecutableElement, Closure>{};
  final _tearOffs = <ExecutableElement, Closure>{};

  /// Functions made here.
  final List<HirFunction> made = [];

  HirTypeTest? _anyFunction;

  /// Whether objects are functions.
  HirTypeTest get anyFunction => _anyFunction ??= HirTypeTest('Function');

  /// The classes that pass each test.
  Map<HirTypeTest, Set<HirClass>> get tests => {
    ?_anyFunction: {for (final closure in closures) closure.class_},
  };

  void add(Closure closure) => closures.add(closure);

  /// The selector of calls with arguments of a shape; names are sorted.
  HirSelector selectorOf(int positional, List<String> named) {
    final name = 'call $positional ${named.join(' ')}'.trimRight();
    return _selectors[name] ??= () {
      final made = HirSelector(
        name,
        List.filled(positional + named.length, .reference),
        .reference,
      );
      _shapes[made] = (positional: positional, named: named);
      _entries[made] = {};
      return made;
    }();
  }

  Map<HirSelector, Map<HirClass, HirFunction>> get dispatch => _entries;

  /// Adds the entries found since the last time. Returns whether there were any.
  bool update() {
    var found = false;
    for (final MapEntry(key: selector, value: shape)
        in _shapes.entries.toList()) {
      for (final closure in closures.toList()) {
        if (!_accepts(closure, shape)) continue;
        if (_entries[selector]!.containsKey(closure.class_)) continue;
        _entries[selector]![closure.class_] = _entry(closure, selector, shape);
        found = true;
      }
    }
    return found;
  }

  static bool _accepts(Closure closure, _Shape shape) {
    final positional = closure.parameters.where((p) => p.isPositional);
    final named = {
      for (final parameter in closure.parameters)
        if (parameter.isNamed) parameter.name,
    };
    return shape.positional <= positional.length &&
        shape.positional >= positional.where((p) => p.isRequired).length &&
        named.containsAll(shape.named) &&
        closure.parameters.every(
          (p) => !p.isRequiredNamed || shape.named.contains(p.name),
        );
  }

  HirFunction _entry(Closure closure, HirSelector selector, _Shape shape) {
    final function = HirFunction('${selector.name} of ${closure.class_.name}', [
      .reference,
      ...selector.parameters,
    ], selector.result);
    final builder = FunctionBuilder(_unit, function, const []);
    final conversions = Conversions(_scope, builder);
    var position = 0;
    HirValue argument(FormalParameterElement parameter) {
      final at = parameter.isNamed
          ? shape.named.indexOf(parameter.name!) + shape.positional
          : position++;
      final isGiven = parameter.isNamed
          ? at >= shape.positional
          : at < shape.positional;
      if (!isGiven) return builder.add(_scope.defaultOf(parameter));
      final value = builder.inputs[at + 1], type = parameter.type;
      if (!closure.isTearOff || !isUnchecked(parameter)) {
        return conversions.coerce(value, valueType(type)!);
      }
      return conversions.cast(
            value,
            conversions.types.objectQuestionType,
            type,
            ending: " of '${parameter.name}'",
          ) ??
          (throw StateError('No test for $type.'));
    }

    final target = closure.target();
    final leading = closure.leading(builder, builder.inputs.first);
    if (closure.isTearOff) builder.setReceiver(leading.first);
    final result = builder.call(
      HirCall(target, [
        ...leading,
        for (final parameter in closure.parameters) argument(parameter),
      ]),
    );
    final given = result ?? builder.add(HirNull());
    builder
      ..end(HirReturn(conversions.coerce(given, .reference)))
      ..finish();
    made.add(function);
    return function;
  }

  /// The class of the function or constructor [element], which needs no other
  /// object, as a value.
  ///
  /// One that is generic has a field for its type arguments.
  Closure static(ExecutableElement element) => _static[element] ??= () {
    final owner = takesTypes(element);
    final types = owner == null ? null : HirField('types', .reference);
    final made = Closure(
      HirClass(element.displayName, null, [?types]),
      element.type,
      element.formalParameters,
      () => element is ConstructorElement
          ? _creatorOf(element)
          : _scope.functionOf(element)!,
      (builder, self) => [if (types != null) builder.add(HirLoad(types, self))],
      typeValue: (builder) {
        if (owner != null) {
          builder.bindTypes(
            owner,
            builder.add(HirLoad(types!, builder.inputs.single)),
          );
        }
        return _scope.typeValue(builder, _withoutParameters(element.type))!;
      },
    );
    add(made);
    return made;
  }();

  /// The object that [element] is with the type arguments [types].
  HirConstObject constant(ExecutableElement element, HirConstObject? types) {
    final class_ = static(element).class_;
    return _constants['${class_.hashCode} ${types.hashCode}'] ??=
        HirConstObject(class_, {
          for (final field in class_.fields) field: types,
        });
  }

  final _constants = <String, HirConstObject>{};

  /// [type] with the parameters it takes itself left free.
  static FunctionType _withoutParameters(FunctionType type) =>
      type.typeParameters.isEmpty
      ? type
      : type.instantiate([
          for (final parameter in type.typeParameters)
            parameter.instantiate(nullabilitySuffix: .none),
        ]);

  /// Gives the method [element] of [receiver], however it is overridden.
  HirValue tearOff(
    FunctionBuilder builder,
    ExecutableElement element,
    HirValue receiver,
  ) {
    final closure = _tearOffs[element] ??= () {
      final field = HirField('receiver', .reference);
      final made = Closure(
        HirClass('tear-off ${element.displayName}', null, [field]),
        element.type,
        element.formalParameters,
        () => _scope.memberOf(element),
        (builder, self) => [builder.add(HirLoad(field, self))],
        typeValue: (builder) {
          builder.setReceiver(
            builder.add(HirLoad(field, builder.inputs.single)),
          );
          return _scope.methodType(builder, element)!;
        },
        isTearOff: true,
      );
      add(made);
      return made;
    }();
    final object = builder.create(closure.class_);
    builder.add(HirStore(closure.class_.fields.single, object, receiver));
    return object;
  }

  /// How functions compare themselves, in place of `Object`'s [equals].
  Map<HirClass, HirFunction> equalities(
    HirSelector selector,
    HirFunction equals,
  ) => {
    for (final closure in closures)
      closure.class_: closure.isTearOff
          ? _equalities[closure] ??= _tearOffEquals(closure, selector)
          : equals,
  };

  final _equalities = <Closure, HirFunction>{};

  HirFunction _tearOffEquals(Closure closure, HirSelector selector) {
    final function = HirFunction('== of ${closure.class_.name}', [
      .reference,
      .reference,
    ], .boolean);
    final builder = FunctionBuilder(_unit, function, const []);
    final test = HirTypeTest(closure.class_.name);
    exact[test] = {closure.class_};
    final [self, other] = builder.inputs;
    final field = closure.class_.fields.single;
    HirValue receiver(HirValue object) => builder.add(HirLoad(field, object));
    final result = builder.choose(
      builder.add(HirIsInstance(test, other)),
      .boolean,
      () => builder.add(HirCompare(.equal, receiver(self), receiver(other))),
      () => builder.add(HirConst(false)),
    );
    builder
      ..end(HirReturn(result))
      ..finish();
    made.add(function);
    return function;
  }

  /// Tests for single classes.
  final exact = <HirTypeTest, Set<HirClass>>{};
}
