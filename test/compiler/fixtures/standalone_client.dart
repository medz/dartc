import 'dart:ffi';

void main(List<String> arguments) {
  final library = DynamicLibrary.open(arguments.single);
  try {
    final add = library
        .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
          'native_add',
        );
    final literal = library.lookupFunction<Int64 Function(), int Function()>(
      'literal',
    );
    if (add(23, 19) != 42 ||
        add(-17, 5) != -12 ||
        literal() != 0x123456789abcdef0) {
      throw StateError('Unexpected native result.');
    }
  } finally {
    library.close();
  }
}
