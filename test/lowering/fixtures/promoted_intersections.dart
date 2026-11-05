import 'dart:async';

Type typeOf<T>(T value) => T;
T identity<T>(T value) => value;

String numeric<T>(T value) {
  if (value is num) {
    final T original = value;
    final values = [value];
    return '${value + 1}|${typeOf(value) == T}|${typeOf(values) == List<T>}|${identity<T>(original) == value}';
  }
  return 'other';
}

String numericCases() =>
    '${numeric<Object>(2)};${numeric<int>(3)};${numeric<Object?>(null)}';

int lists<T>(T value) {
  if (value is List<int>) {
    value.add(7);
    return value[0] + value.length;
  }
  return -1;
}

int listCases() => lists<Object>([3]) + lists<Object>('no');

int records<T>(T value) {
  if (value is (int, {int count})) return value.$1 + value.count;
  return -1;
}

int recordCases() => records<Object>((3, count: 4));

int functions<T>(T value) {
  if (value is int Function(int)) {
    final invoke = value;
    return invoke(4) + value.call(5);
  }
  return -1;
}

int plus(int value) => value + 1;
int functionCases() => functions<Object>(plus);

String nulls<T>(T value) {
  if (value is int?) {
    final inferred = typeOf(value) == T;
    if (value != null) return '$inferred|${value + 1}|${typeOf(value) == T}';
    return '$inferred|null';
  }
  return 'other';
}

String nullableCases() =>
    '${nulls<Object?>(1)};${nulls<Object?>(null)};${nulls<Object>('x')}';

String nonNull<T>(T value) {
  if (value != null) {
    return '${typeOf(value) == T}|${typeOf([value]) == List<T>}';
  }
  return 'null';
}

String objectCases() => '${nonNull<int?>(1)};${nonNull<Object?>(null)}';

int captured<T>(T value) {
  if (value is int) {
    int read() => value + 1;
    return read();
  }
  return -1;
}

int captureCases() => captured<Object>(8);

abstract class Left() {
  int left();
}

abstract class Right() implements Left {
  int right();
}

class Both() implements Left, Right {
  @override
  int left() => 3;
  @override
  int right() => 7;
}

int bounded<T extends Left>(T value) {
  if (value is Right) return value.left() + value.right();
  return value.left();
}

int boundedCases() => bounded<Left>(Both());

String futures<T>(T value) {
  if (value is FutureOr<int>) return '${typeOf(value) == T}|${value is int}';
  return 'other';
}

String futureCases() => '${futures<Object>(1)};${futures<Object>('x')}';

int rewritten<T>(T value, T replacement) {
  void replace() {
    value = replacement;
  }

  if (value is int) {
    final before = value as int;
    replace();
    if (value is int) return before + (value as int);
    return before;
  }
  return -1;
}

int revokedCases() => rewritten<Object>(4, 'changed') + rewritten<Object>(4, 3);

int nested<T>(T value) {
  if (value is List<num>) {
    if (value is List<int>) return value[0] + value.length;
    return value.length;
  }
  return -1;
}

int nestedCases() => nested<Object>([3]) + nested<Object>(<num>[2.5]);

int genericFunctions<T>(T value) {
  if (value is U Function<U>(U)) return value<int>(4);
  return -1;
}

int genericFunctionCases() => genericFunctions<Object>(identity);

int boundedFields<T extends Box<num>>(T value) {
  if (value is Box<int>) {
    value.item = 6;
    final read = value.read;
    return read() + value.item;
  }
  return -1;
}

class Box<T>(T initial) {
  T item = initial;
  T read() => item;
}

int fieldCases() => boundedFields<Box<num>>(Box<int>(2));

int nullableRecords<T>(T value) {
  if (value is (int, int)?) return value!.$1;
  return -1;
}

int nullableRecordCases() => nullableRecords<Object?>((5, 6));

int nullableFunctions<T>(T value) {
  if (value is int Function(int)?) return value!(4);
  return -1;
}

int nullableFunctionCases() => nullableFunctions<Object?>(plus);

T nonNullReturn<T extends Object>(T value) {
  if (value is num) return value;
  return value;
}

bool nonNullReturnCases() => nonNullReturn<int>(3) == 3;

U otherParameter<T, U>(T value) {
  if (value is U) return value;
  throw 7;
}

bool otherParameterCases() => otherParameter<Object, int>(3) == 3;

int boundedRecord<T, U extends (int, int)>(T value) {
  if (value is U) return value.$1 + value.$2;
  return -1;
}

int boundedRecordCases() => boundedRecord<Object, (int, int)>((4, 5));

int boundedFunction<T, U extends int Function(int)>(T value) {
  if (value is U) return value(5);
  return -1;
}

int boundedFunctionCases() => boundedFunction<Object, int Function(int)>(plus);

int originalRecordBound<T extends (int, int), U>(T value) {
  if (value is U) return value.$1 + value.$2;
  return -1;
}

int originalRecordCases() => originalRecordBound<(int, int), Object>((4, 6));

int originalFunctionBound<T extends int Function(int), U>(T value) {
  if (value is U) return value(6) + value.call(7);
  return -1;
}

int originalFunctionCases() =>
    originalFunctionBound<int Function(int), Object>(plus);

int originalGenericFunctionBound<T extends V Function<V>(V), U>(T value) {
  if (value is U) return value<int>(8);
  return -1;
}

int originalGenericFunctionCases() =>
    originalGenericFunctionBound<V Function<V>(V), Object>(identity);

bool genericPromotionSubstitution<T>(T value) {
  // Inferred closure signatures exercise promotion substitution.
  // ignore: prefer_function_declarations_over_variables
  final f = <S>(S x) => x is int ? x : throw 1;
  final result = f<T>(value);
  return typeOf(result) == T;
}

bool genericPromotionSubstitutionCases() =>
    genericPromotionSubstitution<Object>(3);

String capturedPromotionSubstitution<T>(T value) {
  if (value is int) {
    // Inferred closure signatures exercise promotion substitution.
    // ignore: prefer_function_declarations_over_variables
    final f = <S>(S x) => value;
    final result = f<T>(value);
    return '${typeOf(result) == T}:$result';
  }
  return 'other';
}

String capturedPromotionSubstitutionCases() =>
    capturedPromotionSubstitution<Object>(3);
