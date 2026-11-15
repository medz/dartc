import 'numeric_boxes.dart';
import 'managed_recovery.dart' show restrictMemory;

void main() {
  restrictMemory(0);
  optional(42, 0);
}
