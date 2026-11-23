import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'conversions.dart';
import 'dynamic_shape.dart';
import 'levels.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

/// Finds what uses of members by their names reach.
///
/// Arguments and results are objects. Arguments are checked where they are
/// taken.
final class DynamicTable(final ProgramScope _scope, final SourceUnit _unit) {
  final _selectors = <String, HirSelector>{};
  final _shapes = <HirSelector, DynamicShape>{};
  final _entries = <HirSelector, Map<HirClass, HirFunction>>{};

  /// Functions made here.
  final List<HirFunction> made = [];

  Map<HirSelector, Map<HirClass, HirFunction>> get dispatch => _entries;

  HirSelector selectorOf(DynamicShape shape) {
    final DynamicShape(:use, :name, :library, :positional, :named) = shape;
    final key = [
      'dynamic',
      use.name,
      name,
      positional,
      ...named,
      ?library?.uri,
    ].join(' ');
    return _selectors[key] ??= () {
      final made = HirSelector(
        key,
        List.filled(positional + named.length, .reference),
        .reference,
      );
      _shapes[made] = shape;
      _entries[made] = {};
      return made;
    }();
  }

  /// Adds the entries found since the last time. Returns whether there were any.
  bool update(
    Iterable<ClassElement> classes,
    HirClass Function(ClassElement element) classOf,
    Iterable<Closure> closures,
  ) {
    var found = false;
    for (final MapEntry(key: selector, value: shape)
        in _shapes.entries.toList()) {
      final entries = _entries[selector]!;
      void add(HirClass class_, HirFunction Function() make) {
        if (entries.containsKey(class_)) return;
        entries[class_] = make();
        found = true;
      }

      for (final class_ in classes.toList()) {
        add(classOf(class_), () => _member(class_, selector, shape));
      }
      for (final closure in closures.toList()) {
        add(closure.class_, () => _function(closure, selector, shape));
      }
    }
    return found;
  }

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
    final result = build(builder, conversions) ?? builder.add(HirNull());
    builder
      ..end(HirReturn(conversions.coerce(result, .reference)))
      ..finish();
    made.add(function);
    return function;
  }

  /// A function throwing that objects have no such member.
  HirFunction _missing(HirSelector selector, DynamicShape shape) =>
      _make('no ${shape.name}', selector, (builder, _) {
        throwMissing(_scope, builder, builder.inputs.first, shape);
        return null;
      });

  HirFunction _function(
    Closure closure,
    HirSelector selector,
    DynamicShape shape,
  ) {
    if (shape.name != 'call' || shape.use == .set) {
      return _missing(selector, shape);
    }
    if (shape.use == .get) {
      return _make(selector.name, selector, (builder, _) {
        return builder.inputs.first;
      });
    }
    if (!accepts(closure.parameters, shape.positional, shape.named)) {
      return _missing(selector, shape);
    }
    return _make(selector.name, selector, (builder, conversions) {
      final self = builder.inputs.first;
      closure.bindTypes(builder, self);
      return builder.call(
        HirCall(closure.target(), [
          ...closure.leading(builder, self),
          ..._arguments(builder, conversions, closure.parameters, shape),
        ]),
      );
    });
  }

  /// What [selector] does for null.
  HirFunction forNull(HirSelector selector, ClassElement nullClass) =>
      _forNull[selector] ??= _member(nullClass, selector, _shapes[selector]!);
  final _forNull = <HirSelector, HirFunction>{};

  HirFunction _member(
    ClassElement class_,
    HirSelector selector,
    DynamicShape shape,
  ) {
    final own = _scope.levelOf(class_);
    final method = shape.use == .set
        ? null
        : memberNamed(own, shape.name, shape.library);
    final accessor = memberNamed(
      own,
      shape.use == .set ? '${shape.name}=' : shape.name,
      shape.library,
      isSetter: shape.use == .set,
      isGetter: shape.use != .set,
    );
    final found = method ?? accessor;
    if (found == null) {
      _rejectHandler(class_, shape);
      return _missing(selector, shape);
    }
    if (method == null) {
      return _make(selector.name, selector, (builder, conversions) {
        return _useAccessor(builder, conversions, accessor!, shape);
      });
    }
    if (shape.use == .get) {
      return _make(selector.name, selector, (builder, _) {
        return _scope.tearOff(builder, method, builder.inputs.first);
      });
    }
    final (:element, :level) = method;
    if (!accepts(element.formalParameters, shape.positional, shape.named)) {
      _rejectHandler(class_, shape);
      return _missing(selector, shape);
    }
    return _make(selector.name, selector, (builder, conversions) {
      final receiver = builder.inputs.first;
      builder.setReceiver(receiver, level);
      final types = _typeArguments(builder, element, shape);
      return builder.call(
        HirCall(_scope.memberOf(level, element), [
          _own(conversions, receiver, level),
          ?types,
          ..._arguments(builder, conversions, element.formalParameters, shape),
        ]),
      );
    });
  }

  void _rejectHandler(ClassElement class_, DynamicShape shape) {
    final level = _scope.levelOf(class_);
    final handler = memberNamed(level, 'noSuchMethod', null);
    final isOwn = handler?.level.superLevel != null;
    if (isOwn) {
      shape.reject('noSuchMethod');
    }
  }

  /// The type arguments of a call of [method] that gives none.
  HirValue? _typeArguments(
    FunctionBuilder builder,
    ExecutableElement method,
    DynamicShape shape,
  ) {
    if (method.typeParameters.isEmpty) return null;
    final list = _scope.typeList(builder, [
      for (final parameter in method.typeParameters)
        parameter.bound ?? builder.library.typeProvider.dynamicType,
    ]);
    if (list == null) shape.reject('these bounds in a dynamic call');
    builder.bindTypes(method, list);
    return list;
  }

  HirValue? _useAccessor(
    FunctionBuilder builder,
    Conversions conversions,
    Implementation found,
    DynamicShape shape,
  ) {
    final (element: accessor, :level) = found;
    final receiver = builder.inputs.first;
    final field = fieldOfAccessor(accessor);
    builder.setReceiver(receiver, level);
    final own = _own(conversions, receiver, level);
    if (shape.use == .set) {
      final value = _checked(
        conversions,
        builder.inputs[1],
        accessor.formalParameters.single,
        shape,
      );
      if (field != null) {
        _scope.storeField(builder, level, field, receiver, value);
      } else {
        builder.call(HirCall(_scope.memberOf(level, accessor), [own, value]));
      }
      return builder.inputs[1];
    }
    final value = field != null
        ? _scope.loadField(builder, level, field, receiver)
        : builder.call(HirCall(_scope.memberOf(level, accessor), [own]));
    if (shape.use == .get || value == null) return value;
    // A property that is called.
    return dynamicUse(
      _scope,
      builder,
      conversions.coerce(value, .reference),
      DynamicShape(
        .call,
        'call',
        null,
        shape.positional,
        shape.named,
        shape.reject,
      ),
      builder.inputs.skip(1).toList(),
    );
  }

  /// [receiver] as members of [level] take it.
  static HirValue _own(
    Conversions conversions,
    HirValue receiver,
    Level level,
  ) => conversions.coerce(receiver, plainType(level.element) ?? .reference);

  HirValue _checked(
    Conversions conversions,
    HirValue value,
    FormalParameterElement parameter,
    DynamicShape shape,
  ) =>
      conversions.cast(
        value,
        conversions.types.objectQuestionType,
        parameter.type,
        ending: " of '${parameter.name}'",
      ) ??
      shape.reject('testing for ${parameter.type}');

  /// What [parameters] get of what a use gives.
  List<HirValue> _arguments(
    FunctionBuilder builder,
    Conversions conversions,
    List<FormalParameterElement> parameters,
    DynamicShape shape,
  ) {
    var position = 0;
    return [
      for (final parameter in parameters)
        if (_place(parameter, shape, position) case final at?)
          _checked(
            conversions,
            builder.inputs[(parameter.isPositional ? position++ : at) + 1],
            parameter,
            shape,
          )
        else
          builder.add(_scope.defaultOf(parameter)),
    ];
  }

  static int? _place(
    FormalParameterElement parameter,
    DynamicShape shape,
    int position,
  ) {
    if (parameter.isPositional) {
      return position < shape.positional ? position : null;
    }
    final at = shape.named.indexOf(parameter.name!);
    return at < 0 ? null : shape.positional + at;
  }
}

