import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'dynamic_shape.dart';
import 'dynamic_table.dart';
import 'scope.dart';

/// Translates uses of members of objects that can be anything.
final class DynamicTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
) {
  late final _conversions = Conversions(_scope, _builder);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  HirValue _use(
    AstNode node,
    HirValue object,
    DynamicUse use,
    String name, [
    List<HirValue> positional = const [],
    Map<String, HirValue> named = const {},
    (HirValue, int)? types,
  ]) {
    final names = named.keys.toList()..sort();
    return dynamicUse(
      _scope,
      _builder,
      _conversions.coerce(object, .reference),
      DynamicShape(
        use,
        name,
        name.startsWith('_') ? _builder.library : null,
        positional.length,
        names,
        (what) => _unsupported(node, what),
        types: types?.$2 ?? 0,
      ),
      [
        ?types?.$1,
        for (final value in positional) _conversions.coerce(value, .reference),
        for (final name in names) _conversions.coerce(named[name]!, .reference),
      ],
    );
  }

  HirValue get(AstNode node, HirValue object, String name) =>
      _use(node, object, .get, name);

  void set(AstNode node, HirValue object, String name, HirValue value) =>
      _use(node, object, .set, name, [value]);

  /// Applies an operator by the name of its member.
  HirValue operate(
    AstNode node,
    HirValue object,
    String name,
    List<HirValue> operands,
  ) => _use(node, object, .call, name, operands);

  /// Calls the member [name] of [object], or [object] itself.
  HirValue call(
    AstNode node,
    HirValue object,
    String name,
    ArgumentList list, {
    TypeArgumentList? types,
  }) {
    final given = [
      for (final type in types?.arguments ?? const <TypeAnnotation>[])
        type.type!,
    ];
    final typeList = given.isEmpty ? null : _scope.typeList(_builder, given);
    if (given.isNotEmpty && typeList == null) {
      _unsupported(node, 'these type arguments');
    }
    final positional = <HirValue>[], named = <String, HirValue>{};
    for (final argument in list.arguments) {
      final value = _evaluator.value(
        argument.argumentExpression,
        placeholder: .reference,
      );
      if (argument is NamedArgument) {
        named[argument.name.lexeme] = value;
      } else {
        positional.add(value);
      }
    }
    return _use(
      node,
      object,
      .call,
      name,
      positional,
      named,
      typeList == null ? null : (typeList, given.length),
    );
  }
}
