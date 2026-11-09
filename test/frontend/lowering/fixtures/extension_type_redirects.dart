extension type const Value<T>._(T? value) {
  const factory(T? value) = Value<T>._;
  factory named({T? value}) = Value<T>.destination;
  new destination({T? value, int unused = 3}) : value = value;
}

extension type Number._(int value) {
  factory([int value]) = Number.destination;
  factory again([int value]) = Number;
  factory named({int value}) = Number.namedDestination;
  factory reordered({int x, int y}) = Number.combine;
  new destination([int value = 7]) : value = value;
  new namedDestination({int value = 8, int unused = 9}) : value = value;
  new combine({int y = 3, int x = 2}) : value = x * 10 + y;
}

extension type General<T>(T value) {
  factory specific(T value) = Specific<T>;
}

extension type Specific<T>(T value) implements General<T>;

String redirects() {
  final make = Number.again;
  final generic = Value.new;
  const constant = Value<int>(4);
  return '${Number().value}:${make().value}:${make(2).value}:${Number.named().value}:${generic<String>('three').value}:${constant.value}:${Value<int>.named().value}:${Number.reordered().value}:${General<String>.specific('mapped').value}';
}
