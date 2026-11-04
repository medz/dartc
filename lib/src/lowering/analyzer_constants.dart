import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

// The analyzer's public DartObject API does not expose instantiated function
// arguments. A signature cannot recover unused (phantom) arguments or alias
// identity. Keep this analyzer 14.7 compatibility boundary separate from IR.
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
