import '../../lib/layout/memory.dart';
import 'memory.dart';

/// Reads one to eight entropy bytes, or returns null when the OS source fails.
int? randomBytes(int count) {
  RangeError.checkValueInInterval(count, 1, 8, 'count');
  final storage = ByteStorage.allocate(8);
  final address = Memory.addressOf(storage) + ObjectHeader.fieldsOffset;
  int status;
  do {
    status = Memory.entropy(address, count);
  } while (status == -4); // EINTR before Linux's entropy pool is initialized.
  final value = status == 0 ? Memory.read(address) : null;
  Memory.keepAlive(storage);
  return value;
}
