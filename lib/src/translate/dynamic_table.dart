import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'conversions.dart';
import 'dynamic_shape.dart';
import 'forwarders.dart';
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
    final DynamicShape(:use, :name, :library, :positional, :named, :types) =
        shape;
    final key = [
      'dynamic',
      use.name,
      name,
      positional,
      if (types > 0) '<$types>',
      ...named,
      ?library?.uri,
    ].join(' ');
    return _selectors[key] ??= () {
      final made = HirSelector(key, [
        if (types > 0) HirType.reference,
        for (var i = positional + named.length; i > 0; i--) HirType.reference,
      ], .reference);
      _shapes[made] = shape;
      _entries[made] = {};
      return made;
    }();
  }

  /// Adds the entries found since the last time. Returns whether there were any.
  bool update(
    Iterable<InterfaceElement> classes,
    HirClass Function(InterfaceElement element) classOf,
    Iterable<Closure> closures,
    InterfaceElement functionClass,
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
        add(
          closure.class_,
          () => _function(closure, functionClass, selector, shape),
        );
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

  /// A function telling that objects have no such member, or one that takes
  /// [found] and is called [name]. Objects of all classes share it.
  HirFunction _missing(
    HirSelector selector,
    DynamicShape shape, {
    String? name,
    String? found,
  }) => _missed[(selector, name, found)] ??= _makeMissing(
    selector,
    shape,
    name,
    found,
  );
  final _missed = <(HirSelector, String?, String?), HirFunction>{};

  HirFunction _makeMissing(
    HirSelector selector,
    DynamicShape shape,
    String? name,
    String? found,
  ) => _make('no ${shape.name}', selector, (builder, _) {
    final [receiver, ...all] = builder.inputs;
    final types = shape.types > 0 ? all.first : null;
    final given = types == null ? all : all.sublist(1);
    final isSetter = shape.use == .set;
    return callMissing(
      _scope,
      builder,
      receiver,
      shape.use.index,
      name ?? (isSetter ? '${shape.name}=' : shape.name),
      given.take(isSetter ? 1 : shape.positional).toList(),
      {
        for (final (i, name) in shape.named.indexed)
          name: given[shape.positional + i],
      },
      types: types,
      found: found,
    );
  });

  /// Uses the field of a record, if it has it.
  HirFunction _recordField(HirSelector selector, DynamicShape shape) {
    final missing = _missing(selector, shape);
    return _make(selector.name, selector, (builder, _) {
      final record = builder.inputs.first;
      HirValue call(String name, List<HirValue> given) =>
          builder.call(HirCall(_scope.runtime(name), [record, ...given]))!;
      final name = builder.add(_scope.text(shape.name));
      final index = call('recordIndex', [name]);
      final hasNone = HirCompare(.less, index, builder.add(HirConst(0)));
      return builder.choose(
        builder.add(hasNone),
        .reference,
        () => builder.call(HirCall(missing, builder.inputs))!,
        () {
          final value = call('recordField', [index]);
          if (shape.use == .get) return value;
          return _callValue(builder, value, shape);
        },
      );
    });
  }

  /// Calls [value], which a property gave.
  HirValue _callValue(
    FunctionBuilder builder,
    HirValue value,
    DynamicShape shape,
  ) => dynamicUse(
    _scope,
    builder,
    value,
    DynamicShape(
      .call,
      'call',
      null,
      shape.positional,
      shape.named,
      shape.reject,
      types: shape.types,
    ),
    builder.inputs.skip(1).toList(),
  );

  HirFunction _function(
    Closure closure,
    InterfaceElement functionClass,
    HirSelector selector,
    DynamicShape shape,
  ) {
    if (shape.name != 'call' || shape.use == .set) {
      return _member(functionClass, selector, shape);
    }
    if (shape.use == .get) {
      return _make(selector.name, selector, (builder, _) {
        return builder.inputs.first;
      });
    }
    if (closure.part case final part? when shape.types == 0) {
      return _make(selector.name, selector, (builder, _) {
        final [self, ...given] = builder.inputs;
        return builder.call(
          HirVirtualCall(
            selectorOf(shape.withTypes(part.count)),
            builder.add(HirLoad(part.function, self)),
            [builder.add(HirLoad(part.types, self)), ...given],
          ),
        );
      });
    }
    final count = closure.typeParameters.length;
    if (shape.types > 0 && shape.types != count ||
        !accepts(closure.parameters, shape.positional, shape.named)) {
      return _missing(selector, shape, name: closure.name);
    }
    return _make(selector.name, selector, (builder, conversions) {
      final self = builder.inputs.first;
      closure.bindTypes(builder, self);
      return conversions.call(closure.target(), [
        ...closure.leading(builder, self),
        if (count > 0)
          ?_typesFor(
            builder,
            conversions,
            closure.typeParameters,
            shape,
            (list) => closure.bindGiven(builder, list),
          ),
        ..._arguments(builder, conversions, closure.parameters, shape, closure),
      ]);
    });
  }

  /// What [selector] does for null.
  HirFunction forNull(HirSelector selector, InterfaceElement nullClass) =>
      _forNull[selector] ??= _member(nullClass, selector, _shapes[selector]!);
  final _forNull = <HirSelector, HirFunction>{};

  HirFunction _member(
    InterfaceElement class_,
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
    final isField = class_ == _scope.recordClass && shape.use != .set;
    if (method == null && accessor == null && isField) {
      return _recordField(selector, shape);
    }
    if (method == null && accessor == null) {
      return _forward(class_, own, selector, shape) ??
          _missing(selector, shape);
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
    final count = element.typeParameters.length;
    if (shape.types > 0 && shape.types != count ||
        !accepts(element.formalParameters, shape.positional, shape.named)) {
      final type = describeType(element.type);
      return _missing(selector, shape, found: type);
    }
    return _make(selector.name, selector, (builder, conversions) {
      final receiver = builder.inputs.first;
      builder.setReceiver(receiver, level);
      final types = _typeArguments(builder, conversions, element, shape);
      return builder.call(
        HirCall(_scope.memberOf(level, element), [
          _own(conversions, receiver, level),
          ?types,
          ..._arguments(builder, conversions, element.formalParameters, shape),
        ]),
      );
    });
  }

  /// The type arguments of a call of [method] that gives none.
  HirValue? _typeArguments(
    FunctionBuilder builder,
    Conversions conversions,
    ExecutableElement method,
    DynamicShape shape,
  ) {
    final parameters = method.typeParameters;
    return parameters.isEmpty
        ? null
        : _typesFor(builder, conversions, parameters, shape, (list) {
            builder
              ..bindTypes(method.baseElement, list)
              ..bindParameters(parameters, list);
            return list;
          });
  }

  /// The type arguments that a call gives for [parameters], or their bounds,
  /// as [bind] gives them.
  HirValue? _typesFor(
    FunctionBuilder builder,
    Conversions conversions,
    List<TypeParameterElement> parameters,
    DynamicShape shape,
    HirValue? Function(HirValue list) bind,
  ) {
    final list = shape.types > 0
        ? builder.inputs[1]
        : _scope.typeList(builder, defaultTypesOf(parameters, builder.library));
    if (list == null) shape.reject('these bounds in a dynamic call');
    final bound = bind(list);
    conversions.checkBounds(parameters);
    return bound;
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
        field != null && field.isExternal ? '#externalFieldValue' : null,
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
    return _callValue(builder, conversions.coerce(value, .reference), shape);
  }

  /// Uses a member that [class_] only forwards to its `noSuchMethod`, if it has
  /// one like that.
  HirFunction? _forward(
    InterfaceElement class_,
    Level level,
    HirSelector selector,
    DynamicShape shape,
  ) {
    if (shape.use != .call) return null;
    for (final type in class_.allSupertypes) {
      final method = type.element.getMethod(shape.name);
      final isKnown =
          method != null &&
          !method.isStatic &&
          (shape.library == null || shape.library == method.library) &&
          implementationIn(level, method) == null;
      if (!isKnown) continue;
      final viewed = viewedAt(level, method);
      final parameters = viewed.formalParameters;
      if (!accepts(parameters, shape.positional, shape.named)) {
        final type = describeType(viewed.type);
        return _missing(selector, shape, found: type);
      }
      return _make(selector.name, selector, (builder, conversions) {
        final receiver = builder.inputs.first;
        builder.setReceiver(receiver, level);
        return conversions.call(_scope.forwarderOf(level, method), [
          receiver,
          ?_typeArguments(builder, conversions, viewed, shape),
          ..._arguments(builder, conversions, parameters, shape),
        ]);
      });
    }
    return null;
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
    DynamicShape shape, [
    String? name,
  ]) =>
      conversions.cast(
        value,
        conversions.types.objectQuestionType,
        parameter.type,
        ending: " of '${name ?? parameter.name}'",
      ) ??
      shape.reject('testing for ${parameter.type}');

  /// What [parameters] get of what a use gives.
  List<HirValue> _arguments(
    FunctionBuilder builder,
    Conversions conversions,
    List<FormalParameterElement> parameters,
    DynamicShape shape, [
    Closure? closure,
  ]) {
    var position = 0;
    return [
      for (final parameter in parameters)
        if (_place(parameter, shape, position) case final at?)
          _checked(
            conversions,
            builder.inputs[(parameter.isPositional ? position++ : at) +
                (shape.types > 0 ? 2 : 1)],
            parameter,
            shape,
            closure?.nameOf(parameter),
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
