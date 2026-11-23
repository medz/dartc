import 'dart:_heap/machine.dart' show addressOf, classNumber, isSame;
import 'dart:_heap/numbers.dart' show sameObjects;
import 'dart:_heap/program.dart' show functionName, receiverOf;
import 'dart:_heap/types.dart' show objectTypeName;

@patch
bool identical(Object? a, Object? b) => sameObjects(a, b);

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
    final receiver = receiverOf(this);
    return receiver != null &&
        other is _Closure &&
        classNumber(this) == classNumber(other) &&
        isSame(receiver, receiverOf(other));
  }

  @patch
  int get hashCode {
    final receiver = receiverOf(this);
    return receiver == null
        ? addressOf(this) >> 4
        : (addressOf(receiver) >> 4) + classNumber(this);
  }
}
