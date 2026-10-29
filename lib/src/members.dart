import 'ast.dart';
import 'source.dart';

const int interfaceMethod = 0;
const int interfaceGetter = 1;

const int memberReadIdentity = 0;
const int memberReadNumberProperty = 10;
const int memberReadMethod = 1;
const int memberReadGetter = 2;
const int memberReadField = 3;
const int memberReadLength = 4;
const int memberReadIsEmpty = 5;
const int memberReadIsNotEmpty = 6;
const int memberReadFirst = 7;
const int memberReadLast = 8;

class CheckedMemberRead(
  final int receiver,
  final int type,
  final int kind,
  final int target,
);

class const InterfaceMember(
  final String name,
  final int role, [
  final String implementation = '',
]);

class MemberBinding {
  String name;
  final int library;
  bool isStatic = false;
  // A runtime implementation declares its receiver as its first formal.
  bool receiverParameter = false;
  // bindClassMembers records syntax ordinals. Declaration collection resolves
  // these to field, global and function IDs before checking member uses.
  int field = -1;
  int fieldSetter = -1;
  int staticField = -1;
  int method = -1;
  int getter = -1;
  int setter = -1;
  List<bool> covariantParameters = const <bool>[];

  MemberBinding(this.name, this.library);
}

class ClassMembers {
  List<MemberBinding> members;
  List<String> constructors = const <String>[];

  ClassMembers(this.members);
}

int lookupMember(ClassMembers owner, String name, [int library = -1]) {
  var i = 0;
  while (i < owner.members.length) {
    final member = owner.members[i];
    if (member.name == name &&
        (!name.startsWith('_') || library < 0 || member.library == library))
      return i;
    i++;
  }
  return -1;
}

String constructorSelector(SourceProgram source, String name, int token) {
  if (name != 'new') return name;
  if (!sourceVersionAtLeast(source, source.tokens[token].source, 2, 15))
    _memberError(
      source,
      token,
      'constructor name new requires language version 2.15',
    );
  return '';
}

int lookupConstructor(ClassMembers owner, String name) {
  var i = 0;
  while (i < owner.constructors.length) {
    if (owner.constructors[i] == name) return i;
    i++;
  }
  return -1;
}

int resolveConstructorReference(
  SourceProgram source,
  AstClass syntax,
  ClassMembers owner,
  String rawName,
  int token, [
  bool tearOff = false,
]) {
  final name = constructorSelector(source, rawName, token);
  final ordinal = lookupConstructor(owner, name);
  if (ordinal < 0) return -1;
  if (name.startsWith('_') &&
      sourceLibrary(source, source.tokens[token].source) !=
          sourceLibrary(source, source.tokens[syntax.token].source))
    _memberError(source, token, 'private constructor ' + name);
  if (tearOff &&
      !sourceVersionAtLeast(source, source.tokens[token].source, 2, 15))
    _memberError(
      source,
      token,
      'constructor tear-off requires language version 2.15',
    );
  if (syntax.isAbstract &&
      (syntax.constructors.isEmpty || !syntax.constructors[ordinal].factory))
    _memberError(source, token, 'cannot instantiate an abstract class');
  return ordinal;
}

MemberBinding _memberBinding(
  SourceProgram source,
  AstClass syntax,
  ClassMembers owner,
  String name,
  int token,
  bool isStatic,
) {
  if (name == syntax.name)
    _memberError(source, token, 'member cannot have the class name');
  if (isStatic && lookupConstructor(owner, name) >= 0)
    _memberError(source, token, 'static member conflicts with constructor');
  var index = lookupMember(owner, name);
  if (index < 0) {
    index = owner.members.length;
    var member = MemberBinding(
      name,
      sourceLibrary(source, source.tokens[token].source),
    );
    member.isStatic = isStatic;
    owner.members.add(member);
  } else if (owner.members[index].isStatic != isStatic) {
    _memberError(source, token, 'static member conflicts with instance member');
  }
  return owner.members[index];
}

Never _memberError(SourceProgram source, int token, String message) {
  sourceError(source, source.tokens[token], message);
}

void _checkStaticInterface(
  SourceProgram source,
  List<InterfaceMember> inherited,
  String name,
  int token,
) {
  var i = 0;
  while (i < inherited.length) {
    if (inherited[i].name == name)
      _memberError(
        source,
        token,
        'static member conflicts with instance interface',
      );
    i++;
  }
}

ClassMembers bindClassMembers(
  SourceProgram source,
  AstClass syntax,
  List<InterfaceMember> inheritedInstanceMembers,
) {
  var result = ClassMembers(<MemberBinding>[]);
  if (syntax.constructors.isEmpty)
    result.constructors = const <String>[''];
  else
    result.constructors = <String>[];
  var i = 0;
  while (i < syntax.constructors.length) {
    var constructor = syntax.constructors[i];
    var dot = constructor.name.indexOf('.');
    var name = '';
    if (dot >= 0)
      name = constructorSelector(
        source,
        constructor.name.substring(dot + 1),
        constructor.token + 2,
      );
    if (lookupConstructor(result, name) >= 0)
      _memberError(source, constructor.token, 'duplicate constructor');
    result.constructors.add(name);
    i++;
  }
  i = 0;
  while (i < syntax.methods.length) {
    var method = syntax.methods[i];
    if (method.isStatic)
      _checkStaticInterface(
        source,
        inheritedInstanceMembers,
        method.name,
        method.token,
      );
    var member = _memberBinding(
      source,
      syntax,
      result,
      method.name,
      method.token,
      method.isStatic,
    );
    var duplicate = member.method >= 0;
    if (method.getter) {
      duplicate = duplicate || member.getter >= 0;
      member.getter = i;
    } else if (method.setter) {
      duplicate = duplicate || member.setter >= 0;
      member.setter = i;
    } else {
      duplicate = duplicate || member.getter >= 0 || member.setter >= 0;
      member.method = i;
    }
    if (duplicate) {
      _memberError(source, method.token, 'duplicate member ' + method.name);
    }
    for (var p = 0; p < method.parameters.length; p++) {
      if (!method.parameters[p].covariant) continue;
      if (member.covariantParameters.isEmpty)
        member.covariantParameters = List<bool>.filled(
          method.parameters.length,
          false,
        );
      member.covariantParameters[p] = true;
    }
    i++;
  }
  i = 0;
  while (i < syntax.fields.length) {
    var field = syntax.fields[i];
    var member = _memberBinding(
      source,
      syntax,
      result,
      field.name,
      field.token,
      false,
    );
    if (member.field >= 0 ||
        member.method >= 0 ||
        member.getter >= 0 ||
        member.setter >= 0 && field.hasSetter) {
      _memberError(source, field.token, 'duplicate member ' + field.name);
    }
    member.field = i;
    if (field.hasSetter) member.fieldSetter = i;
    i++;
  }
  i = 0;
  while (i < syntax.staticFields.length) {
    var field = syntax.staticFields[i];
    _checkStaticInterface(
      source,
      inheritedInstanceMembers,
      field.name,
      field.token,
    );
    var member = _memberBinding(
      source,
      syntax,
      result,
      field.name,
      field.token,
      true,
    );
    if (member.staticField >= 0 ||
        member.method >= 0 ||
        member.getter >= 0 ||
        member.setter >= 0 && field.hasSetter) {
      _memberError(
        source,
        field.token,
        'duplicate static member ' + field.name,
      );
    }
    member.staticField = i;
    i++;
  }
  return result;
}
