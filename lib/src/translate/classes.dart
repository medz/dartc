import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'types.dart';

/// Where the program declares each of its elements.
final class Declarations(Iterable<SourceLibrary> libraries) {
  final _nodes = <Element, (SourceUnit, AstNode)>{};

  this {
    for (final library in libraries) {
      for (final unit in library.units) {
        for (final declaration in unit.ast.declarations) {
          switch (declaration) {
            case FunctionDeclaration(:final declaredFragment?):
              _nodes[declaredFragment.element] = (unit, declaration);
            case TopLevelVariableDeclaration(:final variables):
              _addVariables(unit, variables);
            case ClassDeclaration(:final declaredFragment?):
              _nodes[declaredFragment.element] = (unit, declaration);
              for (final member in declaration.body.members) {
                _addMember(unit, member);
              }
            case ClassTypeAlias(:final declaredFragment?):
              _nodes[declaredFragment.element] = (unit, declaration);
            default:
              break;
          }
        }
      }
    }
  }

  void _addMember(SourceUnit unit, ClassMember member) {
    switch (member) {
      case MethodDeclaration(:final declaredFragment?):
        _nodes[declaredFragment.element] = (unit, member);
      case ConstructorDeclaration(:final declaredFragment?):
        _nodes[declaredFragment.element] = (unit, member);
      case FieldDeclaration(:final fields):
        _addVariables(unit, fields);
      default:
        break;
    }
  }

  void _addVariables(SourceUnit unit, VariableDeclarationList list) {
    for (final variable in list.variables) {
      if (variable.declaredFragment case final fragment?) {
        _nodes[fragment.element] = (unit, variable);
      }
    }
  }

  (SourceUnit, AstNode)? operator [](Element element) => _nodes[element];

  /// The failure to translate the declaration of [element].
  CompileFailure unsupported(Element element, String what) {
    // What is inside of functions has no place of its own here.
    Element? found = element;
    while (!_nodes.containsKey(found)) {
      found = found!.enclosingElement;
    }
    final (unit, node) = _nodes[found]!;
    final offset = switch (node) {
      FunctionDeclaration(:final name) ||
      MethodDeclaration(:final name) ||
      VariableDeclaration(:final name) => name.offset,
      ClassDeclaration(:final namePart) => namePart.typeName.offset,
      ClassTypeAlias(:final name) => name.offset,
      _ => node.offset,
    };
    return CompileFailure([
      unit.problemAt(offset, 'Not supported yet: $what.'),
    ]);
  }
}

/// The program's classes and their fields.
final class ClassTable(final Declarations _declarations) {
  final _classes = <ClassElement, HirClass>{};
  final _fields = <FieldElement, HirField>{};
  final _argumentFields = <ClassElement, HirField>{};

  HirClass classOf(ClassElement element) =>
      _classes[element] ??= _class(element);

  /// A field of a class that objects are created of, or of its superclass.
  HirField fieldOf(FieldElement element) => _fields[element.baseElement]!;

  HirClass _class(ClassElement element) {
    CompileFailure unsupported(String what) =>
        _declarations.unsupported(element, what);
    if (element.library.isInSdk) {
      // A number, an error thrown by the program itself, or a stack trace.
      return HirClass(element.displayName, null, switch (element.name) {
        'StackTrace' => const [],
        'int' => [HirField('value', .integer)],
        'double' => [HirField('value', .float)],
        'bool' => [HirField('value', .boolean)],
        'TypeError' => [
          HirField('number', .integer),
          HirField('object', .reference),
          HirField('type', .reference),
        ],
        _ => [HirField('number', .integer)],
      });
    }
    if (element.mixins.isNotEmpty) throw unsupported('mixins');
    if (element.primaryConstructor != null) {
      throw unsupported('primary constructors');
    }
    final superclass = element.supertype!.element as ClassElement;
    final isBase = superclass.library.isDartCore && superclass.name == 'Error';
    if (superclass.library.isInSdk && !superclass.isDartCoreObject && !isBase) {
      throw unsupported('extending ${superclass.name} of the SDK');
    }
    return HirClass(
      element.displayName,
      superclass.library.isInSdk ? null : classOf(superclass),
      [
        ?_arguments(element),
        for (final field in instanceFields(element)) _field(field),
      ],
    );
  }

  /// Where objects keep the type arguments of [element], if it is generic.
  HirField? argumentsOf(ClassElement element) {
    classOf(element);
    return _argumentFields[element];
  }

  HirField? _arguments(ClassElement element) {
    if (element.typeParameters.isEmpty) return null;
    return _argumentFields[element] = HirField(
      '${element.displayName} types',
      .reference,
    );
  }

  HirField _field(FieldElement element) {
    CompileFailure unsupported(String what) =>
        _declarations.unsupported(element, what);
    if (element.isLate) throw unsupported('late fields');
    final type =
        valueType(element.type) ??
        (throw unsupported('a field of type ${element.type}'));
    return _fields[element] = HirField(element.displayName, type);
  }

  /// The fields that [class_] itself adds to objects, in order.
  static Iterable<FieldElement> instanceFields(ClassElement class_) =>
      class_.fields.where(
        (field) =>
            !field.isStatic &&
            field.isOriginDeclaration &&
            !field.isAbstract &&
            !field.isExternal,
      );
}
