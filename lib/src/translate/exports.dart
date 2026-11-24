import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'conversions.dart';
import 'native_scope.dart';
import 'native_types.dart';
import 'native_values.dart';
import 'scope.dart';
import 'types.dart';

/// A function that a library exports: its name in C, and its type there.
typedef Export = ({
  String name,
  TopLevelFunctionElement element,
  FunctionType native,
  SourceUnit unit,
  FunctionDeclaration node,
});

/// The functions that [program] exports.
List<Export> exportsOf(SourceProgram program) => [
  for (final library in program.libraries)
    for (final unit in library.units)
      for (final node in unit.ast.declarations)
        if (node is FunctionDeclaration)
          ?_exportOf(unit, node)
        else if (_hasOther(node))
          throw unit.unsupported(node, 'exporting members'),
];

/// Whether [declaration] has something in it that is to be exported.
bool _hasOther(CompilationUnitMember declaration) {
  final element = declaration.declaredFragment?.element;
  return element is InstanceElement &&
      element.methods.any((method) => _annotationOf(method) != null);
}

/// What says that [element] is exported, if it is.
DartObject? _annotationOf(Element element) {
  for (final annotation in element.metadata.annotations) {
    final value = annotation.computeConstantValue();
    final type = value?.type?.element;
    if (type?.name == 'Export' &&
        '${type?.library?.uri}' ==
            'package:dartc/src/interop/annotation.dart') {
      return value;
    }
  }
  return null;
}

Export? _exportOf(SourceUnit unit, FunctionDeclaration node) {
  final element = node.declaredFragment!.element;
  final value = _annotationOf(element);
  if (value == null) return null;
  final native = (value.type! as InterfaceType).typeArguments.single;
  if (element is! TopLevelFunctionElement || native is! FunctionType) {
    throw unit.unsupported(node, 'exporting this');
  }
  return (
    name: value.getField('symbol')?.toStringValue() ?? element.displayName,
    element: element,
    native: native,
    unit: unit,
    node: node,
  );
}

/// Makes what does the work of exported functions.
final class ExportTable(final ProgramScope _scope) {
  final _functions = <String, HirFunction>{};

  /// What does their work, by their names.
  Map<String, HirFunction> get functions => _functions;

  NativeScope get _natives => _scope.natives;

  /// Adds [export].
  void add(Export export) {
    final (:name, :element, :native, :unit, :node) = export;
    Never reject(String what) => throw unit.unsupported(node, what);
    final signature = _natives.types.signature(native);
    if (signature == null || signature.fixedCount != null) {
      reject('exporting a function of type $native');
    }
    final isPlain =
        element.typeParameters.isEmpty &&
        element.formalParameters.every((p) => p.isRequiredPositional) &&
        element.formalParameters.length == signature.parameters.length &&
        !node.functionExpression.body.isAsynchronous &&
        !node.functionExpression.body.isGenerator;
    if (!isPlain) reject('exporting this kind of function');
    for (final (i, parameter) in element.formalParameters.indexed) {
      if (_fits(signature.parameters[i], parameter.type)) continue;
      reject('exporting a parameter of type ${parameter.type}');
    }
    final isVoid = signature.result is NativeVoid;
    if (!isVoid && !_fits(signature.result, element.returnType)) {
      reject('exporting a result of type ${element.returnType}');
    }
    if (!_isName(name)) reject("exporting what is called '$name'");
    if (_functions.containsKey(name)) reject("exporting '$name' twice");
    _functions[name] = _make(export, signature);
  }

  static final _names = RegExp(r'^[A-Za-z_][A-Za-z_0-9]*$');

  static bool _isName(String name) => _names.hasMatch(name);

  /// Whether a value of [native] is one of [type] in Dart.
  static bool _fits(NativeType native, DartType type) => switch (native) {
    NativeInteger() => type.isDartCoreInt,
    NativeBoolean() => type.isDartCoreBool,
    NativeFloating() => type.isDartCoreDouble,
    NativePointer() =>
      type is InterfaceType &&
          NativeTypes.isFfi(type.element) &&
          type.element.name == 'Pointer' &&
          type.nullabilitySuffix == .none,
    NativeCompound(:final name) =>
      type is InterfaceType &&
          type.element.displayName == name &&
          type.nullabilitySuffix == .none,
    _ => false,
  };

  HirFunction _make(Export export, NativeSignature signature) {
    final (:name, :element, native: _, :unit, node: _) = export;
    final passing = _scope.natives.types.passing(signature);
    final function = HirFunction('export $name', const [.integer, .integer]);
    final target = _scope.functionOf(element)!;
    _scope.schedule(() {
      final builder = FunctionBuilder(unit, function, const []);
      final values = NativeValues(_scope, builder);
      final conversions = Conversions(_scope, builder);
      final [block, stack] = builder.inputs;
      final result = builder.call(
        HirCall(target, [
          for (final (i, type) in signature.parameters.indexed)
            conversions.coerce(
              values.load(
                block,
                passing.parameters[i],
                type,
                element.formalParameters[i].type,
                stack: stack,
              ),
              target.parameters[i],
            ),
        ]),
      );
      if (result != null && signature.result is! NativeVoid) {
        final type = valueType(element.returnType)!;
        values.storeResult(
          block,
          passing.result,
          signature.result,
          conversions.coerce(result, type),
        );
      }
      builder.finish();
    });
    return function;
  }
}
