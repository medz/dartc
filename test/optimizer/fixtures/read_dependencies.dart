final class Snapshot(var int value, var int unrelated);

int readValue(Snapshot snapshot) => snapshot.value;

int unrelatedField(int input) {
  final snapshot = Snapshot(7, 0);
  final first = readValue(snapshot);
  snapshot.unrelated = input;
  return first + readValue(snapshot);
}

int changedField(int input) {
  final snapshot = Snapshot(7, 0);
  final first = readValue(snapshot);
  snapshot.value = input;
  return first + readValue(snapshot);
}

late int observed;
late int unrelated;

int readGlobal() => observed;
int forwardGlobal() => readGlobal();

int unrelatedGlobal(int input) {
  observed = 7;
  final first = forwardGlobal();
  unrelated = input;
  return first + forwardGlobal();
}

int changedGlobal(int input) {
  observed = 7;
  final first = forwardGlobal();
  observed = input;
  return first + forwardGlobal();
}

int captured(int input) {
  var value = 7;
  int read() => value;
  final first = read();
  unrelated = input;
  return first + read();
}

abstract interface class View() {
  int get value;
}

final class PlainView(@override final int value) implements View;

final class CountingView(final int result) implements View {
  @override
  int get value {
    observed++;
    return result;
  }
}

int readView(View view) => view.value;

int virtualRead(bool writes, int input) {
  observed = 0;
  final View view = writes ? CountingView(input) : PlainView(input);
  return readView(view) + readView(view) + observed;
}

int initialize(int value) {
  observed++;
  return value;
}

final class LazyView(final int initial) implements View {
  @override
  late int value = initialize(initial);
}

int lazyRead(int input) {
  observed = 0;
  final view = LazyView(input);
  return readView(view) + readView(view) + observed;
}
