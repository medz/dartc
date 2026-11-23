import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/world.dart';

import 'classes.dart';
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
  final Declarations _declarations,
  final HirFunction Function(ExecutableElement member) _memberOf,
  final HirField Function(FieldElement field) _fieldOf,
  final HirInstruction Function(FormalParameterElement parameter) _defaultOf,
) {
  final _world = World<ClassElement, HirSelector>(isSubclass);
  final _selectors = <String, HirSelector>{};
  final _shapes = <HirSelector, _Shape>{};
  final _entries = <HirSelector, Map<ClassElement, HirFunction>>{};
  final _adapters = <(ExecutableElement, HirSelector), HirFunction>{};

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
  ) => {
    for (final MapEntry(key: selector, value: entries) in _entries.entries)
      selector: {
        for (final MapEntry(:key, :value) in entries.entries)
          classOf(key): value,
      },
  };

  HirFunction _entry(ClassElement class_, HirSelector selector) {
    final shape = _shapes[selector]!;
    final found =
        implementationIn(class_, shape.member) ??
        (throw _declarations.unsupported(class_, 'noSuchMethod'));
    if (found.library.isInSdk) return _objectEquals;
    _checkCovariance(class_, found);
    return _adapters[(found, selector)] ??= _adapt(found, selector, shape);
  }

  /// Calls rely on the parameters that overridden members declare.
  void _checkCovariance(ClassElement class_, ExecutableElement found) {
    final system = found.library.typeSystem;
    final parameters = found.formalParameters;
    for (final other in overriddenBy(class_, found)) {
      // Of the SDK's members only those of Object can be called yet.
      final owner = other.enclosingElement;
      if (other.library.isInSdk &&
          !(owner is ClassElement && owner.isDartCoreObject)) {
        continue;
      }
      for (final declared in other.formalParameters) {
        final own = declared.isNamed
            ? parameters.firstWhere((p) => p.isNamed && p.name == declared.name)
            : parameters
                  .where((p) => p.isPositional)
                  .elementAt(other.formalParameters.indexOf(declared));
        if (!system.isSubtypeOf(declared.type, own.type)) {
          throw _declarations.unsupported(
            fieldOfAccessor(found) ?? found,
            'covariant parameters',
          );
        }
      }
    }
  }

  /// A function called as [selector] says that does the work of [found].
  HirFunction _adapt(
    ExecutableElement found,
    HirSelector selector,
    _Shape shape,
  ) {
    if (fieldOfAccessor(found) case final field?) {
      return _accessor(found, _fieldOf(field), selector);
    }
    final target = _memberOf(found);
    final given = _given(found, shape.positional, shape.named);
    final isSame =
        given.length == found.formalParameters.length &&
        given.indexed.every((e) => e.$2 == found.formalParameters[e.$1]) &&
        target.result == selector.result;
    Never mismatch() => throw _declarations.unsupported(
      found,
      'overriding ${found.displayName} with other types',
    );
    for (final (i, parameter) in given.indexed) {
      if (valueType(parameter.type) != selector.parameters[i]) mismatch();
    }
    if (selector.result != null && target.result != selector.result) mismatch();
    if (isSame) return target;
    final block = HirBlock([.reference, ...selector.parameters]);
    final supplied = {
      for (final (i, parameter) in given.indexed)
        parameter: block.parameters[i + 1],
    };
    final call = block.add(
      HirCall(target, [
        block.parameters.first,
        for (final parameter in found.formalParameters)
          supplied[parameter] ?? block.add(_defaultOf(parameter)),
      ]),
    );
    block.end(HirReturn(selector.result == null ? null : call));
    return _make('adapt ${target.name}', selector, block);
  }

  HirFunction _accessor(
    ExecutableElement found,
    HirField field,
    HirSelector selector,
  ) {
    final isGetter = found is GetterElement;
    final type = isGetter ? selector.result : selector.parameters.single;
    if (field.type != type) {
      throw _declarations.unsupported(
        fieldOfAccessor(found)!,
        'overriding ${field.name} with other types',
      );
    }
    final block = HirBlock([.reference, ...selector.parameters]);
    final receiver = block.parameters.first;
    if (isGetter) {
      block.end(HirReturn(block.add(HirLoad(field, receiver))));
    } else {
      block
        ..add(HirStore(field, receiver, block.parameters[1]))
        ..end(HirReturn());
    }
    return _make(selector.name, selector, block);
  }

  HirFunction _make(String name, HirSelector selector, HirBlock block) {
    final function = HirFunction(name, [
      .reference,
      ...selector.parameters,
    ], selector.result)..define([block]);
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
