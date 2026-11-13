import 'numeric_boxes.dart';
import 'managed_failure.dart' show restrictMemory;

void main() {
  restrictMemory(0);
  optional(42, 0);
}
