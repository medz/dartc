import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

// The public analyzer API omits function-constant arguments/alias identity and
// pattern context schemas. Keep these analyzer 14.7 metadata reads isolated
// instead of reconstructing inference or identity from lossy public types.
// ignore: implementation_imports
import 'package:analyzer/src/dart/ast/ast.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type_schema_elimination.dart'
    as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/constant/value.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/element.dart' as internal;

/// Reads the exact arguments retained by constant function instantiation.
List<DartType>? constantFunctionArguments(DartObject value) {
  if (value is! internal.DartObjectImpl ||
      value.state is! internal.FunctionState) {
    throw UnsupportedError('Analyzer function constant metadata unavailable.');
  }
  return (value.state as internal.FunctionState).typeArguments;
}

/// Tests the alias identity without inspecting or reconstructing private state.
bool constantFunctionUsesAlias(DartObject value, TypeAliasElement alias) {
  if (value is! internal.DartObjectImpl ||
      value.state is! internal.FunctionState ||
      alias is! internal.TypeAliasElementImpl) {
    throw UnsupportedError('Analyzer constructor alias metadata unavailable.');
  }
  final state = value.state as internal.FunctionState;
  return state ==
      internal.FunctionState(
        state.element,
        typeArguments: state.typeArguments,
        viaTypeAlias: alias,
      );
}

/// Whether a function constant retains a distinct constructor alias identity.
bool constantFunctionHasAlias(DartObject value) {
  if (value is! internal.DartObjectImpl ||
      value.state is! internal.FunctionState) {
    throw UnsupportedError('Analyzer constructor alias metadata unavailable.');
  }
  final state = value.state as internal.FunctionState;
  return state !=
      internal.FunctionState(state.element, typeArguments: state.typeArguments);
}

/// The contextual type applied to a declaration/assignment's RHS expression.
/// For-in patterns do not apply a context schema to each iterated value.
DartType? patternContextType(ast.DartPattern pattern) {
  final schema = switch (pattern.parent) {
    internal.PatternAssignmentImpl(:final patternTypeSchema) ||
    internal.PatternVariableDeclarationImpl(
      :final patternTypeSchema,
    ) => patternTypeSchema,
    _ => null,
  };
  return schema == null
      ? null
      : internal.TypeSchemaEliminationVisitor.run(
          topType: internal.DynamicTypeImpl.instance,
          bottomType: internal.NeverTypeImpl.instance,
          isLeastClosure: false,
          schema: schema,
        );
}
