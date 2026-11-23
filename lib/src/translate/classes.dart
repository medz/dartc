import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'levels.dart';
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
            case MixinDeclaration(:final declaredFragment?):
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

/// Where objects keep the value of a variable, and whether it has one if that
/// is not certain.
typedef FieldPlace = ({HirField value, HirField? isSet});

/// The program's classes and their fields.
final class ClassTable(final Declarations _declarations) {
  final levels = LevelTable();
  final _classes = <Level, HirClass>{};
  final _fields = <(Level, FieldElement), FieldPlace>{};
  final _argumentFields = <Level, HirField>{};

  HirClass classOf(ClassElement element) => atLevel(levels.of(element));

  /// The class whose objects have the members of [level] and before.
  HirClass atLevel(Level level) => _classes[level] ??= _class(level);

  /// A field of [level], of which objects are created.
  FieldPlace fieldOf(Level level, FieldElement element) {
    atLevel(level);
    return _fields[(level, element.baseElement)]!;
  }

  HirClass _class(Level level) {
    final Level(:element, :class_, :superLevel) = level;
    CompileFailure unsupported(String what) =>
        _declarations.unsupported(class_, what);
    if (element.library.isInSdk) return _sdkClass(element);
    if (element is ClassElement && element.primaryConstructor != null) {
      throw unsupported('primary constructors');
    }
    final below = superLevel!.element;
    final isBase = below.library.isDartCore && below.name == 'Error';
    final isObject = below is ClassElement && below.isDartCoreObject;
    if (below.library.isInSdk && !isObject && !isBase) {
      throw unsupported('extending ${below.name} of the SDK');
    }
    return HirClass(
      level.isMixin
          ? '${class_.displayName} with ${element.displayName}'
          : element.displayName,
      below.library.isInSdk ? null : atLevel(superLevel),
      [
        ?_arguments(level),
        for (final field in instanceFields(element)) ..._field(level, field),
      ],
    );
  }

  /// A number, an error thrown by the program itself, or a stack trace.
  static HirClass _sdkClass(InterfaceElement element) =>
      HirClass(element.displayName, null, switch (element.name) {
        'StackTrace' => const [],
        'int' => [HirField('value', .integer)],
        'double' => [HirField('value', .float)],
        'bool' => [HirField('value', .boolean)],
        'TypeError' || 'NoSuchMethodError' => [
          HirField('number', .integer),
          HirField('object', .reference),
          HirField('type', .reference),
        ],
        _ => [HirField('number', .integer)],
      });

  /// Where objects keep the type arguments of [level], if it has any.
  HirField? argumentsOf(Level level) {
    atLevel(level);
    return _argumentFields[level];
  }

  HirField? _arguments(Level level) {
    if (level.element.typeParameters.isEmpty) return null;
    return _argumentFields[level] = HirField(
      '${level.element.displayName} types',
      .reference,
    );
  }

  List<HirField> _field(Level level, FieldElement element) {
    CompileFailure unsupported(String what) =>
        _declarations.unsupported(element, what);
    final type =
        valueType(element.type) ??
        (throw unsupported('a field of type ${element.type}'));
    final name = element.displayName;
    final value = HirField(name, type);
    final isSet = element.isLate ? HirField('$name is set', .boolean) : null;
    _fields[(level, element)] = (value: value, isSet: isSet);
    return [value, ?isSet];
  }

  /// The fields that [class_] itself adds to objects, in order.
  static Iterable<FieldElement> instanceFields(InterfaceElement class_) =>
      class_.fields.where(
        (field) =>
            !field.isStatic &&
            field.isOriginDeclaration &&
            !field.isAbstract &&
            !field.isExternal,
      );
}
