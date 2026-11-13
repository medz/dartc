import '../../frontend/lowering/fixtures/generators.dart' as cases;
import 'futures.dart' show Payload, churn;

Iterable<WeakReference<Payload>> released() sync* {
  final value = Payload(42, 'suspended');
  yield WeakReference(value);
  if (value.id != 42) throw StateError('Lost frame root');
  yield WeakReference(Payload(1, 'temporary'));
}

void main() {
  print(cases.reentrantIterator());
  late Iterator<int> iterator;
  var cleaned = false;
  Iterable<int> values() sync* {
    try {
      iterator.moveNext();
      yield 1;
    } finally {
      cleaned = true;
    }
  }

  iterator = values().iterator;
  try {
    iterator.moveNext();
  } on StateError {
    print('rejected:$cleaned:${iterator.moveNext()}');
  }
  final frames = released().iterator;
  frames.moveNext();
  final weak = frames.current;
  churn();
  if (weak.target == null) throw StateError('Collected a live frame slot');
  frames.moveNext();
  churn();
  if (weak.target != null) throw StateError('Retained a dead frame slot');
  print('released:${frames.moveNext()}');
}
