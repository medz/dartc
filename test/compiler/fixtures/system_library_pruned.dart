import 'system_libraries.dart' as system;

abstract class Reader() {
  int read();
}

final class PlainReader() implements Reader {
  @override
  int read() => 7;
}

final class ForeignReader() implements Reader {
  @override
  int read() {
    system.loaderError();
    return system.sine(0.5).toInt();
  }
}

int read(Reader reader) => reader.read();
bool isForeign(Reader reader) => reader is ForeignReader;

void main() {
  if (read(PlainReader()) != 7 ||
      !isForeign(ForeignReader()) ||
      system.processId() <= 0) {
    throw StateError('selected native dependencies');
  }
}
