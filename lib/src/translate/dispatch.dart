import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:dartc/world.dart';

import 'builder.dart';
import 'classes.dart';
import 'closure_table.dart';
import 'conversions.dart';
import 'forwarders.dart' show viewedAt;
import 'levels.dart';
import 'members.dart';
import 'native_types.dart' show nativeAnnotation;
import 'scope.dart';
import 'types.dart';

/// A member and the arguments its calls give.
typedef _Shape = ({
  ExecutableElement member,
  int positional,
  List<String> named,

  /// Whether the receiver is the object that the calling code is of.
  bool isOwn,
});

/// Finds which functions calls on objects can reach.
final class DispatchBuilder(
  final ProgramScope _scope,
  final Declarations _declarations,
  final SourceUnit _unit,
) {
  final _tearOffs = <HirSelector>{};
  final _world = World<InterfaceElement, HirSelector>(isSubclass);
  final _selectors = <String, HirSelector>{};
  final _shapes = <HirSelector, _Shape>{};
  final _entries = <HirSelector, Map<InterfaceElement, HirFunction>>{};
  final _adapters = <(Implementation, HirSelector, String), HirFunction>{};

  /// Functions made here rather than declared by the program.
  final List<HirFunction> made = [];

  List<InterfaceElement> get classes => _world.classes.cast();

  void instantiate(InterfaceElement class_) => _world.instantiate(class_);

  HirSelector selectorOf(
    ExecutableElement member,
    InterfaceElement receiver,
    int positional,
    List<String> named,
    Reject reject, {
    required bool isOwn,
  }) {
    final selector = _selector(
      member,
      positional,
      named,
      reject,
      // Others need no function of their own.
      isOwn: isOwn && member.formalParameters.any(isUnchecked),
    );
    _world.call(selector, receiver);
    return selector;
  }

  HirSelector _selector(
    ExecutableElement member,
    int positional,
    List<String> named,
    Reject reject, {
    bool isOwn = false,
  }) {
    final isGeneric = member.typeParameters.isNotEmpty;
    final types = [
      if (isGeneric) HirType.reference,
      for (final parameter in _given(member, positional, named))
        valueType(parameter.type) ??
            reject('a parameter of type ${parameter.type}'),
    ];
    final result = _result(member, reject);
    final kind = switch (member) {
      GetterElement() => 'get ',
      SetterElement() => 'set ',
      _ => '',
    };
    final name = '$kind${member.displayName}';
    final owner = member.isPrivate ? member.library.uri : '';
    final key = [
      name,
      member.lookupName,
      owner,
      named,
      isGeneric,
      types,
      result,
      isOwn,
    ].join('|');
    return _selectors.putIfAbsent(key, () {
      final made = HirSelector(name, types, result);
      _shapes[made] = (
        member: member,
        positional: positional,
        named: named,
        isOwn: isOwn,
      );
      _entries[made] = {};
      return made;
    });
  }

  /// What [level] has for [member], or null if it is abstract there.
  HirFunction? functionAt(
    Level level,
    ExecutableElement member,
    int positional,
    List<String> named,
    Reject reject, {
    bool isUnboxed = false,
    bool orForwarder = false,
  }) {
    final found = implementationIn(level, member);
    if (found == null && !orForwarder) return null;
    final selector = _selector(member, positional, named, reject);
    return found == null
        ? _forwarder(level, member, selector)
        : _function(level, found, selector, isUnboxed: isUnboxed);
  }

  /// How to get the method [member] of objects of [receiver].
  HirSelector tearOffSelector(
    ExecutableElement member,
    InterfaceElement receiver,
  ) {
    final owner = member.isPrivate ? member.library.uri : '';
    final key = 'tear-off|${member.lookupName}|$owner';
    final selector = _selectors.putIfAbsent(key, () {
      final made = HirSelector(
        'tear-off ${member.displayName}',
        const [],
        .reference,
      );
      _shapes[made] = (
        member: member,
        positional: 0,
        named: const [],
        isOwn: false,
      );
      _entries[made] = {};
      _tearOffs.add(made);
      return made;
    });
    _world.call(selector, receiver);
    return selector;
  }

  HirType _result(ExecutableElement member, Reject reject) =>
      valueType(member.returnType) ??
      reject('a result of type ${member.returnType}');

  /// The parameters of [member] that calls of a shape give, in their order.
  static List<FormalParameterElement> _given(
    ExecutableElement member,
    int positional,
    List<String> named,
  ) {
    final all = member.formalParameters;
    return [
      ...all.where((parameter) => parameter.isPositional).take(positional),
      for (final name in named)
        all.firstWhere(
          (parameter) => parameter.isNamed && parameter.name == name,
        ),
    ];
  }

  /// Adds the entries found since the last time. Returns whether there were any.
  bool update() {
    final entries = _world.takeEntries();
    for (final (found, selector) in entries) {
      final class_ = found;
      _entries[selector]![class_] = _entry(class_, selector);
    }
    return entries.isNotEmpty;
  }

  /// The class of objects of [element], if there are any.
  HirClass? created(
    InterfaceElement element,
    HirClass Function(InterfaceElement element) classOf,
  ) => classes.contains(element) ? classOf(element) : null;

  /// The classes that most objects are of, where they may be of many.
  static const _common = [
    '_GrowableList', '_List', '_OneByteString', '_Mint', '_Double', //
    '_Map', '_Set', 'ListIterator', '_ArrayIterator',
  ];
  static const _commonObjects = ['_OneByteString', '_Mint'];

  /// The classes that objects receiving calls of each selector often are of.
  Map<HirSelector, List<HirClass>> likely(
    HirClass Function(InterfaceElement element) classOf,
  ) {
    final common = {
      for (final class_ in classes)
        if (class_.library.isInSdk && _common.contains(class_.name))
          class_.name!: class_,
    };
    return {
      for (final MapEntry(key: selector, value: entries) in _entries.entries)
        if (_shapes[selector]!.member.enclosingElement case final owner?)
          selector: [
            for (final name
                in owner is ClassElement && owner.isDartCoreObject
                    ? _commonObjects
                    : _common)
              if (common[name] case final class_?
                  when entries.containsKey(class_))
                classOf(class_),
          ],
    };
  }

  Map<HirSelector, Map<HirClass, HirFunction>> result(
    HirClass Function(InterfaceElement element) classOf,
    ClosureTable closures,
    InterfaceElement functionClass,
  ) => {
    for (final MapEntry(key: selector, value: entries) in _entries.entries)
      selector: {
        for (final MapEntry(:key, :value) in entries.entries)
          classOf(key): value,
        // Functions have the members of one class.
        if (entries[functionClass] case final function?)
          for (final closure in closures.closures) closure.class_: function,
      },
  };

  HirFunction _entry(InterfaceElement class_, HirSelector selector) {
    final level = _scope.levelOf(class_);
    final shape = _shapes[selector]!;
    final own = implementationIn(level, shape.member);
    // Members that are not there are forwarded.
    final found =
        own ?? (element: declaredFor(class_, shape.member), level: level);
    if (_tearOffs.contains(selector)) {
      return _make(selector.name, selector, found.level, (builder, _) {
        final receiver = builder.inputs.first;
        return _scope.tearOff(
          builder,
          found,
          receiver,
          isForwarder: own == null,
        );
      });
    }
    return own == null
        ? _forwarder(level, found.element, selector)
        : _function(level, found, selector);
  }

  /// What calls the `noSuchMethod` of objects of [level] for [member], which
  /// they have.
  HirFunction _forwarder(
    Level level,
    ExecutableElement member,
    HirSelector selector,
  ) {
    final shape = _shapes[selector]!;
    return _adapt(
      (element: member, level: level),
      selector,
      shape,
      _checkedParameters(level.class_, member, shape),
      isUnboxed: false,
      isForwarder: true,
    );
  }

  /// What does the work of [found] for objects whose class is at [level].
  HirFunction _function(
    Level level,
    Implementation found,
    HirSelector selector, {
    bool isUnboxed = false,
  }) {
    final element = found.element;
    final shape = _shapes[selector]!;
    final isMissingSetter = switch (variableOfAccessor(element)) {
      final FieldElement field when element is SetterElement =>
        isExternalVariable(field) &&
            !field.library.isInSdk &&
            nativeAnnotation(field) == null,
      _ => false,
    };
    // Missing setters keep explicit covariance checks even when an own call
    // shares a selector with a call through a wider interface.
    final checked =
        isMissingSetter && !_isCovariantSetter(level.class_, element)
        ? const <int>[]
        : _checkedParameters(
            level.class_,
            element,
            shape,
            checksOwnCall: isMissingSetter,
          );
    final key = (found, selector, '$checked $isUnboxed');
    return _adapters[key] ??= isMissingSetter
        ? _missingSetter(found, selector, checked.isNotEmpty)
        : _adapt(found, selector, shape, checked, isUnboxed: isUnboxed);
  }

  /// Whether the setter is marked `covariant` here or in a supertype.
  static bool _isCovariantSetter(
    InterfaceElement class_,
    ExecutableElement setter,
  ) =>
      setter.formalParameters.single.isCovariant ||
      overriddenBy(
        class_,
        setter,
      ).any((other) => other.formalParameters.single.isCovariant);

  HirFunction _missingSetter(
    Implementation found,
    HirSelector selector,
    bool isChecked,
  ) {
    final (:element, :level) = found;
    final target = _scope.memberOf(level, element);
    final type = target.parameters[1];
    if (!isChecked && selector.parameters.single == type) return target;
    return _make('adapt ${target.name}', selector, level, (
      builder,
      conversions,
    ) {
      final [receiver, given] = builder.inputs;
      // The stub ignores the argument after any required type check.
      final parameterType = element.formalParameters.single.type;
      final value = isChecked
          ? conversions.cast(
                  given,
                  conversions.types.objectQuestionType,
                  parameterType,
                  ending: " of '#externalFieldValue'",
                ) ??
                (throw _declarations.unsupported(
                  element,
                  'testing for $parameterType',
                ))
          : builder.placeholder(type);
      return builder.call(HirCall(target, [receiver, value]));
    });
  }

  /// The places of parameters that calls may give values of other types, as
  /// they rely on the types that overridden members declare.
  List<int> _checkedParameters(
    InterfaceElement class_,
    ExecutableElement found,
    _Shape shape, {
    bool checksOwnCall = false,
  }) {
    final system = found.library.typeSystem;
    final parameters = found.formalParameters;
    final checked = <int>{};
    for (final other in overriddenBy(class_, found)) {
      for (final declared in other.formalParameters) {
        final place = declared.isNamed
            ? parameters.indexWhere((p) => p.isNamed && p.name == declared.name)
            : other.formalParameters.indexOf(declared);
        // What overrides [found] may take more.
        if (place < 0 || place >= parameters.length) continue;
        if (!system.isSubtypeOf(declared.type, parameters[place].type)) {
          checked.add(place);
        }
      }
    }
    // Objects with other type arguments may be used as having these.
    for (final (i, parameter) in parameters.indexed) {
      if (mentions(parameter.type, found.enclosingElement)) checked.add(i);
    }
    if (shape.isOwn && !checksOwnCall) {
      // Code of the object itself knows its type arguments.
      checked.removeWhere((i) => _isGiven(class_, found, shape.member, i));
    }
    return checked.toList()..sort();
  }

  /// Whether what is given for [member] fits the parameter of [found] at [place],
  /// for objects of [class_].
  static bool _isGiven(
    InterfaceElement class_,
    ExecutableElement found,
    ExecutableElement member,
    int place,
  ) {
    List<FormalParameterElement>? of(ExecutableElement element) {
      final owner = element.enclosingElement;
      if (owner is! InterfaceElement) return null;
      final type = class_.thisType.asInstanceOf(owner);
      return <ExecutableElement>[...?type?.methods, ...?type?.setters]
          .where((own) => own.baseElement == element)
          .firstOrNull
          ?.formalParameters;
    }

    final own = of(found), given = of(member);
    if (own == null || given == null) return false;
    final parameter = own[place];
    final source = parameter.isNamed
        ? given.where((p) => p.isNamed && p.name == parameter.name).firstOrNull
        : given.elementAtOrNull(place);
    return source == null ||
        found.library.typeSystem.isSubtypeOf(source.type, parameter.type);
  }

  /// A function called as [selector] says that does the work of
  /// [implementation], after checking some parameters.
  HirFunction _adapt(
    Implementation implementation,
    HirSelector selector,
    _Shape shape,
    List<int> checked, {
    required bool isUnboxed,
    bool isForwarder = false,
  }) {
    final (element: found, :level) = implementation;
    final field = isForwarder ? null : fieldOfAccessor(found);
    final isGeneric = found.typeParameters.isNotEmpty;
    final given = _given(found, shape.positional, shape.named);
    final parameters = found.formalParameters;
    // What is not implemented here is declared by a supertype.
    final viewed = isForwarder ? viewedAt(level, found) : found;
    HirValue argument(
      FunctionBuilder builder,
      Conversions conversions,
      FormalParameterElement parameter,
    ) {
      final at = given.indexOf(parameter);
      if (at < 0) return builder.add(_scope.defaultOf(parameter));
      final value = builder.inputs[at + (isGeneric ? 2 : 1)];
      final place = parameters.indexOf(parameter);
      final type = viewed.formalParameters[place].type;
      if (!checked.contains(place)) {
        return conversions.coerce(value, valueType(parameter.type)!);
      }
      return conversions.cast(
            value,
            conversions.types.objectQuestionType,
            type,
            ending: " of '${parameter.name}'",
          ) ??
          (throw _declarations.unsupported(found, 'testing for $type'));
    }

    if (field != null) {
      return _make(selector.name, selector, level, (builder, conversions) {
        final receiver = builder.inputs.first;
        if (found is GetterElement) {
          return _scope.loadField(builder, level, field, receiver);
        }
        final value = argument(builder, conversions, parameters.single);
        _scope.storeField(builder, level, field, receiver, value);
        return null;
      });
    }
    final target = isForwarder
        ? _scope.forwarderOf(level, found)
        : _scope.memberOf(level, found);
    // Objects with other type arguments may be used as having these.
    final isBound =
        !shape.isOwn &&
        found.typeParameters.any(
          (parameter) => switch (parameter.bound) {
            final bound? => mentions(bound, found.enclosingElement),
            null => false,
          },
        );
    final isSame =
        checked.isEmpty &&
        !isBound &&
        (isUnboxed || target.parameters.first == .reference) &&
        given.length == parameters.length &&
        given.indexed.every((e) => e.$2 == parameters[e.$1]) &&
        given.indexed.every(
          (e) =>
              valueType(e.$2.type) ==
              selector.parameters[e.$1 + (isGeneric ? 1 : 0)],
        ) &&
        target.result == selector.result;
    if (isSame) return target;
    return _make('adapt ${target.name}', selector, level, (
      builder,
      conversions,
    ) {
      if (isGeneric) {
        builder
          ..bindTypes(found, builder.inputs[1])
          ..bindParameters(viewed.typeParameters, builder.inputs[1]);
      }
      if (isBound) {
        conversions.checkBounds(
          viewed.typeParameters,
          owner: isForwarder ? null : found.enclosingElement,
        );
      }
      return conversions.call(target, [
        builder.inputs.first,
        if (isGeneric) builder.inputs[1],
        for (final parameter in parameters)
          argument(builder, conversions, parameter),
      ]);
    });
  }

  /// A function for [selector] giving what [build] does, if it gives anything.
  HirFunction _make(
    String name,
    HirSelector selector,
    Level level,
    HirValue? Function(FunctionBuilder builder, Conversions conversions) build,
  ) {
    final function = HirFunction(name, [
      .reference,
      ...selector.parameters,
    ], selector.result);
    final builder = FunctionBuilder(_unit, function, const []);
    final conversions = Conversions(_scope, builder);
    builder.setReceiver(builder.inputs.first, level);
    final value = build(builder, conversions);
    final result = selector.result;
    if (result != null) {
      final given = value ?? builder.add(HirNull());
      builder.end(HirReturn(conversions.coerce(given, result)));
    }
    builder.finish();
    made.add(function);
    return function;
  }
}
