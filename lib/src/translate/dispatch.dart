import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:dartc/world.dart';

import 'builder.dart';
import 'classes.dart';
import 'closure_table.dart';
import 'conversions.dart';
import 'levels.dart';
import 'members.dart';
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
  }) {
    final found = implementationIn(level, member);
    if (found == null) return null;
    final selector = _selector(member, positional, named, reject);
    return _function(level, found, selector, isUnboxed: isUnboxed);
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

  HirType? _result(ExecutableElement member, Reject reject) {
    if (hasNoResult(member.returnType)) return null;
    return valueType(member.returnType) ??
        reject('a result of type ${member.returnType}');
  }

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
    final found = own ?? (element: shape.member, level: level);
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
    if (own == null) {
      return _adapt(
        found,
        selector,
        shape,
        _checkedParameters(class_, shape.member, shape),
        isUnboxed: false,
        isForwarder: true,
      );
    }
    return _function(level, found, selector);
  }

  /// What does the work of [found] for objects whose class is at [level].
  HirFunction _function(
    Level level,
    Implementation found,
    HirSelector selector, {
    bool isUnboxed = false,
  }) {
    final checked = _checkedParameters(
      level.class_,
      found.element,
      _shapes[selector]!,
    );
    return _adapters[(found, selector, '$checked $isUnboxed')] ??= _adapt(
      found,
      selector,
      _shapes[selector]!,
      checked,
      isUnboxed: isUnboxed,
    );
  }

  /// The places of parameters that calls may give values of other types, as
  /// they rely on the types that overridden members declare.
  List<int> _checkedParameters(
    InterfaceElement class_,
    ExecutableElement found,
    _Shape shape,
  ) {
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
    if (shape.isOwn) {
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
    HirValue argument(
      FunctionBuilder builder,
      Conversions conversions,
      FormalParameterElement parameter,
    ) {
      final at = given.indexOf(parameter);
      if (at < 0) return builder.add(_scope.defaultOf(parameter));
      final value = builder.inputs[at + (isGeneric ? 2 : 1)];
      final type = parameter.type;
      if (!checked.contains(parameters.indexOf(parameter))) {
        return conversions.coerce(value, valueType(type)!);
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
    final isSame =
        checked.isEmpty &&
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
      if (isGeneric) builder.bindTypes(found, builder.inputs[1]);
      return builder.call(
        HirCall(target, [
          conversions.coerce(builder.inputs.first, target.parameters.first),
          if (isGeneric) builder.inputs[1],
          for (final parameter in parameters)
            argument(builder, conversions, parameter),
        ]),
      );
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
