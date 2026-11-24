import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'scope.dart';

/// Translates assertions, which programs check if they are compiled so.
final class AssertionTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
) {
  late final _conversions = Conversions(_scope, _builder);

  void check(Assertion node) {
    final library = _builder.library;
    if (!_scope.checksAssertions || library.isInSdk) return;
    final condition = node.condition, unit = _builder.unit;
    final types = _conversions.types;
    _builder.unless(_evaluator.valueTo(condition, types.boolType), () {
      final message = switch (node.message) {
        null => _builder.add(HirNull()),
        final message => _evaluator.valueAsObject(message, types.dynamicType),
      };
      final at = unit.problem(condition, '');
      final uri = library.uri.isScheme('package')
          ? library.uri
          : Uri.file(unit.path);
      _builder.call(
        HirCall(_scope.runtime('throwAssertion'), [
          _builder.add(_scope.text(unit.textOf(condition))),
          _builder.add(_scope.text('$uri')),
          _builder.add(HirConst(at.line)),
          _builder.add(HirConst(at.column)),
          message,
        ]),
      );
    });
  }
}
