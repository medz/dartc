import 'dart:_heap/program.dart' show typeOf;
import 'dart:_heap/type_objects.dart' show RuntimeType;
import 'dart:_heap/types.dart' show hashOfType, isSameType, typeName;

Type _newType(RuntimeType own) => _Type._of(own);

@patch
class _AbstractType {
  const _AbstractType();

  @patch
  String toString();
  @patch
  int get hashCode;
  @patch
  bool operator ==(other) => identical(this, other);
}

@patch
class _Type {
  final RuntimeType _own;
  const _Type._of(this._own);

  String toString() => typeName(_own);
  int get hashCode => hashOfType(_own);
  int get _identityHashCode => hashCode;
  @patch
  bool operator ==(other) => other is _Type && isSameType(_own, other._own);
}

@patch
class Object {
  @patch
  Type get runtimeType => _Type._of(typeOf(this));

  @patch
  static bool _haveSameRuntimeType(a, b) => a.runtimeType == b.runtimeType;
}

// What the classes are called that implement others here.

@patch
class _IntegerImplementation {
  Type get runtimeType => int;
}

@patch
class _Double {
  Type get runtimeType => double;
}

@patch
class _StringBase {
  Type get runtimeType => String;
}

@patch
class _Array<E> {
  Type get runtimeType => List<E>;
}

@patch
class _GrowableList<T> {
  Type get runtimeType => List<T>;
}

@patch
class Null {
  Type get runtimeType => Null;
}
