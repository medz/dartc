import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:dartc/world.dart';

import 'builder.dart';
import 'classes.dart';
import 'closure_table.dart';
import 'conversions.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

/// A member and the arguments its calls give.
typedef _Shape = ({
  ExecutableElement member,
  int positional,
  List<String> named,
});

/// Finds which functions calls on objects can reach.
final class DispatchBuilder(
  final ProgramScope _scope,
  final Declarations _declarations,
  final SourceUnit _unit,
) {
  final _tearOffs = <HirSelector>{};
  final _world = World<ClassElement, HirSelector>(isSubclass);
  final _selectors = <String, HirSelector>{};
  final _shapes = <HirSelector, _Shape>{};
  final _entries = <HirSelector, Map<ClassElement, HirFunction>>{};
  final _adapters = <(ExecutableElement, HirSelector, String), HirFunction>{};

  /// Functions made here rather than declared by the program.
  final List<HirFunction> made = [];

  late final HirFunction _objectEquals = _makeObjectEquals();

  List<ClassElement> get classes => _world.classes;

  void instantiate(ClassElement class_) => _world.instantiate(class_);

  HirSelector selectorOf(
    ExecutableElement member,
    ClassElement receiver,
    int positional,
    List<String> named,
    Reject reject,
  ) {
    final types = [
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
      types,
      result,
    ].join('|');
    final selector = _selectors.putIfAbsent(key, () {
      final made = HirSelector(name, types, result);
      _shapes[made] = (member: member, positional: positional, named: named);
      _entries[made] = {};
      return made;
    });
    _world.call(selector, receiver);
    return selector;
  }

  /// How to get the method [member] of objects of [receiver].
  HirSelector tearOffSelector(ExecutableElement member, ClassElement receiver) {
    final owner = member.isPrivate ? member.library.uri : '';
    final key = 'tear-off|${member.lookupName}|$owner';
    final selector = _selectors.putIfAbsent(key, () {
      final made = HirSelector(
        'tear-off ${member.displayName}',
        const [],
        .reference,
      );
      _shapes[made] = (member: member, positional: 0, named: const []);
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
    for (final (class_, selector) in entries) {
      _entries[selector]![class_] = _entry(class_, selector);
    }
    return entries.isNotEmpty;
  }

  Map<HirSelector, Map<HirClass, HirFunction>> result(
    HirClass Function(ClassElement element) classOf,
    ClosureTable closures,
  ) => {
    for (final MapEntry(key: selector, value: entries) in _entries.entries)
      selector: {
        for (final MapEntry(:key, :value) in entries.entries)
          classOf(key): value,
        if (selector.name == '==')
          ...closures.equalities(selector, _objectEquals),
      },
  };

  HirFunction _entry(ClassElement class_, HirSelector selector) {
    final shape = _shapes[selector]!;
    final found =
        implementationIn(class_, shape.member) ??
        (throw _declarations.unsupported(class_, 'noSuchMethod'));
    if (_tearOffs.contains(selector)) {
      return _make(selector.name, selector, (builder, _) {
        return _scope.tearOff(builder, found, builder.inputs.first);
      });
    }
    if (found.library.isInSdk) {
      return _numberEquals(class_, selector) ?? _objectEquals;
    }
    final checked = _checkedParameters(class_, found);
    return _adapters[(found, selector, '$checked')] ??= _adapt(
      found,
      selector,
      shape,
      checked,
    );
  }

  /// How a number compares itself, if [class_] is one of numbers.
  HirFunction? _numberEquals(ClassElement class_, HirSelector selector) {
    final isInt = class_.name == 'int';
    if (!class_.library.isInSdk || !isInt && class_.name != 'double') {
      return null;
    }
    return _make('$class_ ==', selector, (builder, conversions) {
      final [self, other] = builder.inputs;
      final value = conversions.coerce(self, isInt ? .integer : .float);
      final helper = _scope.runtime(isInt ? 'intEquals' : 'doubleEquals');
      return builder.call(HirCall(helper, [value, other]));
    });
  }

  /// The places of parameters that calls may give values of other types, as
  /// they rely on the types that overridden members declare.
  List<int> _checkedParameters(ClassElement class_, ExecutableElement found) {
    final system = found.library.typeSystem;
    final parameters = found.formalParameters;
    final checked = <int>{};
    for (final other in overriddenBy(class_, found)) {
      // Of the SDK's members only those of Object can be called yet.
      final owner = other.enclosingElement;
      if (other.library.isInSdk &&
          !(owner is ClassElement && owner.isDartCoreObject)) {
        continue;
      }
      for (final declared in other.formalParameters) {
        final place = declared.isNamed
            ? parameters.indexWhere((p) => p.isNamed && p.name == declared.name)
            : other.formalParameters.indexOf(declared);
        if (!system.isSubtypeOf(declared.type, parameters[place].type)) {
          checked.add(place);
        }
      }
    }
    return checked.toList()..sort();
  }

  /// A function called as [selector] says that does the work of [found], after
  /// checking some parameters.
  HirFunction _adapt(
    ExecutableElement found,
    HirSelector selector,
    _Shape shape,
    List<int> checked,
  ) {
    final field = fieldOfAccessor(found);
    final given = _given(found, shape.positional, shape.named);
    final parameters = found.formalParameters;
    HirValue argument(
      FunctionBuilder builder,
      Conversions conversions,
      FormalParameterElement parameter,
    ) {
      final at = given.indexOf(parameter);
      if (at < 0) return builder.add(_scope.defaultOf(parameter));
      final value = builder.inputs[at + 1], type = parameter.type;
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
      final place = _scope.fieldOf(field);
      return _make(selector.name, selector, (builder, conversions) {
        final receiver = builder.inputs.first;
        if (found is GetterElement) {
          return builder.add(HirLoad(place, receiver));
        }
        final value = argument(builder, conversions, parameters.single);
        builder.add(HirStore(place, receiver, value));
        return null;
      });
    }
    final target = _scope.memberOf(found);
    final isSame =
        checked.isEmpty &&
        given.length == parameters.length &&
        given.indexed.every((e) => e.$2 == parameters[e.$1]) &&
        given.indexed.every(
          (e) => valueType(e.$2.type) == selector.parameters[e.$1],
        ) &&
        target.result == selector.result;
    if (isSame) return target;
    return _make('adapt ${target.name}', selector, (builder, conversions) {
      return builder.call(
        HirCall(target, [
          builder.inputs.first,
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
    HirValue? Function(FunctionBuilder builder, Conversions conversions) build,
  ) {
    final function = HirFunction(name, [
      .reference,
      ...selector.parameters,
    ], selector.result);
    final builder = FunctionBuilder(_unit, function, const []);
    final conversions = Conversions(_scope, builder);
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

  HirFunction _makeObjectEquals() {
    final block = HirBlock([.reference, .reference]);
    final [left, right] = block.parameters;
    block.end(HirReturn(block.add(HirCompare(.equal, left, right))));
    final function = HirFunction('Object.==', [
      .reference,
      .reference,
    ], .boolean)..define([block]);
    made.add(function);
    return function;
  }
}
