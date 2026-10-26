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
  var i = 0;
  while (i < syntax.constructors.length) {
    var constructor = syntax.constructors[i];
    var previous = 0;
    while (previous < i) {
      if (syntax.constructors[previous].name == constructor.name) {
        _memberError(source, constructor.token, 'duplicate constructor');
      }
      previous++;
    }
    i++;
  }
  var result = ClassMembers(<MemberBinding>[]);
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
