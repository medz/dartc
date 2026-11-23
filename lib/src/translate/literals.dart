import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'describe.dart';
import 'loops.dart';
import 'scope.dart';

/// Translates literals of collections.
final class LiteralTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final LoopTranslator _loops,
) {
  late final _conversions = Conversions(_scope, _builder);

  Never _unsupported(AstNode node) =>
      throw _builder.unit.unsupported(node, describe(node));

  HirValue? _call(String name, List<HirValue> arguments) =>
      _builder.call(HirCall(_scope.runtime(name), arguments));

  HirValue _types(TypedLiteral node) =>
      _scope.typeList(_builder, _arguments(node)) ?? _unsupported(node);

  static List<DartType> _arguments(TypedLiteral node) =>
      (node.staticType as InterfaceType).typeArguments;

  HirValue _array(List<HirValue> values) =>
      _scope.list(_builder, _conversions.types.dynamicType, values);

  HirValue list(ListLiteral node) {
    final type = _arguments(node).single, types = _types(node);
    final isPlain = node.elements.every((element) => element is Expression);
    final first = [
      if (isPlain)
        for (final part in node.elements)
          _evaluator.valueAsObject(part as Expression, type),
    ];
    final list = _call('listOf', [types, _array(first)])!;
    if (isPlain) return list;
    for (final element in node.elements) {
      _element(element, [type], (values) {
        _call('addElement', [list, values.single]);
      });
    }
    return list;
  }

  HirValue setOrMap(SetOrMapLiteral node) {
    final arguments = _arguments(node);
    final kind = node.isMap ? 'Map' : 'Set';
    final result = _call('new$kind', [_types(node)])!;
    for (final element in node.elements) {
      _element(element, arguments, (values) {
        _call('addTo$kind', [result, ...values]);
      });
    }
    return result;
  }

  /// Evaluates [node], giving each value or pair, of [types], to [add].
  void _element(
    CollectionElement node,
    List<DartType> types,
    void Function(List<HirValue> values) add,
  ) {
    switch (node) {
      case Expression():
        add([_evaluator.valueAsObject(node, types.single)]);
      case NullAwareElement(:final value):
        final object = _evaluator.valueAsObject(value, _nullable(types.single));
        _unlessNull(node, [object], () => add([object]));
      case MapLiteralEntry():
        _entry(node, types, add);
      case IfElement(caseClause: null):
        final exit = _builder.join(node);
        final isTrue = _evaluator.valueTo(
          node.expression,
          _conversions.types.boolType,
        );
        _builder.branch(
          isTrue,
          () {
            _element(node.thenElement, types, add);
            _builder.jump(exit);
          },
          () {
            if (node.elseElement case final other?) _element(other, types, add);
            _builder.jump(exit);
          },
        );
        _builder.enter(exit);
      case ForElement(:final forLoopParts, :final body):
        _loops.translate(node, forLoopParts, () => _element(body, types, add));
      case SpreadElement(:final expression):
        final whole = _evaluator.value(expression, placeholder: .reference);
        void spread() => types.length == 1
            ? _spread(node, whole, types.single, add)
            : _spreadMap(node, whole, types, add);
        node.isNullAware ? _unlessNull(node, [whole], spread) : spread();
      default:
        _unsupported(node);
    }
  }

  DartType _nullable(DartType type) => _builder.library.typeSystem
      .leastUpperBound(type, _conversions.types.nullType);

  /// Does [work] unless one of [values] is null.
  void _unlessNull(AstNode node, List<HirValue> values, void Function() work) {
    final exit = _builder.join(node);
    void test(int index) {
      if (index == values.length) {
        work();
        _builder.jump(exit);
      } else {
        _builder.branch(
          _conversions.isNull(values[index]),
          () => _builder.jump(exit),
          () => test(index + 1),
        );
      }
    }

    test(0);
    _builder.enter(exit);
  }

  void _entry(
    MapLiteralEntry node,
    List<DartType> types,
    void Function(List<HirValue> values) add,
  ) {
    HirValue part(
      Expression part,
      DartType type, {
      required bool isNullAware,
    }) => _evaluator.valueAsObject(part, isNullAware ? _nullable(type) : type);
    final skipsKey = node.keyQuestion != null;
    final skipsValue = node.valueQuestion != null;
    final key = part(node.key, types[0], isNullAware: skipsKey);
    _unlessNull(node, [if (skipsKey) key], () {
      final value = part(node.value, types[1], isNullAware: skipsValue);
      _unlessNull(node.value, [if (skipsValue) value], () => add([key, value]));
    });
  }

  void _spread(
    SpreadElement node,
    HirValue whole,
    DartType type,
    void Function(List<HirValue> values) add,
  ) {
    final expression = node.expression, from = expression.staticType!;
    final iterable = from is DynamicType
        ? _conversions.cast(
            whole,
            from,
            _conversions.types.iterableDynamicType,
          )!
        : whole;
    final own = _loops.elementType(from);
    _loops.each(node, expression, iterable, (value) {
      add([_cast(node, value, own, type)]);
    });
  }

  void _spreadMap(
    SpreadElement node,
    HirValue whole,
    List<DartType> types,
    void Function(List<HirValue> values) add,
  ) {
    final from = node.expression.staticType!;
    final mapType = _conversions.types.mapType(
      _conversions.types.dynamicType,
      _conversions.types.dynamicType,
    );
    final map = from is DynamicType
        ? _conversions.cast(whole, from, mapType)!
        : whole;
    final entries = _call('entriesOf', [map])!;
    final own =
        _mapArguments(from) ??
        [_conversions.types.dynamicType, _conversions.types.dynamicType];
    _loops.each(node, node.expression, entries, (entry) {
      add([
        for (final (i, name) in const ['keyOf', 'valueOf'].indexed)
          _cast(node, _call(name, [entry])!, own[i], types[i]),
      ]);
    });
  }

  List<DartType>? _mapArguments(DartType type) => switch (type) {
    final InterfaceType type =>
      type.asInstanceOf(_conversions.types.mapElement)?.typeArguments,
    _ => null,
  };

  HirValue _cast(AstNode node, HirValue value, DartType from, DartType to) =>
      _conversions.coerce(
        _conversions.cast(value, from, to) ?? _unsupported(node),
        .reference,
      );
}
