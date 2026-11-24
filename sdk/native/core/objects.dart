import 'dart:_heap/machine.dart' show addressOf, classNumber, isSame;
import 'dart:_heap/numbers.dart' show sameObjects;
import 'dart:_heap/program.dart' show functionName, receiverOf, typesOf;
import 'dart:_heap/types.dart'
    show areSameTypes, hashOfTypes, objectClassName, objectTypeName;

@patch
bool identical(Object? a, Object? b) =>
    sameObjects(a, b) || a is _Type && a == b;

@patch
int _getHash(obj) => addressOf(obj) >> 4;

@patch
class Object {
  @patch
  bool operator ==(Object other) => isSame(this, other);

  @patch
  String toString() => _toString(this);

  @patch
  static String _toString(obj) {
    if (obj is _GrowableList) {
      return "Instance(length:${obj.length}) of '_GrowableList'";
    }
    if (obj is _List) return '_List len:${obj.length}';
    if (obj is _ImmutableList) return '_ImmutableList len:${obj.length}';
    if (obj is LinkedHashMap) return '_Map len:${obj.length}';
    if (obj is Type) return obj.toString();
    if (obj is Function) {
      return 'Closure: ${objectTypeName(obj)}${functionName(obj)}';
    }
    return "Instance of '${objectTypeName(obj)}'";
  }
}

@patch
class _Closure {
  @patch
  bool operator ==(Object other) {
    if (isSame(this, other)) return true;
    final receiver = receiverOf(this), types = typesOf(this);
    if (receiver == null && types == null ||
        other is! _Closure ||
        classNumber(this) != classNumber(other)) {
      return false;
    }
    final otherReceiver = receiverOf(other);
    // The function that is given types can be a tear-off itself.
    return (types == null
            ? sameObjects(receiver, otherReceiver)
            : receiver == otherReceiver) &&
        areSameTypes(types, typesOf(other));
  }

  @patch
  int get hashCode {
    final receiver = receiverOf(this);
    final types = typesOf(this);
    if (types == null) {
      return receiver == null
          ? addressOf(this) >> 4
          : identityHashCode(receiver) + classNumber(this);
    }
    return receiver.hashCode + classNumber(this) + hashOfTypes(types);
  }
}

@patch
abstract class _Enum {
  @patch
  String _enumToString() => '${objectClassName(this)}.$_name';
}
