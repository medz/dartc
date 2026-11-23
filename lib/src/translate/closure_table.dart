import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'conversions.dart';
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
  final _static = <ExecutableElement, HirConstObject>{};
  final _tearOffs = <ExecutableElement, Closure>{};
  final _tests = <FunctionType, HirTypeTest>{};

  /// Functions made here.
  final List<HirFunction> made = [];

  HirTypeTest? _anyFunction;

  /// Whether objects are functions.
  HirTypeTest get anyFunction => _anyFunction ??= HirTypeTest('Function');

  /// The classes that pass each test.
  Map<HirTypeTest, Set<HirClass>> get tests => {
    ?_anyFunction: {for (final closure in closures) closure.class_},
    for (final MapEntry(key: type, value: test) in _tests.entries)
      test: {
        for (final closure in closures)
          if (_unit.ast.declaredFragment!.element.library.typeSystem
              .isSubtypeOf(closure.type, type))
            closure.class_,
      },
  };

  /// Whether objects are functions of [type].
  HirTypeTest testOf(FunctionType type) =>
      _tests[type] ??= HirTypeTest(type.getDisplayString());

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
      return isGiven
          ? conversions.coerce(
              builder.inputs[at + 1],
              valueType(parameter.type)!,
            )
          : builder.add(_scope.defaultOf(parameter));
    }

    final target = closure.target();
    final result = builder.call(
      HirCall(target, [
        ...closure.leading(builder, builder.inputs.first),
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

  /// The object that the function or constructor [element], which needs no
  /// other object, is.
  HirConstObject static(ExecutableElement element) => _static[element] ??= () {
    final class_ = HirClass(element.displayName, null, const []);
    add(
      Closure(
        class_,
        element.type,
        element.formalParameters,
        () => element is ConstructorElement
            ? _creatorOf(element)
            : _scope.functionOf(element)!,
        (_, _) => const [],
      ),
    );
    return HirConstObject(class_, const {});
  }();

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
