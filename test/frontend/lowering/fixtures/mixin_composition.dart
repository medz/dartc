// Closures intentionally capture an application's lexical super binding.
// ignore_for_file: prefer_function_declarations_over_variables
import 'dart:async';

class CompositionBase() {
  int get value => 1;
  @override
  String toString() => 'base';
}

mixin Composition on CompositionBase {
  late final read = () => super.value;
  Iterable<int> values() sync* {
    final get = () => super.value;
    yield get();
    yield read();
    yield value;
  }

  String baseText() => super.toString();
  Type baseType() => super.runtimeType;
  FutureOr<int> maybe(bool add) => super.value + (add ? 1 : 0);
}

class CompositionFirst() extends CompositionBase with Composition {
  @override
  int get value => 3;
  @override
  String toString() => 'first';
  Iterable<int> first() => super.values();
  String firstText() => super.baseText();
}

class CompositionLast() extends CompositionFirst with Composition {}

extension type Composed(CompositionLast value) {
  Iterable<int> values() => value.values();
}

int total(Iterable<int> values) {
  var result = 0;
  for (final value in values) {
    result = result * 10 + value;
  }
  return result;
}

String composedGenerators() {
  final value = CompositionLast();
  final method = value.values;
  final values = method();
  final representation = Composed(value);
  return '${total(value.first())}:${total(values)}:${total(values)}:${total(representation.values())}';
}

String composedObjectMembers() {
  final value = CompositionLast();
  return '${value.firstText()}:${value.baseText()}:${value.baseType() == CompositionLast}';
}

int composedUnionTypes() => CompositionLast().maybe(true) as int;
