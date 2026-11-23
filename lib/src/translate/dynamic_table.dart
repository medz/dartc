import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'checks.dart';
import 'closure.dart';
import 'conversions.dart';
import 'dynamic_shape.dart';
import 'members.dart';
import 'scope.dart';

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

  HirFunction _member(
    ClassElement class_,
    HirSelector selector,
    DynamicShape shape,
  ) {
    if (_numberOperator(class_, shape) case final operation?) {
      return _make('$class_ ${shape.name}', selector, operation);
    }
    if (class_.library.isInSdk && _declares(class_, shape)) {
      shape.reject('calling ${shape.name} of the SDK');
    }
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
    if (found.element.library.isInSdk) {
      shape.reject('calling ${shape.name} of the SDK');
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
          receiver,
          ?types,
          ..._arguments(builder, conversions, element.formalParameters, shape),
        ]),
      );
    });
  }

  /// Whether [class_] of the SDK has the member used, even if abstract here.
  static bool _declares(ClassElement class_, DynamicShape shape) =>
      [class_, for (final type in class_.allSupertypes) type.element].any(
        (owner) =>
            owner.getMethod(shape.name) != null ||
            owner.getGetter(shape.name) != null ||
            owner.getSetter(shape.name) != null,
      );

  void _rejectHandler(ClassElement class_, DynamicShape shape) {
    final level = _scope.levelOf(class_);
    final handler = memberNamed(level, 'noSuchMethod', null);
    if (handler != null && !handler.element.library.isInSdk) {
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
        builder.call(
          HirCall(_scope.memberOf(level, accessor), [receiver, value]),
        );
      }
      return builder.inputs[1];
    }
    final value = field != null
        ? _scope.loadField(builder, level, field, receiver)
        : builder.call(HirCall(_scope.memberOf(level, accessor), [receiver]));
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

  /// What numbers and bools do for an operator, which the SDK declares.
  HirValue? Function(FunctionBuilder builder, Conversions conversions)?
  _numberOperator(ClassElement class_, DynamicShape shape) {
    if (!class_.library.isDartCore || shape.use != .call) return null;
    final isUnary = shape.positional == 0;
    if (shape.positional > 1 || shape.named.isNotEmpty) return null;
    return switch (class_.name) {
      'int' || 'double' when isUnary => _unaryOf(class_.name!, shape.name),
      'int' || 'double' => _binaryOf(class_.name!, shape),
      'bool' when !isUnary => _boolOf(shape),
      _ => null,
    };
  }

  HirValue? Function(FunctionBuilder, Conversions)? _unaryOf(
    String class_,
    String name,
  ) {
    final helper = switch (name) {
      'unary-' => 'numNegate',
      'toInt' => 'numToInt',
      'toDouble' => 'numToDouble',
      _ => null,
    };
    if (helper != null) {
      return (builder, _) =>
          builder.call(HirCall(_scope.runtime(helper), builder.inputs));
    }
    if (name != '~' || class_ != 'int') return null;
    return (builder, conversions) => builder.add(
      HirUnary(
        .complement,
        conversions.coerce(builder.inputs.single, .integer),
      ),
    );
  }

  HirValue? Function(FunctionBuilder, Conversions)? _binaryOf(
    String class_,
    DynamicShape shape,
  ) {
    HirValue other(
      FunctionBuilder builder,
      Conversions conversions,
      DartType type,
    ) => conversions.cast(
      builder.inputs[1],
      conversions.types.objectQuestionType,
      type,
      ending: " of 'other'",
    )!;
    final helper = numberHelpers[shape.name];
    if (helper != null) {
      return (builder, conversions) {
        final operands = [
          builder.inputs[0],
          other(builder, conversions, conversions.types.numType),
        ];
        return builder.call(
          HirCall(
            _scope.runtime(helper.name),
            helper.isSwapped ? operands.reversed : operands,
          ),
        );
      };
    }
    if (class_ != 'int') return null;
    for (final operator in HirIntOperator.values) {
      if (operator.symbol != shape.name) continue;
      return (builder, conversions) =>
          CheckedOperations(_scope, builder).integer(
            operator,
            conversions.coerce(builder.inputs[0], .integer),
            other(builder, conversions, conversions.types.intType),
          );
    }
    return null;
  }

  HirValue? Function(FunctionBuilder, Conversions)? _boolOf(
    DynamicShape shape,
  ) {
    for (final operator in HirBoolOperator.values) {
      if (operator.symbol != shape.name) continue;
      return (builder, conversions) {
        final other = conversions.cast(
          builder.inputs[1],
          conversions.types.objectQuestionType,
          conversions.types.boolType,
          ending: " of 'other'",
        )!;
        return builder.add(
          HirBoolBinary(
            operator,
            conversions.coerce(builder.inputs[0], .boolean),
            other,
          ),
        );
      };
    }
    return null;
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
  final number = scope.missingNumber(kind, shape.name);
  builder
    ..call(
      HirCall(scope.throwerOf(.missingMember), [
        object,
        builder.add(HirNull()),
        builder.add(HirConst(number)),
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
  final isSome = builder.add(
    HirCompare(.notEqual, object, builder.add(HirNull())),
  );
  builder.unless(isSome, () => throwMissing(scope, builder, object, shape));
  return builder.call(
    HirVirtualCall(scope.dynamicSelector(shape), object, arguments),
  )!;
}
