import '../ast.dart';
import '../constants.dart';
import '../ir.dart';
import '../initialization.dart';
import '../members.dart';
import '../resolve_type.dart';
import '../source.dart';
import '../symbols.dart';
import '../types.dart';
import 'parameters.dart';

const int classMethod = 0;
const int classGetter = 1;
const int classSetter = 2;

bool hasClassMember(MemberBinding member, int role) {
  if (role == classMethod) return member.method >= 0;
  if (role == classGetter) return member.getter >= 0 || member.field >= 0;
  return member.setter >= 0 || member.fieldSetter >= 0;
}

int classMemberFunction(MemberBinding member, int role) {
  if (role == classMethod) return member.method;
  return role == classGetter ? member.getter : member.setter;
}

bool hasConcreteClassMember(
  MemberBinding member,
  int role,
  List<AstFunction> declarations,
) {
  if (member.isStatic || !hasClassMember(member, role)) return false;
  final function = classMemberFunction(member, role);
  if (function < 0) return true;
  final syntax = declarations[function];
  return syntax.body != null || syntax.arrow != null;
}

MemberBinding? classImplementation(
  int owner,
  String name,
  int library,
  int role,
  List<ClassMembers> ownMembers,
  ClassMembers objectMembers,
  List<AstFunction> declarations,
) {
  while (owner >= 0) {
    final index = lookupMember(ownMembers[owner], name, library);
    if (index >= 0 &&
        hasConcreteClassMember(
          ownMembers[owner].members[index],
          role,
          declarations,
        ))
      return ownMembers[owner].members[index];
    final parent = classSuperclasses[owner];
    owner = typeIsClass(parent) ? typeArgument(parent) : -1;
  }
  final index = lookupMember(objectMembers, name, library);
  return index >= 0 && hasClassMember(objectMembers.members[index], role)
      ? objectMembers.members[index]
      : null;
}

class ClassSignature(
  final int result,
  final List<int> parameters,
  final List<AstParameter> formals,
  final List<int> typeParameters,
  final List<bool> covariantParameters,
);

ClassSignature classSignature(
  MemberBinding member,
  int role,
  List<AstFunction> declarations,
  List<int> fieldTypes,
) {
  final function = classMemberFunction(member, role);
  if (function >= 0) {
    final info = functions[function];
    return ClassSignature(
      info.result,
      info.parameterTypes.sublist(info.typeParameters.isEmpty ? 1 : 2),
      member.receiverParameter
          ? declarations[function].parameters.sublist(1)
          : declarations[function].parameters,
      info.typeParameters,
      role == classGetter ? const <bool>[] : member.covariantParameters,
    );
  }
  if (role == classGetter)
    return ClassSignature(
      fieldTypes[member.field],
      const <int>[],
      const <AstParameter>[],
      const <int>[],
      const <bool>[],
    );
  return ClassSignature(
    tVoid,
    <int>[fieldTypes[member.fieldSetter]],
    <AstParameter>[
      AstParameter(AstType('', const <AstType>[], 0), '', false, 0),
    ],
    const <int>[],
    member.covariantParameters,
  );
}

bool classCovariantParameter(ClassSignature signature, int parameter) =>
    parameter >= 0 &&
    parameter < signature.covariantParameters.length &&
    signature.covariantParameters[parameter];

bool classSignatureSubtype(
  ClassSignature actual,
  ClassSignature expected, [
  bool overriding = false,
]) {
  if (actual.typeParameters.length != expected.typeParameters.length)
    return false;
  for (var i = 0; i < actual.typeParameters.length; i++) {
    final bound = substituteType(
      typeParameterInfo(expected.typeParameters[i]).bound,
      expected.typeParameters,
      actual.typeParameters,
    );
    final actualBound = typeParameterInfo(actual.typeParameters[i]).bound;
    if (!typeIsSubtype(bound, actualBound) ||
        !typeIsSubtype(actualBound, bound))
      return false;
  }
  final result = substituteType(
    expected.result,
    expected.typeParameters,
    actual.typeParameters,
  );
  if (!typeIsSubtype(actual.result, result)) return false;
  for (var i = 0; i < expected.formals.length; i++) {
    final index = correspondingParameter(
      actual.formals,
      expected.formals[i],
      i,
    );
    if (index < 0) return false;
    final type = substituteType(
      expected.parameters[i],
      expected.typeParameters,
      actual.typeParameters,
    );
    if (!typeIsSubtype(type, actual.parameters[index]) &&
        !(overriding &&
            (classCovariantParameter(actual, index) ||
                classCovariantParameter(expected, i)) &&
            typeIsSubtype(actual.parameters[index], type)))
      return false;
  }
  for (var i = 0; i < actual.formals.length; i++) {
    final formal = actual.formals[i];
    if (formal.kind != astRequiredPositional && !formal.required) continue;
    final index = correspondingParameter(expected.formals, formal, i);
    if (index < 0) return false;
    final parent = expected.formals[index];
    if (parent.kind != astRequiredPositional && !parent.required) return false;
  }
  return true;
}

