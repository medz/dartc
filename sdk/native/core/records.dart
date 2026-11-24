import 'dart:_heap/machine.dart' show addressOf, isSame;
import 'dart:_heap/objects.dart' show lengthOf, loadReference;
import 'dart:_heap/program.dart' show typeOf;
import 'dart:_heap/type_objects.dart';

@patch
@pragma('dartc:elements', 'references')
final class _Record {
  List<String>? _names;

  // Equal lists of names are the same object, which never moves.
  @patch
  int get _shape => (addressOf(_names!) << 16) + lengthOf(this);

  @patch
  int get _numFields => lengthOf(this);

  @patch
  _List get _fieldNames => unsafeCast<_List>(_names);

  @patch
  Object? _fieldAt(int index) => loadReference(this, index);
}

/// The type of [record].
RuntimeType _recordType(_Record record) {
  TypeList? fields;
  for (var i = lengthOf(record) - 1; i >= 0; i--) {
    final value = loadReference(record, i);
    final type = value == null ? const BasicType(nullKind) : typeOf(value);
    fields = TypeList(type, fields);
  }
  return RecordType(fields, record._names!);
}

/// Whether [value] is a record of [count] fields, of which the last have
/// [names].
bool _hasShape(Object? value, int count, List<String> names) =>
    value is _Record &&
    lengthOf(value) == count &&
    isSame(value._names!, names);

/// The place of the field called [name] of [record], or -1 if it has none.
int _recordIndex(_Record record, String name) {
  final names = record._names!, first = lengthOf(record) - names.length;
  for (var i = 0; i < first; i++) {
    if (name == '\$${i + 1}') return i;
  }
  for (var i = 0; i < names.length; i++) {
    if (name == names[i]) return first + i;
  }
  return -1;
}

Object? _recordField(_Record record, int index) =>
    loadReference(record, index);

Never _throwNoMatch() => throw StateError('Pattern matching error');
