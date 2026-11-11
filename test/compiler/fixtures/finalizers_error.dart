import 'finalizers.dart';

void main() {
  owner = Finalizer<double?>((_) => throw StateError('finalizer failure'));
  attach();
  collect(0);
}

void attach() => owner!.attach(Cell(1), null);
