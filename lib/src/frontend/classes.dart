import '../ast.dart';
import '../constants.dart';
import '../ir.dart';
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
    );
  }
  if (role == classGetter)
    return ClassSignature(
      fieldTypes[member.field],
      const <int>[],
      const <AstParameter>[],
      const <int>[],
    );
  return ClassSignature(
    tVoid,
    <int>[fieldTypes[member.fieldSetter]],
    <AstParameter>[
      AstParameter(AstType('', const <AstType>[], 0), '', false, 0),
    ],
    const <int>[],
  );
}

bool classSignatureSubtype(ClassSignature actual, ClassSignature expected) {
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
    if (!typeIsSubtype(type, actual.parameters[index])) return false;
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
  return copy;
}

void _copyRole(MemberBinding target, MemberBinding source, int role) {
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

  for (final owner in order) {
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
      final parameter = field < 0 ? null : fields[field].declaringParameter;
      if (parameter != null && parameter.type.name == '') {
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
          if (fields[field].modifier == 'final') break;
        }
        if (type < 0) {
          final expression = parameter.defaultValue;
          final scope = constants.lexicalClass;
          constants.lexicalClass = owner;
          type = expression == null
              ? tNull
              : inferConstantType(constants, expression);
          constants.lexicalClass = scope;
          if (type == tNull) type = nullableType(tObject);
        }
        fieldTypes[field] = type;
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
          if (function >= 0 && selected != null) {
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
          final signature = classSignature(own, role, declarations, fieldTypes);
          for (final parent in candidates)
            if (!classSignatureSubtype(
              signature,
              classSignature(parent, role, declarations, fieldTypes),
            ))
              fail(owner, 'invalid override of ' + member.name);
        } else {
          if (selected == null)
            fail(
              owner,
              'incompatible inherited member signatures: ' + member.name,
            );
          _copyRole(member, selected, role);
        }
      }
      if (member.method >= 0 &&
          (hasClassMember(member, classGetter) ||
              hasClassMember(member, classSetter)))
        fail(owner, 'method conflicts with inherited accessor: ' + member.name);
      for (var role = classMethod; role <= classSetter; role++) {
        if (!hasClassMember(member, role)) continue;
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
            );
        if (!classes[owner].isAbstract && !concrete)
          fail(owner, 'missing concrete implementation of ' + member.name);
      }
    }
  }
  return views;
}

List<int> resolveClassInterfaces(SymbolTable symbols, List<AstClass> classes) {
  final parents = <List<int>>[];
  final supers = <int>[];
  final uses = <AliasApplication>[];
  for (final syntax in classes) {
    final types = <int>[];
    var superclass = tObject;
    if (syntax.superclass case final parent?) {
      superclass = resolveSuperinterface(symbols, parent, uses);
      if (superclass != tObject && !typeIsClass(superclass))
        sourceError(
          symbols.program,
          symbols.program.tokens[parent.token],
          'this superclass type is not yet supported',
        );
    }
    supers.add(superclass);
    for (final interface in syntax.interfaces) {
      final type = resolveSuperinterface(symbols, interface, uses);
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
  checkAliasApplications(symbols, uses);
  return order;
}
