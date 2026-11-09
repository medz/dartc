// ignore_for_file: curly_braces_in_flow_control_structures, annotate_overrides, unused_element, unused_element_parameter, unnecessary_type_check, use_primary_constructors
import 'effects.dart' as effects;

abstract class Contract<A extends num> {
  int _f([int value = 7]);
  T _gen<T extends A>(T value, {int z = 9, String a = 'a'});
  int get _g;
  set _s(covariant int value);
  int _cov(covariant int value);
  void _void([int value = 8]);
  Never _never();
}

Object? invoke(dynamic receiver, int form, dynamic value) {
  if (form == 0) return receiver._f();
  if (form == 1) return receiver._f(value);
  if (form == 2) return receiver._f(1, 2);
  if (form == 3) return receiver._f();
  if (form == 4) return receiver._f(1, 2, 3);
  if (form == 5) return receiver._gen<int>(2);
  if (form == 6) return receiver._gen(2);
  if (form == 7) return receiver._gen<String>('bad');
  if (form == 8) return receiver._gen<String>(1);
  if (form == 9) return receiver._gen<String>(1, 2);
  if (form == 10) return receiver._g;
  if (form == 11) return receiver._s = value;
  if (form == 12) return receiver._cov(value);
  if (form == 13) return receiver._void();
  if (form == 14) return receiver._never();
  if (form == 15) {
    final dynamic tear = receiver._f;
    return tear();
  }
  if (form == 16) {
    final dynamic tear = receiver._f;
    return tear(1, 2);
  }
  if (form == 17) {
    final dynamic tear = receiver._gen;
    return tear<String>(1, 2);
  }
  if (form == 18) return receiver._f is int Function([int]);
  if (form == 19) return receiver._cov is int Function(Object?);
  if (form == 20) return receiver._f is int Function([num]);
  if (form == 21) return receiver._gen<int>(value, unknown: 1);
  return receiver._gen<int>(value, z: 4, a: 'supplied');
}

class SymbolCapture {
  dynamic noSuchMethod(Invocation invocation) => invocation.memberName;
}

bool origin(Symbol name) {
  final dynamic capture = SymbolCapture();
  return name == capture._f() || name == capture._gen();
}

class Real {
  int _f([int value = 10]) => value;
}

abstract class RealChanged extends Real {
  int _f([num value = 20]);
}

class Synthetic {
  dynamic noSuchMethod(Invocation invocation) => 11;
  int _f([int value = 10]);
}

abstract class SyntheticChanged extends Synthetic {
  int _f([num value = 30]);
}

class RealCov {
  int _q(covariant int value) => value;
}

abstract class RealCovChanged extends RealCov {
  int _q(num value);
}

Object? invokeCov(dynamic receiver, int form, dynamic value) {
  if (form == 0) return receiver._q is int Function(Object?);
  if (form == 1) return receiver._q(value);
  final dynamic tear = receiver._q;
  return tear(value);
}

abstract class NamedA {
  int _named({required covariant num z, int a = 2});
}

abstract class NamedB {
  int _named({int a = 2, required num z});
}

class NamedReal {
  int _named({int a = 1, required covariant int z}) => z;
}

abstract class NamedChanged extends NamedReal implements NamedA, NamedB {
  int _named({int a = 2, required num z});
}

Object? invokeNamed(dynamic receiver, int form, dynamic value) {
  if (form == 0)
    return receiver._named is int Function({int a, required Object? z});
  if (form == 1) return receiver._named(z: value);
  final dynamic tear = receiver._named;
  if (form == 2) return tear(z: value);
  return tear(a: value, z: 3);
}

// Deliberately child-before-parent, including direct super call and tear-off.
class LocalChild extends LocalBase {
  int parentCall() => super._unchanged();
  int parentTear() {
    final f = super._unchanged;
    return f();
  }
}

class LocalBase implements LocalContract {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(71);
    return invocation.positionalArguments[0];
  }
}

abstract class LocalContract {
  int _unchanged([int value = 41]);
}

Object? invokeUnchanged(LocalBase receiver, bool tearoff) {
  if (tearoff) {
    final f = receiver._unchanged;
    return f();
  }
  return receiver._unchanged();
}

class CompatibleReal {
  int _wide(num value) => 2;
  int _return(int value) => 3;
  int _same(int value) => 4;
}

abstract class CompatibleContract {
  int _wide(int value);
  num _return(int value);
  int _same(int value);
}

Object privateCompatibleCall(dynamic receiver, int form) {
  if (form == 0) return receiver._wide(1);
  if (form == 1) return receiver._return(1);
  return receiver._same(1);
}
