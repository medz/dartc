import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'conversions.dart';
import 'dynamic_table.dart';
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
  final _tearOffs = <Implementation, Closure>{};

  /// Functions made here.
  final List<HirFunction> made = [];

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
        if (!accepts(closure.parameters, shape.positional, shape.named)) {
          continue;
        }
        if (_entries[selector]!.containsKey(closure.class_)) continue;
        _entries[selector]![closure.class_] = _entry(closure, selector, shape);
        found = true;
      }
    }
    return found;
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
    if (closure.isTearOff) closure.bindTypes(builder, builder.inputs.first);
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
      bind: (builder, self) {
        if (owner != null) {
          builder.bindTypes(owner, builder.add(HirLoad(types!, self)));
        }
      },
      typeValue: (builder) {
        if (owner != null) {
          builder.bindTypes(
            owner,
            builder.add(HirLoad(types!, builder.inputs.single)),
          );
        }
        return _scope.typeValue(builder, _withoutParameters(element.type))!;
      },
      text: " from Function '${_nameOf(element)}': static.",
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

  static String _nameOf(ExecutableElement element) {
    if (element is! ConstructorElement) return element.displayName;
    final name = element.name == 'new' ? '' : element.name;
    return '${element.enclosingElement.displayName}.$name';
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

  /// Gives the method [found] of [receiver], however it is overridden.
  HirValue tearOff(
    FunctionBuilder builder,
    Implementation found,
    HirValue receiver,
  ) {
    final (:element, :level) = found;
    final closure = _tearOffs[found] ??= () {
      final field = HirField('receiver', .reference);
      final made = Closure(
        HirClass('tear-off ${element.displayName}', null, [field]),
        element.type,
        element.formalParameters,
        () => _scope.memberOf(level, element),
        (builder, self) => [builder.add(HirLoad(field, self))],
        bind: (builder, self) {
          builder.setReceiver(builder.add(HirLoad(field, self)), level);
        },
        typeValue: (builder) {
          builder.setReceiver(
            builder.add(HirLoad(field, builder.inputs.single)),
            level,
          );
          return _scope.methodType(builder, element)!;
        },
        text: " from Function '${element.displayName}':.",
        isTearOff: true,
      );
      add(made);
      return made;
    }();
    final object = builder.create(closure.class_);
    builder.add(HirStore(closure.class_.fields.single, object, receiver));
    return object;
  }
}