MemberBinding _copyMember(MemberBinding member) {
  final copy = MemberBinding(member.name, member.library);
  copy.isStatic = member.isStatic;
  copy.receiverParameter = member.receiverParameter;
  copy.method = member.method;
  copy.getter = member.getter;
  copy.setter = member.setter;
  copy.field = member.field;
  copy.fieldSetter = member.fieldSetter;
  copy.staticField = member.staticField;
  copy.covariantParameters = member.covariantParameters;
  return copy;
}

void _copyRole(MemberBinding target, MemberBinding source, int role) {
  if (role != classGetter)
    target.covariantParameters = source.covariantParameters;
  if (role == classMethod)
    target.method = source.method;
  else if (role == classGetter) {
    target.getter = source.getter;
    target.field = source.field;
  } else {
    target.setter = source.setter;
    target.fieldSetter = source.fieldSetter;
  }
}

void _inheritCovariance(
  MemberBinding member,
  int role,
  List<MemberBinding> candidates,
  List<AstFunction> declarations,
  List<int> fieldTypes,
) {
  if (role == classGetter) return;
  var inherits = false;
  for (final candidate in candidates)
    if (candidate.covariantParameters.isNotEmpty) inherits = true;
  if (!inherits) return;
  final signature = classSignature(member, role, declarations, fieldTypes);
  var flags = <bool>[...member.covariantParameters];
  for (final candidate in candidates) {
    if (candidate.covariantParameters.isEmpty) continue;
    final parent = classSignature(candidate, role, declarations, fieldTypes);
    for (var p = 0; p < parent.formals.length; p++) {
      if (!classCovariantParameter(parent, p)) continue;
      final index = correspondingParameter(
        signature.formals,
        parent.formals[p],
        p,
      );
      if (index < 0) continue;
      if (flags.isEmpty)
        flags = List<bool>.filled(signature.formals.length, false);
      flags[index] = true;
    }
  }
  member.covariantParameters = flags;
}

MemberBinding? _combinedMember(
  List<MemberBinding> candidates,
  int role,
  List<AstFunction> declarations,
  List<int> fieldTypes,
) {
  for (final candidate in candidates) {
    final signature = classSignature(candidate, role, declarations, fieldTypes);
    var suitable = true;
    for (final other in candidates)
      if (!classSignatureSubtype(
        signature,
        classSignature(other, role, declarations, fieldTypes),
      ))
        suitable = false;
    if (suitable) return candidate;
  }
  return null;
}

