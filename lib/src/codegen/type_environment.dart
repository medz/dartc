import 'package:dartc/ir.dart';

/// Lexical type inputs actually consumed by the selected executable bodies.
///
/// Runtime type descriptors retain their full language identity. This plan only
/// controls hidden call arguments. Unknown and generated entries retain their
/// declared convention; analyzed bodies grow demands from actual reification.
final class TypeEnvironment(Iterable<FunctionTarget> functions) {
  final _functions = functions.toSet();
  final _parameters = <FunctionTarget, Set<int>>{};
  final _owners = <FunctionTarget>{};
  final _lexical = <FunctionTarget, Set<TypeParameterType>>{};

  /// Changes whenever a body reveals another required input.
  int revision = 0;

  Iterable<int> parametersOf(FunctionTarget target) sync* {
    for (var i = 0; i < target.typeParameters.length; i++) {
      if (!_functions.contains(target) ||
          (_parameters[target]?.contains(i) ?? false)) {
        yield i;
      }
    }
  }

  Iterable<TypeParameterType> lexicalParametersOf(FunctionTarget target) sync* {
    if (target.kind != .closure) return;
    for (final parameter in target.capturedTypeParameters) {
      if (!_functions.contains(target) ||
          (_lexical[target]?.contains(parameter) ?? false)) {
        yield parameter;
      }
    }
  }

  void requireLexicalParameter(
    FunctionTarget target,
    TypeParameterType parameter,
  ) {
    if (target.kind != .closure ||
        !target.capturedTypeParameters.contains(parameter)) {
      throw ArgumentError('Not a captured lexical type input.');
    }
    if (_functions.contains(target) &&
        (_lexical[target] ??= {}).add(parameter)) {
      revision++;
    }
  }

  bool ownerOf(FunctionTarget target) =>
      target.kind == .factory &&
      target.owner!.typeParameters.isNotEmpty &&
      (!_functions.contains(target) || _owners.contains(target));

  void requireParameter(FunctionTarget target, int index) {
    RangeError.checkValidIndex(index, target.typeParameters);
    if (_functions.contains(target) &&
        (_parameters[target] ??= {}).add(index)) {
      revision++;
    }
  }

  void requireOwner(FunctionTarget target) {
    if (target.kind != .factory || target.owner!.typeParameters.isEmpty) {
      throw ArgumentError('Only a generic factory has an owner input.');
    }
    if (_functions.contains(target) && _owners.add(target)) revision++;
  }
}
