void main(List<String> arguments) {
  try {
    arguments.add('unexpected');
    throw StateError('Arguments must have fixed length.');
  } on UnsupportedError {
    if (arguments.isNotEmpty) {
      final first = arguments.first;
      arguments[0] = 'changed';
      if (arguments.first != 'changed') {
        throw StateError('Arguments must be writable.');
      }
      arguments[0] = first;
    }
  }
  print(arguments.length);
  for (var i = 0; i < arguments.length; i++) {
    print('$i:${arguments[i].length}:${arguments[i]}');
  }
}