/// The runtime's functions for operators of numbers of any kind.
const numberHelpers = <String, ({String name, bool isSwapped})>{
  '+': (name: 'numAdd', isSwapped: false),
  '-': (name: 'numSubtract', isSwapped: false),
  '*': (name: 'numMultiply', isSwapped: false),
  '/': (name: 'numDivide', isSwapped: false),
  '~/': (name: 'numTruncate', isSwapped: false),
  '%': (name: 'numModulo', isSwapped: false),
  '<': (name: 'numLess', isSwapped: false),
  '<=': (name: 'numLessOrEqual', isSwapped: false),
  '>': (name: 'numLess', isSwapped: true),
  '>=': (name: 'numLessOrEqual', isSwapped: true),
};

/// Whether a function with [parameters] can be called with arguments.
bool accepts(
  List<FormalParameterElement> parameters,
  int positional,
  List<String> named,
) {
  final places = parameters.where((p) => p.isPositional);
  final names = {
    for (final parameter in parameters)
      if (parameter.isNamed) parameter.name,
  };
  return positional <= places.length &&
      positional >= places.where((p) => p.isRequired).length &&
      names.containsAll(named) &&
      parameters.every((p) => !p.isRequiredNamed || named.contains(p.name));
}

/// Throws that [object] has no member for [shape].
void throwMissing(
  ProgramScope scope,
  FunctionBuilder builder,
  HirValue object,
  DynamicShape shape,
) {
  final kind = switch (shape.use) {
    .call => 'method',
    .get => 'getter',
    .set => 'setter',
  };
  builder
    ..call(
      HirCall(scope.runtime('throwMissing'), [
        object,
        builder.add(scope.text(kind)),
        builder.add(scope.text(shape.name)),
      ]),
    )
    ..end(HirUnreachable());
}

/// Uses a member of [object], which can be anything.
HirValue dynamicUse(
  ProgramScope scope,
  FunctionBuilder builder,
  HirValue object,
  DynamicShape shape,
  List<HirValue> arguments,
) {
  final selector = scope.dynamicSelector(shape);
  return builder.choose(
    builder.add(HirCompare(.equal, object, builder.add(HirNull()))),
    .reference,
    () => builder.call(
      HirCall(scope.dynamicNull(selector), [object, ...arguments]),
    )!,
    () => builder.call(HirVirtualCall(selector, object, arguments))!,
  );
}
