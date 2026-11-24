import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'conversions.dart';
import 'scope.dart';

/// Throws [CompileFailure] if [program] imports something in a way that is not
/// supported yet.
void checkImports(SourceProgram program) {
  for (final library in program.libraries) {
    for (final unit in library.units) {
      for (final directive in unit.ast.directives) {
        if (directive is ImportDirective && directive.deferredKeyword != null) {
          throw unit.unsupported(directive, 'deferred imports');
        }
      }
    }
  }
}

/// Makes the function that starts the program with [_main], which is
/// [_element].
final class EntryTranslator(
  final ProgramScope _scope,
  final SourceUnit _unit,
  final ExecutableElement _element,
  final HirFunction _main,
) {
  final function = HirFunction('start', const []);
  late final _builder = FunctionBuilder(_unit, function, const []);

  /// Adds the call of `main`.
  void begin() {
    final conversions = Conversions(_scope, _builder);
    var position = 0;
    HirValue argument(FormalParameterElement parameter) {
      if (parameter.isNamed || position > 1) {
        return _builder.add(_scope.defaultOf(parameter));
      }
      final value = position++ == 0
          ? _builder.call(HirCall(_scope.runtime('mainArguments'), const []))!
          : _builder.add(HirNull());
      final type = conversions.types.dynamicType;
      return conversions.cast(
            value,
            type,
            parameter.type,
            ending: " of '${parameter.name}'",
          ) ??
          (throw StateError('No test for ${parameter.type}.'));
    }

    _builder.call(HirCall(_main, _element.formalParameters.map(argument)));
  }

  /// Does what `main` left to be done later with [eventLoop], if there is
  /// anything.
  void finish(HirFunction? eventLoop) {
    if (eventLoop != null) _builder.call(HirCall(eventLoop, const []));
    _builder.finish();
  }
}
