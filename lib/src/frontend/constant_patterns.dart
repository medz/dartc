// Reuse the pinned analyzer's pattern-space conversion and exhaustiveness rules.
// ignore_for_file: experimental_member_use, implementation_imports

import 'package:_fe_analyzer_shared/src/exhaustiveness/exhaustive.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart' show FieldElement;
import 'package:analyzer/src/dart/ast/ast.dart' show CaseNodeImpl;
import 'package:analyzer/src/dart/constant/value.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer/src/generated/exhaustiveness.dart';

/// Checks pattern coverage and duplicate keys with the evaluated constants.
final class ConstantPatterns(
  final ResolvedUnitResult unit,
  final DartObjectImpl Function(FieldElement) evaluateEnum,
) {
  final constants = <ConstantPattern, DartObjectImpl>{};
  final keys = <Expression, DartObjectImpl>{};
  late final _library = unit.libraryElement as LibraryElementImpl;
  late final _cache = _PatternCache(_library, _EnumConstants(evaluateEnum));

  static final errors = {
    diag.nonExhaustiveSwitchExpression,
    diag.nonExhaustiveSwitchExpressionPrivate,
    diag.nonExhaustiveSwitchStatement,
    diag.nonExhaustiveSwitchStatementPrivate,
    diag.equalKeysInMapPattern,
  };

  void checkMap(MapPattern pattern) {
    final seen = <DartObjectImpl>[];
    for (final entry in pattern.elements.whereType<MapPatternEntry>()) {
      final value = keys[entry.key2]!;
      _known(value);
      for (final previous in seen) {
        if (value.isIdentical2(_library.typeSystem, previous).toBoolValue() ==
                true ||
            value.hasPrimitiveEquality(_library.featureSet) &&
                previous.hasPrimitiveEquality(_library.featureSet) &&
                value == previous) {
          _fail(entry.key2, 'The map pattern contains equal keys.');
        }
      }
      seen.add(value);
    }
  }

  bool checkSwitch(AstNode node) {
    if (!_library.featureSet.isEnabled(Feature.patterns)) return false;
    final (expression, cases, required) = switch (node) {
      SwitchExpression(:final expression2, :final cases) => (
        expression2,
        cases,
        true,
      ),
      SwitchStatement(:final expression2, :final members) => (
        expression2,
        members,
        _library.typeSystem.isAlwaysExhaustive(
          expression2.staticType as TypeImpl,
        ),
      ),
      _ => throw ArgumentError.value(node, 'node', 'Expected a switch.'),
    };
    if (!required || cases.any((node) => node is SwitchDefault)) return true;
    final shape = _cache.getShapeForType(expression.staticType as TypeImpl);
    final converter = PatternConverter(
      languageVersion: _library.languageVersion.effective,
      featureSet: _library.featureSet,
      cache: _cache,
      mapPatternKeyValues: keys,
      constantPatternValues: constants,
    );
    final patterns = cases.whereType<CaseNodeImpl>().toList();
    final spaces = [
      for (final node in patterns)
        converter.createRootSpace(shape, node.guardedPattern.pattern),
    ];
    if (converter.hasInvalidType) return false;
    final missing = computeExhaustiveness(_cache, shape, [
      for (final node in patterns) node.guardedPattern.whenClause != null,
    ], spaces);
    if (missing != null) {
      _fail(
        node,
        'The switch is not exhaustive: ${missing.witnesses.first.asWitness}.',
      );
    }
    return true;
  }

  void constant(ConstantPattern node, DartObjectImpl value) {
    _known(value);
    constants[node] = value;
  }

  void _known(DartObjectImpl value) {
    if (value.isUnknown) {
      throw UnsupportedError('A constant pattern value is unknown.');
    }
  }

  Never _fail(AstNode node, String message) =>
      throw FormatException('${unit.uri}: $message', unit.content, node.offset);
}

final class _PatternCache(
  LibraryElementImpl library,
  final _EnumConstants _enums,
) extends AnalyzerExhaustivenessCache {
  this : super(library.typeSystem, library);

  @override
  AnalyzerEnumOperations get enumOperations => _enums;
}

final class _EnumConstants(final DartObjectImpl Function(FieldElement) evaluate)
    extends AnalyzerEnumOperations {
  @override
  DartObjectImpl getEnumElementValue(FieldElement field) => evaluate(field);
}