List<ClassMembers> checkClassInterfaces(
  SymbolTable symbols,
  List<AstClass> classes,
  List<int> order,
  List<ClassMembers> ownMembers,
  ClassMembers objectMembers,
  List<AstFunction> declarations,
  List<int> fieldTypes,
  List<AstVariable> fields,
  ConstantContext constants,
  List<ConstructorPlan> constructorPlans,
) {
  final views = <ClassMembers>[];
  for (var owner = 0; owner < ownMembers.length; owner++) {
    final own = ownMembers[owner];
    if (classSupertypes[owner].isEmpty) {
      views.add(own);
      continue;
    }
    final view = ClassMembers(<MemberBinding>[]);
    view.constructors = own.constructors;
    for (final member in own.members) view.members.add(_copyMember(member));
    views.add(view);
  }
  constants.classMembers = views;
  Never fail(int owner, String message) {
    sourceError(
      symbols.program,
      symbols.program.tokens[classes[owner].token],
      message,
    );
  }

  final states = List<int>.filled(classes.length, 0);
  final fieldReady = <bool>[for (final field in fields) field.type.name != ''];
  late void Function(int) check;
  void prepareConstructor(int function) {
    final info = functions[function];
    final owner = typeArgument(info.result);
    final parameters = declarations[function].parameters;
    for (var p = 0; p < parameters.length; p++) {
      final parameter = parameters[p];
      if (parameter.fieldFormal) {
        final field = ownMembers[owner]
            .members[lookupMember(ownMembers[owner], parameter.name)]
            .field;
        if (!fieldReady[field]) check(owner);
        if (parameter.type.name == '')
          info.parameterTypes[p + 1] = fieldTypes[field];
        else if (!typeIsSubtype(info.parameterTypes[p + 1], fieldTypes[field]))
          sourceError(
            symbols.program,
            symbols.program.tokens[parameter.token],
            'field-formal type must be a subtype of the field type',
          );
      }
      if (parameter.superFormal) check(typeArgument(classSuperclasses[owner]));
    }
    resolveConstructorSuperParameters(
      symbols,
      declarations,
      functions,
      constructorPlans,
      function,
    );
    info.callableType = -1;
  }

  check = (int owner) {
    if (states[owner] == 2) return;
    if (states[owner] == 1)
      fail(owner, 'cyclic constructor parameter inference');
    states[owner] = 1;
    for (final parent in classSupertypes[owner])
      if (typeIsClass(parent)) check(typeArgument(parent));
    for (final syntax in classes[owner].methods)
      if (syntax.isStatic && syntax.body == null && syntax.arrow == null)
        fail(owner, 'static method requires a body');
    final inherited = <MemberBinding>[];
    for (final parent in classSupertypes[owner]) {
      if (!typeIsClass(parent)) continue;
      for (final member in views[typeArgument(parent)].members)
        if (!member.isStatic) inherited.add(member);
    }
    final view = views[owner];
    void checkCovariance(
      MemberBinding member,
      int role,
      ClassSignature actual,
    ) {
      final signature = classSignature(member, role, declarations, fieldTypes);
      if (signature.covariantParameters.isEmpty &&
          actual.covariantParameters.isEmpty)
        return;
      final visited = List<bool>.filled(classes.length, false);
      void visit(int ancestor) {
        if (visited[ancestor]) return;
        visited[ancestor] = true;
        final index = lookupMember(
          ownMembers[ancestor],
          member.name,
          member.library,
        );
        if (index >= 0 &&
            !ownMembers[ancestor].members[index].isStatic &&
            hasClassMember(ownMembers[ancestor].members[index], role)) {
          final parent = classSignature(
            ownMembers[ancestor].members[index],
            role,
            declarations,
            fieldTypes,
          );
          for (var p = 0; p < actual.formals.length; p++) {
            final current = correspondingParameter(
              signature.formals,
              actual.formals[p],
              p,
            );
            if (!classCovariantParameter(actual, p) &&
                !classCovariantParameter(signature, current))
              continue;
            final other = correspondingParameter(
              parent.formals,
              actual.formals[p],
              p,
            );
            if (other < 0) continue;
            final type = substituteType(
              parent.parameters[other],
              parent.typeParameters,
              actual.typeParameters,
            );
            if (!typeIsSubtype(type, actual.parameters[p]) &&
                !typeIsSubtype(actual.parameters[p], type))
              fail(owner, 'incompatible covariant parameter of ' + member.name);
          }
        }
        for (final parent in classSupertypes[ancestor])
          if (typeIsClass(parent)) visit(typeArgument(parent));
      }

      for (final parent in classSupertypes[owner])
        if (typeIsClass(parent)) visit(typeArgument(parent));
    }

    for (final member in inherited) {
      var index = lookupMember(view, member.name, member.library);
      if (index < 0) {
        index = view.members.length;
        view.members.add(MemberBinding(member.name, member.library));
      }
      final target = view.members[index];
      if (target.isStatic)
        fail(owner, 'static member conflicts with instance interface');
    }
    for (final member in view.members) {
      if (member.isStatic) continue;
      final ownIndex = lookupMember(
        ownMembers[owner],
        member.name,
        member.library,
      );
      final own = ownIndex < 0 ? null : ownMembers[owner].members[ownIndex];
      final field = own == null ? -1 : own.field;
      final variable = field >= 0
          ? fields[field]
          : own == null || own.getter < 0
          ? null
          : declarations[own.getter].abstractField;
      final parameter = variable?.declaringParameter;
      if (variable != null && variable.type.name == '') {
        var type = -1;
        for (var role = classGetter; role <= classSetter; role++) {
          final candidates = <MemberBinding>[];
          for (final parent in inherited)
            if (parent.name == member.name &&
                (!member.name.startsWith('_') ||
                    parent.library == member.library) &&
                hasClassMember(parent, role))
              candidates.add(parent);
          if (candidates.isEmpty) continue;
          final selected = _combinedMember(
            candidates,
            role,
            declarations,
            fieldTypes,
          );
          if (selected == null)
            fail(
              owner,
              'cannot infer field from incompatible inherited signatures',
            );
          final signature = classSignature(
            selected,
            role,
            declarations,
            fieldTypes,
          );
          final inferred = role == classGetter
              ? signature.result
              : signature.parameters[0];
          if (type >= 0 && type != inferred)
            fail(
              owner,
              'cannot infer a mutable field from different getter and setter types',
            );
          type = inferred;
          if (!variable.hasSetter) break;
        }
        if (type < 0) {
          AstExpression? expression;
          if (parameter == null) {
            if (variable.initializer.isNotEmpty) {
              if (classes[owner].hasPrimary)
                fail(
                  owner,
                  'primary field initializer type inference is not yet supported',
                );
              expression = variable.initializer[0];
            }
          } else {
            expression = parameter.defaultValue;
          }
          final scope = constants.lexicalClass;
          constants.lexicalClass = owner;
          type = expression == null
              ? tNull
              : inferConstantType(constants, expression);
          constants.lexicalClass = scope;
          if (type == tNull)
            type = parameter == null ? tDynamic : nullableType(tObject);
        }
        if (field >= 0) {
          fieldTypes[field] = type;
          fieldReady[field] = true;
        } else {
          functions[own!.getter].result = type;
          if (variable.hasSetter)
            functions[own.setter].parameterTypes[1] = type;
        }
      }
      for (var role = classMethod; role <= classSetter; role++) {
        final candidates = <MemberBinding>[];
        for (final parent in inherited)
          if (parent.name == member.name &&
              (!member.name.startsWith('_') ||
                  parent.library == member.library) &&
              hasClassMember(parent, role))
            candidates.add(parent);
        if (candidates.isEmpty) continue;
        final selected = _combinedMember(
          candidates,
          role,
          declarations,
          fieldTypes,
        );
        if (own != null && hasClassMember(own, role)) {
          _inheritCovariance(
            member,
            role,
            candidates,
            declarations,
            fieldTypes,
          );
          final function = classMemberFunction(own, role);
          if (function >= 0 && selected == null) {
            final syntax = declarations[function];
            if (syntax.result.name == '' && !syntax.setter)
              fail(
                owner,
                'cannot infer result from incompatible inherited signatures',
              );
            for (var p = 0; p < syntax.parameters.length; p++) {
              if (syntax.parameters[p].type.name != '') continue;
              for (final candidate in candidates) {
                final parent = classSignature(
                  candidate,
                  role,
                  declarations,
                  fieldTypes,
                );
                if (correspondingParameter(
                      parent.formals,
                      syntax.parameters[p],
                      p,
                    ) >=
                    0)
                  fail(
                    owner,
                    'cannot infer parameter from incompatible inherited signatures',
                  );
              }
            }
          }
          if (function >= 0 &&
              selected != null &&
              declarations[function].abstractField == null) {
            final info = functions[function];
            final syntax = declarations[function];
            final parent = classSignature(
              selected,
              role,
              declarations,
              fieldTypes,
            );
            if (info.typeParameters.length == parent.typeParameters.length) {
              if (syntax.result.name == '' && !syntax.setter)
                info.result = substituteType(
                  parent.result,
                  parent.typeParameters,
                  info.typeParameters,
                );
              final offset = info.typeParameters.isEmpty ? 1 : 2;
              for (var p = 0; p < syntax.parameters.length; p++) {
                if (syntax.parameters[p].type.name != '') continue;
                final other = correspondingParameter(
                  parent.formals,
                  syntax.parameters[p],
                  p,
                );
                if (other >= 0)
                  info.parameterTypes[offset + p] = substituteType(
                    parent.parameters[other],
                    parent.typeParameters,
                    info.typeParameters,
                  );
              }
            }
          }
          final signature = classSignature(
            member,
            role,
            declarations,
            fieldTypes,
          );
          for (final parent in candidates)
            if (!classSignatureSubtype(
              signature,
              classSignature(parent, role, declarations, fieldTypes),
              true,
            ))
              fail(owner, 'invalid override of ' + member.name);
        } else {
          if (selected == null)
            fail(
              owner,
              'incompatible inherited member signatures: ' + member.name,
            );
          _copyRole(member, selected, role);
          _inheritCovariance(
            member,
            role,
            candidates,
            declarations,
            fieldTypes,
          );
        }
      }
      if (member.method >= 0 &&
          (hasClassMember(member, classGetter) ||
              hasClassMember(member, classSetter)))
        fail(owner, 'method conflicts with inherited accessor: ' + member.name);
      for (var role = classMethod; role <= classSetter; role++) {
        if (!hasClassMember(member, role)) continue;
        checkCovariance(
          member,
          role,
          classSignature(member, role, declarations, fieldTypes),
        );
        final implementation = classImplementation(
          owner,
          member.name,
          member.library,
          role,
          ownMembers,
          objectMembers,
          declarations,
        );
        final concrete =
            implementation != null &&
            classSignatureSubtype(
              classSignature(implementation, role, declarations, fieldTypes),
              classSignature(member, role, declarations, fieldTypes),
              true,
            );
        if (implementation != null)
          checkCovariance(
            member,
            role,
            classSignature(implementation, role, declarations, fieldTypes),
          );
        if (!classes[owner].isAbstract && !concrete)
          fail(owner, 'missing concrete implementation of ' + member.name);
      }
    }
    states[owner] = 2;
    for (final function in constants.classConstructors[owner])
      prepareConstructor(function);
  };

  constants.prepareConstructorTypes = prepareConstructor;
  for (final owner in order) check(owner);
  constants.prepareConstructorTypes = null;
  return views;
}

