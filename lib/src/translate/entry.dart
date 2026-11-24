import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'builder.dart';

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

/// Starts the program with [main], then does what that left to be done later
/// with [eventLoop], if there is anything.
HirFunction startFunction(HirFunction main, HirFunction? eventLoop) {
  final block = HirBlock()..add(HirCall(main, const []));
  if (eventLoop != null) block.add(HirCall(eventLoop, const []));
  block.end(HirReturn());
  return HirFunction('start', const [])..define([block]);
}
