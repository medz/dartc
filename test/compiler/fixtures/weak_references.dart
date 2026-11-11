import 'dart:ffi';

import 'package:dartc/interop.dart';

final class Cell(final double value) {
  Cell? next;
}

WeakReference<Cell>? saved;
WeakReference<Cell>? other;
Cell? strong;

@Export<Void Function(Double, Int8)>()
void create(double value, int retain) {
  final cell = Cell(value);
  cell.next = cell;
  saved = WeakReference(cell);
  final child = Cell(value + 1)..next = cell;
  other = WeakReference(child);
  strong = retain == 0 ? null : cell;
}

@Export<Double Function()>()
double read() => saved?.target?.value ?? -1;

@Export<Double Function()>()
double readOther() => other?.target?.value ?? -1;

@Export<Double Function(Int64)>()
double retainRead(int count) {
  final cell = saved?.target;
  strong = null;
  churn(count);
  return cell?.value ?? -1;
}

@Export<Void Function()>()
void release() => strong = null;

@Export<Double Function(Int64)>()
double churn(int count) {
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    sum += Cell(i.toDouble()).value;
  }
  return sum;
}

WeakReference<T> wrap<T extends Object>(T value) {
  final constructor = WeakReference<T>.new;
  return constructor(value);
}

bool targetType<T extends Object>(Object value) => value is WeakReference<T>;

@Export<Double Function(Double, Int64)>()
double local(double value, int count) {
  final cell = Cell(value);
  final weak = wrap(cell);
  churn(count);
  if (!targetType<Cell>(weak) ||
      targetType<String>(weak) ||
      !identical(weak.target, cell)) {
    throw StateError('Weak reference lost its target or type');
  }
  return weak.target!.value;
}

final class const Token(final int value);
const token = Token(42);
WeakReference<Token>? permanent;

@Export<Int64 Function(Int64)>()
int constantTarget(int count) {
  permanent ??= wrap(token);
  churn(count);
  return permanent!.target!.value;
}

@Export<Int8 Function(Int64)>()
int objectKinds(int count) {
  final list = [Cell(2)];
  final map = {'x': Cell(3)};
  double call() => list[0].value + map['x']!.value;
  final weakList = wrap(list), weakMap = wrap(map);
  final weakFunction = wrap(call), weakType = wrap(Cell);
  churn(count);
  return identical(weakList.target, list) &&
          identical(weakMap.target, map) &&
          identical(weakFunction.target, call) &&
          weakFunction.target!() == 5 &&
          weakType.target == Cell
      ? 1
      : 0;
}

@Export<Int8 Function(Int64)>()
int rejects(int kind) {
  final Object value = switch (kind) {
    0 => 42,
    1 => 1.25,
    2 => true,
    3 => 'target',
    _ => Pointer<Void>.fromAddress(0x1234),
  };
  try {
    WeakReference(value);
    return 0;
  } on ArgumentError catch (error) {
    return identical(error.invalidValue, value) && error.name == 'target'
        ? 1
        : -1;
  }
}
