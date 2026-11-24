import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'coroutine.dart';
import 'scope.dart';
import 'types.dart';

/// Translates what only `async` functions and generators do.
final class CoroutineBody(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
) {
  late final _conversions = Conversions(_scope, _builder);

  Coroutine get _coroutine => _builder.coroutine!;

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  HirValue _call(String name, List<HirValue> arguments, {HirValue? types}) {
    final function = _scope.runtime(name);
    return _builder.call(HirCall(function, [?types, ...arguments]))!;
  }

  HirValue _object(HirValue value) => _conversions.coerce(value, .reference);

  /// Leaves the function, giving [value], until it is entered with another.
  HirValue _suspend(HirValue value) =>
      _builder.call(HirCall(_coroutine.suspend, [value]))!;

  HirValue get _null => _builder.add(HirNull());

  HirValue _truth(bool value) => _object(_builder.add(HirConst(value)));

  /// Ends where a generator is not to start.
  void begin(void Function() end) {
    if (_coroutine.kind == .asyncStar) _endIf(_coroutine.first, end);
  }

  /// Does [end] if [given], which the runtime gave, is true.
  void _endIf(HirValue given, void Function() end) {
    final isOver = _conversions.coerce(given, .boolean);
    _builder.branch(isOver, end, () {});
  }

  /// Ends the function, which gives [value] if it is `async`.
  void finish(HirValue value) {
    switch (_coroutine.kind) {
      case .async:
        _call('finishAsync', [_coroutine.state, value]);
        _builder.end(HirReturn(_null));
      case .asyncStar:
        _call('finishAsyncStar', [_coroutine.state]);
        _builder.end(HirReturn(_null));
      case .syncStar:
        _builder.end(HirReturn(_truth(false)));
    }
  }

  /// The value of [node].
  HirValue awaitExpression(AwaitExpression node) {
    final expression = node.expression, type = expression.staticType!;
    final value = _object(
      _evaluator.value(expression, placeholder: .reference),
    );
    final result = _wait(node, value, type);
    if (isNever(node.staticType)) return result;
    final representation = valueType(node.staticType!);
    if (representation == null) {
      _unsupported(node, 'a value of type ${node.staticType}');
    }
    return _conversions.coerce(result, representation);
  }

  /// What [value], of [type], is if it is no future, or what it gives then.
  HirValue _wait(AstNode node, HirValue value, DartType type) {
    final system = _builder.library.typeSystem;
    final bound = boundOf(type);
    final isFuture =
        type is DynamicType ||
        bound is InterfaceType &&
            bound.asInstanceOf(_conversions.types.futureElement) != null;
    if (isFuture) {
      _call('await', [_coroutine.state, value]);
    } else {
      final found = _scope.typeList(_builder, [system.flatten(type)]);
      if (found == null) _unsupported(node, 'waiting for $type');
      _call('awaitChecked', [_coroutine.state, value], types: found);
    }
    return _suspend(_null);
  }

  /// Gives the value of [node], or all those that it holds.
  void yieldStatement(YieldStatement node, void Function() end) {
    final own = _builder.returnType!, types = _conversions.types;
    final isAll = node.star != null, isAsync = _coroutine.kind == .asyncStar;
    final type = !isAll
        ? own
        : isAsync
        ? types.streamType(own)
        : types.iterableType(own);
    final value = _evaluator.valueAsObject(node.expression, type);
    final name =
        '${isAll ? 'yieldAll' : 'yield'}${isAsync ? 'AsyncStar' : 'SyncStar'}';
    final result = _call(name, [_coroutine.state, value]);
    if (!isAsync) {
      _suspend(_truth(true));
      return;
    }
    _builder.branch(result, end, () {});
    _endIf(_suspend(_null), end);
  }

  /// Does [body] for each value that [stream] gives. Does it within [protect],
  /// which does its second part in any case.
  void each(
    AstNode node,
    HirValue stream,
    DartType type,
    void Function(HirValue value) body, {
    required void Function(Join exit, Join next) within,
    required void Function(void Function() body, void Function() last) protect,
  }) {
    final types = _scope.typeList(_builder, [type]);
    if (types == null) _unsupported(node, 'a stream of $type');
    final iterator = _call('iterateStream', [stream], types: types);
    final exit = _builder.join(node);
    protect(
      () {
        final next = _builder.join(node);
        within(exit, next);
        _builder
          ..jump(next)
          ..enter(next);
        final boolType = _conversions.types.boolType;
        final more = _wait(
          node,
          _call('moveStream', [iterator]),
          _conversions.types.futureType(boolType),
        );
        _builder.branch(_conversions.coerce(more, .boolean), () {
          body(_call('currentOfStream', [iterator]));
          _builder.jump(next);
        }, () => _builder.jump(exit));
        _builder.enter(exit);
      },
      () {
        final after = _builder.join(node);
        _builder.branch(_call('isStreamOpen', [iterator]), () {
          _wait(
            node,
            _call('cancelStream', [iterator]),
            _conversions.types.futureDynamicType,
          );
          _builder.jump(after);
        }, () => _builder.jump(after));
        _builder.enter(after);
      },
    );
  }
}
