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

typedef _Shape = ({int types, int positional, List<String> named});

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
  HirSelector selectorOf(int types, int positional, List<String> named) {
    final generic = types == 0 ? '' : '<$types> ';
    final name = 'call $generic$positional ${named.join(' ')}'.trimRight();
    return _selectors[name] ??= () {
      final made = HirSelector(name, [
        if (types > 0) HirType.reference,
        for (var i = positional + named.length; i > 0; i--) HirType.reference,
      ], .reference);
      _shapes[made] = (types: types, positional: positional, named: named);
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
        if (closure.typeParameters.length != shape.types ||
            !accepts(closure.parameters, shape.positional, shape.named)) {
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
    final [self, ...given] = builder.inputs;
    final types = shape.types > 0 ? given.removeAt(0) : null;
    if (closure.forward case final forward?) {
      builder.end(
        HirReturn(forward(builder, self, given, shape.positional, shape.named)),
      );
      builder.finish();
      made.add(function);
      return function;
    }
    var position = 0;
    HirValue argument(FormalParameterElement parameter) {
      final at = parameter.isNamed
          ? shape.named.indexOf(parameter.name!) + shape.positional
          : position++;
      final isGiven = parameter.isNamed
          ? at >= shape.positional
          : at < shape.positional;
      if (!isGiven) return builder.add(_scope.defaultOf(parameter));
      final value = given[at], type = parameter.type;
      if (!closure.isTearOff || !isUnchecked(parameter)) {
        return conversions.coerce(value, valueType(type)!);
      }
      return conversions.cast(
            value,
            conversions.types.objectQuestionType,
            type,
            ending: " of '${closure.nameOf(parameter)}'",
          ) ??
          (throw StateError('No test for $type.'));
    }

    final target = closure.target();
    final leading = closure.leading(builder, self);
    if (closure.isTearOff) closure.bindTypes(builder, self);
    if (types != null) {
      builder.bindTypes(closure.typeParameters.first.enclosingElement!, types);
    }
    final result = builder.call(
      HirCall(target, [
        ...leading,
        ?types,
        for (final parameter in closure.parameters) argument(parameter),
      ]),
    );
    final value = result ?? builder.add(HirNull());
    builder
      ..end(HirReturn(conversions.coerce(value, .reference)))
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
    final types = owner == null
        ? null
        : HirField('types', .reference, isFinal: true);
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
      name: _qualified(element),
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

  /// The object that the generic function [element] is.
  HirConstObject generic(ExecutableElement element) =>
      _constants['generic ${element.hashCode}'] ??= () {
        final made = Closure(
          HirClass(element.displayName, null, []),
          element.type,
          element.formalParameters,
          () => _scope.functionOf(element)!,
          (_, _) => const [],
          typeParameters: element.typeParameters,
          typeValue: (builder) => _scope.typeValue(builder, element.type)!,
          name: _qualified(element),
          text: " from Function '${_nameOf(element)}': static.",
        );
        add(made);
        return HirConstObject(made.class_, const {});
      }();

  final _extensionTearOffs = <MethodElement, Closure>{};

  /// Gives the method [element] of an extension, used on [receiver], which has
  /// the type arguments [types], if any.
  HirValue extensionTearOff(
    FunctionBuilder builder,
    MethodElement element,
    HirValue receiver,
    HirValue? types,
  ) {
    final closure = _extensionTearOffs[element] ??= _extension(
      element,
      receiver.type!,
    );
    final [own, ...lists] = closure.class_.fields;
    final object = builder.create(closure.class_);
    builder.add(HirStore(own, object, receiver));
    for (final list in lists) {
      builder.add(HirStore(list, object, types!));
    }
    return object;
  }

  Closure _extension(MethodElement element, HirType type) {
    final owner = takesExtensionTypes(element);
    final receiver = HirField('this', type, isFinal: true);
    final types = owner == null
        ? null
        : HirField('types', .reference, isFinal: true);
    void bind(FunctionBuilder builder, HirValue self) {
      if (owner == null) return;
      builder.bindTypes(owner, builder.add(HirLoad(types!, self)));
    }

    final made = Closure(
      HirClass('tear-off ${element.displayName}', null, [receiver, ?types]),
      element.type,
      element.formalParameters,
      () => _scope.functionOf(element)!,
      (builder, self) => [
        for (final field in [receiver, ?types])
          builder.add(HirLoad(field, self)),
      ],
      bind: bind,
      typeValue: (builder) {
        bind(builder, builder.inputs.single);
        return _scope.typeValue(builder, element.type)!;
      },
      typeParameters: element.typeParameters,
      name: _qualified(element),
    );
    add(made);
    return made;
  }

  final _partials = <String, Closure>{};

  /// The generic [function] with a list of types and their number, which then
  /// is of [type].
  HirValue partial(
    FunctionBuilder builder,
    HirValue function,
    (HirValue, int) types,
    FunctionType type,
  ) {
    final (typeList, count) = types;
    final key = '$count ${describeType(type)}';
    final closure = _partials[key] ??= _partial(type, count);
    final [inner, list, own] = closure.class_.fields;
    final object = builder.create(closure.class_);
    final value = _scope.typeValue(builder, type)!;
    builder
      ..add(HirStore(inner, object, function))
      ..add(HirStore(list, object, typeList))
      ..add(HirStore(own, object, value));
    return object;
  }

  Closure _partial(FunctionType type, int count) {
    final inner = HirField('function', .reference, isFinal: true);
    final list = HirField('types', .reference, isFinal: true);
    final own = HirField('type', .reference, isFinal: true);
    final made = Closure(
      HirClass('part of ${describeType(type)}', null, [inner, list, own]),
      type,
      type.formalParameters,
      () => throw StateError('It has no target.'),
      (_, _) => const [],
      forward: (builder, self, arguments, positional, named) => builder.call(
        HirVirtualCall(
          _scope.callSelector(count, positional, named),
          builder.add(HirLoad(inner, self)),
          [builder.add(HirLoad(list, self)), ...arguments],
        ),
      )!,
      typeValue: (builder) => builder.add(HirLoad(own, builder.inputs.single)),
    );
    add(made);
    return made;
  }

  static String _qualified(ExecutableElement element) {
    if (element is ConstructorElement) {
      final class_ = element.enclosingElement.displayName;
      return element.name == 'new' ? '$class_.$class_' : _nameOf(element);
    }
    final owner = element.enclosingElement;
    return owner is InstanceElement
        ? '${owner.displayName}.${element.displayName}'
        : element.displayName;
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
    HirValue receiver, {
    required bool isForwarder,
  }) {
    final (:element, :level) = found;
    final closure = _tearOffs[found] ??= () {
      final field = HirField('receiver', .reference, isFinal: true);
      final made = Closure(
        HirClass('tear-off ${element.displayName}', null, [field]),
        element.type,
        element.formalParameters,
        () => isForwarder
            ? _scope.forwarderOf(level, element)
            : _scope.memberOf(level, element),
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
        typeParameters: element.typeParameters,
        name: _qualified(element),
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
