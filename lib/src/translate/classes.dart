import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';

import 'levels.dart';
import 'members.dart';
import 'types.dart';

/// Where the program declares each of its elements.
final class Declarations(Iterable<SourceLibrary> libraries) {
  final _nodes = <Element, (SourceUnit, AstNode)>{};

  this {
    for (final library in libraries) {
      for (final unit in library.units) {
        for (final declaration in unit.ast.declarations) {
          _addPrimary(unit, declaration);
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
            case EnumDeclaration(:final declaredFragment?):
              _nodes[declaredFragment.element] = (unit, declaration);
              for (final member in declaration.body.members) {
                _addMember(unit, member);
              }
            case ExtensionDeclaration(:final declaredFragment?):
              _nodes[declaredFragment.element] = (unit, declaration);
              for (final member in declaration.body.members) {
                _addMember(unit, member);
              }
            case ExtensionTypeDeclaration(:final declaredFragment?):
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

  void _addPrimary(SourceUnit unit, AstNode declaration) {
    final part = switch (declaration) {
      ClassDeclaration(:final namePart) ||
      EnumDeclaration(:final namePart) ||
      ExtensionTypeDeclaration(:final namePart) => namePart,
      _ => null,
    };
    if (part case PrimaryConstructorDeclaration(:final declaredFragment?)) {
      _nodes[declaredFragment.element] = (unit, declaration);
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
      final element = variable.declaredFragment?.element;
      if (element == null) continue;
      _nodes[element] = (unit, variable);
      if (element is! PropertyInducingElement || !isExternalVariable(element)) {
        continue;
      }
      for (final accessor in [?element.getter, ?element.setter]) {
        _nodes[accessor] = (unit, variable);
      }
    }
  }

  (SourceUnit, AstNode)? operator [](Element element) => _nodes[element];

  /// What the objects of [class_] hold besides fields.
  HirElements? elementsOf(InterfaceElement class_) =>
      switch (pragmaOf(class_, 'dartc:elements')) {
        final kind? => HirElements.values.byName(kind),
        null => null,
      };

  /// How objects of [class_] are weak, if they are.
  HirWeakness? weaknessOf(InterfaceElement class_) =>
      switch (pragmaOf(class_, 'dartc:weak')) {
        final kind? => HirWeakness.values.byName(kind),
        null => null,
      };

  /// What the annotation `@pragma` of [element] says about [name].
  String? pragmaOf(Element element, String name) {
    final node = switch (_nodes[element]?.$2) {
      VariableDeclaration(parent: VariableDeclarationList(:final parent)) =>
        parent,
      final node => node,
    };
    if (node is! AnnotatedNode) return null;
    for (final annotation in node.metadata) {
      final arguments = annotation.arguments?.arguments ?? const <Argument>[];
      final texts = [
        for (final argument in arguments)
          if (argument.argumentExpression case StringLiteral(
            :final stringValue?,
          ))
            stringValue,
      ];
      if (annotation.name.name == 'pragma' && texts.firstOrNull == name) {
        if (name == 'dartc:weak' && !element.library!.isInSdk) {
          throw unsupported(element, 'the dartc:weak pragma outside the SDK');
        }
        return texts.elementAtOrNull(1) ?? '';
      }
    }
    return null;
  }

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
      ClassTypeAlias(:final name) ||
      EnumDeclaration(
        namePart: ClassNamePart(typeName: final name),
      ) => name.offset,
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

  HirClass classOf(InterfaceElement element) => atLevel(levels.of(element));

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
    if (plainType(element) case final plain?) {
      return HirClass(element.displayName, null, [HirField('value', plain)]);
    }
    final below = superLevel?.element;
    final isRoot =
        below == null || below is ClassElement && below.isDartCoreObject;
    if (!isRoot && _declarations[below] == null) {
      throw unsupported('extending ${below.name} of the SDK');
    }
    return HirClass(
      level.isMixin
          ? '${class_.displayName} with ${element.displayName}'
          : element.displayName,
      isRoot ? null : atLevel(superLevel!),
      [
        ?_arguments(level),
        for (final field in instanceFields(element)) ..._field(level, field),
      ],
      level.isMixin ? null : _declarations.elementsOf(class_),
      level.isMixin ? null : _declarations.weaknessOf(class_),
    );
  }

  /// Where objects keep the type arguments of [level], if it has any.
  HirField? argumentsOf(Level level) {
    atLevel(level);
    return _argumentFields[level];
  }

  /// The new field for the type arguments of [level], if it needs one.
  ///
  /// Those of mixins are known where they are mixed in.
  HirField? _arguments(Level level) {
    if (level.isMixin || level.element.typeParameters.isEmpty) return null;
    final superclass = level.class_.supertype!;
    final own = level.type.typeArguments, given = superclass.typeArguments;
    final isSame =
        own.length == given.length &&
        own.indexed.every((e) => e.$2 == given[e.$1]);
    if (isSame) {
      final below = levels.of(superclass.element);
      _argumentFields[level] = argumentsOf(below)!;
      return null;
    }
    return _argumentFields[level] = HirField(
      '${level.element.displayName} types',
      .reference,
      isFinal: true,
    );
  }

  List<HirField> _field(Level level, FieldElement element) {
    CompileFailure unsupported(String what) =>
        _declarations.unsupported(element, what);
    final type =
        valueType(element.type) ??
        (throw unsupported('a field of type ${element.type}'));
    final name = element.displayName;
    final value = HirField(
      name,
      type,
      isFinal: element.isFinal && !element.isLate,
      isWeak: _declarations.pragmaOf(element, 'dartc:weak') != null,
    );
    final isSet = element.isLate ? HirField('$name is set', .boolean) : null;
    _fields[(level, element)] = (value: value, isSet: isSet);
    return [value, ?isSet];
  }

  /// The fields that [class_] itself adds to objects, in order.
  static Iterable<FieldElement> instanceFields(InterfaceElement class_) =>
      class_.fields.where(
        (field) =>
            !field.isStatic &&
            (field.isOriginDeclaration ||
                field.isOriginDeclaringFormalParameter) &&
            !field.isAbstract &&
            !field.isExternal,
      );
}
