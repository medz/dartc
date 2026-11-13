import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart' as runtime;
import '../runtime/memory.dart';
import '../runtime/object_memory.dart';
import '../runtime/type_info.dart';

@patch
@runtime.ReferencePayload()
@runtime.RecordStorage()
class _Record {
  TypeInfo get _type => TypeInfo.of(runtimeType);

  @patch
  int get _shape => _type.shape;

  @patch
  int get _numFields =>
      (ObjectMemory.size(this) - ObjectHeader.fieldsOffset) ~/
      ObjectHeader.alignment;

  @patch
  _List get _fieldNames {
    final signature = _type.signature!;
    final names = _List<String>(_numFields - signature.positional);
    var index = 0;
    for (var node = signature.named; node != null; node = node.next) {
      names[index++] = node.text;
    }
    return names;
  }

  @patch
  Object? _fieldAt(int index) => Memory.readReference(
    this,
    ObjectHeader.fieldsOffset + index * ObjectHeader.alignment,
  );
}
