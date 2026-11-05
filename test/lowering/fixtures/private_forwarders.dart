// ignore_for_file: curly_braces_in_flow_control_structures, annotate_overrides, unused_element, unused_element_parameter, unnecessary_type_check, use_primary_constructors
import 'private_forwarders_a.dart' as a;
import 'private_forwarders_b.dart' as b;
import 'effects.dart' as effects;

class Default implements a.Contract<num> {}

class Custom implements a.Contract<num> {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return '${a.origin(invocation.memberName)}:${b.origin(invocation.memberName)}:${invocation.positionalArguments.length}:${invocation.typeArguments.length}';
  }
}

class Both implements a.Contract<num>, b.Contract {
  int _f() => 123;
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(91);
    return '${a.origin(invocation.memberName)}:${b.origin(invocation.memberName)}';
  }
}

class Changed extends a.RealChanged {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(92);
    return 99;
  }
}

class SynthChanged extends a.SyntheticChanged {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(93);
    return 99;
  }
}

class CovChanged extends a.RealCovChanged {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(94);
    return 99;
  }
}

class NamedChanged extends a.NamedChanged {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(95);
    return 99;
  }
}

class ForeignChild extends a.LocalChild {}

class ForeignOverride extends a.LocalChild {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(72);
    return invocation.positionalArguments[0] + 1;
  }
}

Object? privateForms(int kind, int form, dynamic value) {
  if (kind == 0) return a.invoke(Default(), form, value);
  if (kind == 1) return a.invoke(Custom(), form, value);
  return a.invoke(Both(), form, value);
}

Object? privateSecond(int form) => b.invoke(Both(), form);
int privateOwn() => Both()._f();
Object? privateReplacement(int kind, int form, dynamic value) {
  if (kind == 0) return a.invoke(Changed(), form, value);
  return a.invoke(SynthChanged(), form, value);
}

Object? privateCovariance(int form, dynamic value) =>
    a.invokeCov(CovChanged(), form, value);
Object? privateNamed(int form, dynamic value) =>
    a.invokeNamed(NamedChanged(), form, value);
Object? privateUnchanged(int kind, int form) {
  final a.LocalChild receiver = kind == 0 ? ForeignChild() : ForeignOverride();
  if (form == 0) return a.invokeUnchanged(receiver, false);
  if (form == 1) return a.invokeUnchanged(receiver, true);
  if (form == 2) return receiver.parentCall();
  return receiver.parentTear();
}

class UserInvocation implements Invocation {
  Symbol get memberName {
    effects.tick(101);
    return #missing;
  }

  List<Type> get typeArguments {
    effects.tick(102);
    return <Type>[];
  }

  List<dynamic> get positionalArguments {
    effects.tick(103);
    return <dynamic>[];
  }

  Map<Symbol, dynamic> get namedArguments {
    effects.tick(104);
    return <Symbol, dynamic>{};
  }

  bool get isMethod {
    effects.tick(105);
    return true;
  }

  bool get isGetter {
    effects.tick(106);
    return false;
  }

  bool get isSetter {
    effects.tick(107);
    return false;
  }

  bool get isAccessor {
    effects.tick(108);
    return false;
  }
}

Object privateErrorFactory(int form) {
  final invocation = UserInvocation();
  if (form == 5) {
    final factory = NoSuchMethodError.withInvocation;
    final Object result = factory(null, invocation);
    return result is NoSuchMethodError;
  }
  final Object error = NoSuchMethodError.withInvocation(Custom(), invocation);
  if (form == 0) return error is NoSuchMethodError;
  if (form == 1) return error is Error;
  if (form == 2)
    return identical(
      error,
      NoSuchMethodError.withInvocation(Custom(), invocation),
    );
  if (form == 3) {
    try {
      throw error;
    } on NoSuchMethodError catch (caught) {
      return identical(error, caught);
    }
  }
  try {
    try {
      throw error;
    } on Error {
      rethrow;
    }
  } catch (caught) {
    return identical(error, caught);
  }
}

abstract class PublicContract {
  int publicMethod([int value = 19]);
}

class PublicForward implements PublicContract {
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.positionalArguments[0];
}

int privatePublicBody() => PublicForward().publicMethod();

class CompatibleChild extends a.CompatibleReal
    implements a.CompatibleContract {}

Object privateCompatible(int form) =>
    a.privateCompatibleCall(CompatibleChild(), form);
