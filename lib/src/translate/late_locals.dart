import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'captures.dart';
import 'environment.dart';
import 'late.dart';
import 'scope.dart';

/// Translates `late` local variables, each of which has a cell of its own.
final class LateTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  /// Declares [variable], of which [node] has the initializer.
  ///
  /// The cell then also keeps what that uses.
  void declare(
    VariableDeclaration node,
    VariableElement variable,
    HirType type,
  ) {
    final initializer = node.initializer;
    final name = variable.displayName;
    final value = HirField(name, type);
    final isSet = HirField('$name is set', .boolean);
    final environment = initializer == null
        ? null
        : Environment.of(
            _builder,
            node,
            _scope.capturesOf(declarationOf(node)),
            name: variable,
          );
    final class_ = HirClass('late $name', null, [
      value,
      isSet,
      ...?environment?.fields,
    ]);
    final getter = initializer == null
        ? null
        : HirFunction('${_builder.function.name}.$name', [.reference], type);
    _scope.addLocalClass(class_);
    _builder.locals.lates[variable] = LateLocal(value, isSet, getter);
    if (getter != null) {
      _scope.addLocalFunction(getter);
      _scope.schedule(() {
        final builder = environment!.build(
          getter,
          const [],
          returnType: variable.type,
        );
        final cell = builder.inputs.single;
        builder.bind(variable, cell, type);
        LateAccess(
          _scope,
          builder,
          variable,
          FieldStorage(value, isSet, cell),
        ).returnValue((type) => _scope.evaluate(builder, initializer!, type));
        builder.finish();
      });
    }
    final cell = _builder.create(class_);
    environment?.store(cell);
    _builder.add(HirStore(isSet, cell, _builder.add(HirConst(false))));
    _builder.bind(variable, cell, type);
  }

  /// Reads [variable], or returns null if it is not `late`.
  HirValue? read(Element variable) {
    final getter = _builder.locals.lates[variable]?.getter;
    if (getter == null) return _access(variable)?.read();
    return _builder.call(HirCall(getter, [_builder.raw(variable)]));
  }

  /// Assigns [value] to [variable], if that is `late`.
  bool write(Element variable, HirValue value) {
    final access = _access(variable);
    access?.write(value);
    return access != null;
  }

  LateAccess? _access(Element variable) {
    final local = _builder.locals.lates[variable];
    if (local == null) return null;
    return LateAccess(
      _scope,
      _builder,
      variable as VariableElement,
      FieldStorage(local.value, local.isSet, _builder.raw(variable)),
    );
  }
}
