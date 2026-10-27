import 'ast.dart';
import 'source.dart';

class MemberBinding {
  String name;
  int field = -1;
  int method = -1;
  int getter = -1;
  int setter = -1;

  MemberBinding(this.name);
}

class ClassMembers {
  List<MemberBinding> members;
  List<String> constructors = const <String>[];

  ClassMembers(this.members);
}

int lookupMember(ClassMembers owner, String name) {
  var i = 0;
  while (i < owner.members.length) {
    if (owner.members[i].name == name) return i;
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

MemberBinding _memberBinding(ClassMembers owner, String name) {
  var index = lookupMember(owner, name);
  if (index < 0) {
    index = owner.members.length;
    owner.members.add(MemberBinding(name));
  }
  return owner.members[index];
}

Never _memberError(SourceProgram source, int token, String message) {
  sourceError(source, source.tokens[token], message);
}

ClassMembers bindClassMembers(SourceProgram source, AstClass syntax) {
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
    if (method.name == syntax.name) {
      _memberError(source, method.token, 'member cannot have the class name');
    }
    var member = _memberBinding(result, method.name);
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
    i++;
  }
  i = 0;
  while (i < syntax.fields.length) {
    var field = syntax.fields[i];
    if (field.name == syntax.name) {
      _memberError(source, field.token, 'member cannot have the class name');
    }
    var member = _memberBinding(result, field.name);
    if (member.field >= 0 ||
        member.method >= 0 ||
        member.getter >= 0 ||
        member.setter >= 0 && field.modifier != 'final') {
      _memberError(source, field.token, 'duplicate member ' + field.name);
    }
    member.field = i;
    i++;
  }
  return result;
}