List<int> resolveClassInterfaces(SymbolTable symbols, List<AstClass> classes) {
  final parents = <List<int>>[];
  final supers = <int>[];
  final uses = <TypeApplication>[];
  // Looked up in dart:core itself so a user declaration cannot shadow it.
  final enumSymbol = symbolExportedDeclaration(symbols, sourceCore, 'Enum');
  final enumType =
      enumSymbol >= 0 && symbols.declarations[enumSymbol].kind == symbolClass
      ? classType(symbols.declarations[enumSymbol].target)
      : -1;
  for (final syntax in classes) {
    if (syntax.modifier != '' &&
        !sourceVersionAtLeast(
          symbols.program,
          symbols.program.tokens[syntax.token].source,
          3,
          0,
        ))
      sourceError(
        symbols.program,
        symbols.program.tokens[syntax.token],
        'class modifiers require language version 3.0',
      );
    final scope = classTypeParameters[parents.length];
    final types = <int>[];
    var superclass = tObject;
    if (syntax.superclass case final parent?) {
      superclass = resolveSuperinterface(symbols, parent, uses, scope);
      if (superclass != tObject && !typeIsClass(superclass))
        sourceError(
          symbols.program,
          symbols.program.tokens[parent.token],
          'this superclass type is not yet supported',
        );
    }
    supers.add(superclass);
    for (final interface in syntax.interfaces) {
      final type = resolveSuperinterface(symbols, interface, uses, scope);
      if (syntax.superclass != null && type == superclass)
        sourceError(
          symbols.program,
          symbols.program.tokens[interface.token],
          'class cannot occur in both extends and implements',
        );
      if (type != tObject && !typeIsClass(type))
        sourceError(
          symbols.program,
          symbols.program.tokens[interface.token],
          'this superinterface type is not yet supported',
        );
      for (final previous in types)
        if (previous == type)
          sourceError(
            symbols.program,
            symbols.program.tokens[interface.token],
            'duplicate implemented interface',
          );
      types.add(type);
    }
    if (syntax.isEnum) {
      if (enumType < 0)
        sourceError(
          symbols.program,
          symbols.program.tokens[syntax.token],
          'enums require the standard library',
        );
      var declared = false;
      for (final type in types) if (type == enumType) declared = true;
      if (!declared) types.add(enumType);
    }
    if (typeIsClass(superclass)) types.insert(0, superclass);
    parents.add(types);
  }
  final states = List<int>.filled(classes.length, 0);
  final order = <int>[];
  void visit(int owner) {
    if (states[owner] == 2) return;
    if (states[owner] == 1)
      sourceError(
        symbols.program,
        symbols.program.tokens[classes[owner].token],
        'cyclic class hierarchy',
      );
    states[owner] = 1;
    for (final parent in parents[owner])
      if (typeIsClass(parent)) visit(typeArgument(parent));
    states[owner] = 2;
    order.add(owner);
  }

  for (var owner = 0; owner < classes.length; owner++) visit(owner);
  for (var owner = 0; owner < classes.length; owner++) {
    classSupertypes[owner] = parents[owner];
    classSuperclasses[owner] = supers[owner];
  }
  checkTypeApplications(symbols, uses);
  checkClassModifiers(symbols, classes, order);
  if (enumType >= 0)
    for (var owner = 0; owner < classes.length; owner++) {
      final syntax = classes[owner];
      if (!syntax.isEnum &&
          !syntax.isAbstract &&
          typeIsSubtype(classType(owner), enumType))
        sourceError(
          symbols.program,
          symbols.program.tokens[syntax.token],
          'concrete classes cannot have Enum as a superinterface',
        );
    }
  return order;
}

