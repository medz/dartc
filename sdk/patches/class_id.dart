import '../../lib/layout/memory.dart';
import '../runtime/memory.dart';
import '../runtime/type_info.dart';

/// Target storage identities for SDK fast paths, independent of VM class IDs.
abstract final class ClassID() {
  static int getID(Object? value) {
    final type = value == null
        ? TypeInfo.of(Null)
        : Memory.readReference(value, ObjectHeader.typeOffset) as TypeInfo;
    return (type.shape << 8) | type.kind;
  }

  static final int cidArray = getID(List<Object?>.empty());
  static final int cidGrowableObjectArray = getID(
    List<Object?>.empty(growable: true),
  );
  static final int cidImmutableArray = getID(const []);
  static final int cidOneByteString = getID(String.fromCharCode(65));
  static final int cidTwoByteString = getID(String.fromCharCode(0x100));

  // The VM's predefined-class interval has no target equivalent.
  external static int get numPredefinedCids;
}
