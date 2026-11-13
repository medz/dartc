import 'system_libraries.dart' as system;

void main() {
  if (system.processId() <= 0) throw StateError('process identity');
}