void checkClassModifiers(
  SymbolTable symbols,
  List<AstClass> classes,
  List<int> order,
) {
  final program = symbols.program;
  // Only library identity matters to the transitive base/final restriction.
  final restricted = <List<int>>[
    for (var i = 0; i < classes.length; i++) <int>[],
  ];
  for (final owner in order) {
    final syntax = classes[owner];
    final token = program.tokens[syntax.token];
    final library = sourceLibrary(program, token.source);
    final modern = sourceVersionAtLeast(program, library, 3, 0);
    final inherited = restricted[owner];
    for (final type in classSupertypes[owner]) {
      if (!typeIsClass(type)) continue;
      final parent = typeArgument(type);
      final declaration = classes[parent];
      final parentLibrary = sourceLibrary(
        program,
        program.tokens[declaration.token].source,
      );
      final foreign = parentLibrary != library;
      final exempt = !modern && sourceIsSystem(program, parentLibrary);
      final extendsParent = classSuperclasses[owner] == type;
      if (foreign &&
          (declaration.modifier == 'sealed' ||
              !exempt &&
                  (declaration.modifier == 'final' ||
                      extendsParent && declaration.modifier == 'interface')))
        sourceError(
          program,
          token,
          'cannot subtype ' +
              declaration.modifier +
              ' class from another library',
        );
      for (final restrictedLibrary in restricted[parent]) {
        if (!extendsParent &&
            restrictedLibrary != library &&
            (modern || !sourceIsSystem(program, restrictedLibrary)))
          sourceError(
            program,
            token,
            'cannot implement a type with a base or final supertype from another library',
          );
        var known = false;
        for (final previous in inherited)
          if (previous == restrictedLibrary) known = true;
        if (!known) inherited.add(restrictedLibrary);
      }
    }
    final protected = syntax.modifier == 'base' || syntax.modifier == 'final';
    if (modern &&
        inherited.isNotEmpty &&
        !protected &&
        syntax.modifier != 'sealed' &&
        !syntax.isEnum)
      sourceError(
        program,
        token,
        'a subtype of a base or final class must be base, final or sealed',
      );
    if (protected) {
      var known = false;
      for (final previous in inherited) if (previous == library) known = true;
      if (!known) inherited.add(library);
    }
  }
}
