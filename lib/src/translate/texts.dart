import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'scope.dart';

/// Translates strings.
final class TextTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
) {
  HirValue string(StringLiteral node) {
    if (node.stringValue case final text?) {
      return _builder.add(_scope.text(text));
    }
    final parts = [
      for (final part in _partsOf(node))
        part is Expression
            ? _evaluator.valueAs(part, .reference)
            : _builder.add(_scope.text(part as String)),
    ];
    if (parts case [final single]) {
      return _builder.call(
        HirCall(_scope.runtime('interpolateSingle'), [single]),
      )!;
    }
    return _builder.call(
      HirCall(_scope.runtime('interpolate'), [
        _scope.list(_builder, _builder.library.typeProvider.dynamicType, parts),
      ]),
    )!;
  }

  /// The texts and expressions that [node] is made of.
  static Iterable<Object> _partsOf(StringLiteral node) sync* {
    switch (node) {
      case SimpleStringLiteral(:final value):
        yield value;
      case AdjacentStrings(:final strings):
        for (final string in strings) {
          yield* _partsOf(string);
        }
      case StringInterpolation(:final elements):
        for (final element in elements) {
          switch (element) {
            case InterpolationString(:final value):
              if (value.isNotEmpty) yield value;
            case InterpolationExpression(:final expression):
              yield expression;
          }
        }
    }
  }
}
