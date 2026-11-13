import 'dart:ffi';

void main(List<String> arguments) {
  final library = DynamicLibrary.open(arguments.single);
  try {
    final read = library
        .lookupFunction<Int64 Function(Int64), int Function(int)>(
          'environmentLength',
        );
    print('${read(0)}:${read(40000)}');
  } finally {
    library.close();
  }
}
