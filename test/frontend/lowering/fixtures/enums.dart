// Deliberately test raw runtime types and both inferred and explicit constructors.
// ignore_for_file: unnecessary_this, unnecessary_type_check, unnecessary_type_name_in_constructor, use_primary_constructors

import 'effects.dart';

enum Plain { first, second, third }

abstract interface class Scored {
  int get score;
  int get doubled;
  int bump(int amount);
}

enum Ranked implements Scored {
  low(2),
  middle.named(score: 5),
  high.redirect(9);

  @override
  final int score;
  final String label;

  const Ranked(this.score) : label = 'base', assert(score > 0);
  const Ranked.named({required this.score, this.label = 'named'})
    : assert(score > 0);
  const Ranked.redirect(int score)
    : this.named(score: score, label: 'redirect');
  factory Ranked.pick(bool high) => high ? Ranked.high : Ranked.low;

  @override
  int get doubled => score * 2;
  int get observed => tick(score);
  @override
  int bump(int amount) => score + amount;
  int operator +(int amount) => score + amount;

  int Function(int) explicitCapture() =>
      (int amount) => this.score + amount;
  int Function(int) implicitCapture() =>
      (int amount) => score + index + amount;
  int Function(int) nestedCapture(int offset) => () {
    final self = this;
    return (int amount) => self.score + score + offset + amount;
  }();

  static const bonus = 10;
  static int get threshold => bonus;
  static int scale(int value) => value * bonus;
}

enum Renamed {
  item(7),
  other(11);

  final int value;
  const Renamed(this.value);
  String get name => 'custom$value';
  @override
  String toString() => 'renamed:$value';
}

enum PrivateGetter {
  first(7),
  second(9);

  final int _value;
  const PrivateGetter(this._value);
  int get _name => _value;
  int get own => _name;
}

abstract interface class Carrier<T> {
  T get value;
  T read();
}

enum Rich<T> implements Carrier<T> {
  number<int>(4),
  text<String>('x'),
  fraction<double>(2.5);

  @override
  final T value;
  const Rich(this.value);
  @override
  T read() => value;
  bool matches(Object? candidate) => candidate is T;
  bool Function(Object?) checker() =>
      (Object? candidate) => candidate is T;
}

String enumValues() {
  var result = '';
  for (final value in Plain.values) {
    result += '${value.name}:${value.index};';
  }
  return result;
}

String enumStringForms(int index) {
  final value = Plain.values[index];
  final describe = value.toString;
  return '$value/${value.toString()}/${describe()}';
}

int enumIdentity() {
  const list = [Plain.first, Plain.second, Plain.first];
  const lookup = {Plain.first: 3, Plain.second: 5};
  var result = 0;
  if (identical(Plain.first, Plain.values[0])) result += 1;
  if (identical(list[0], list[2])) result += 2;
  if (identical(list[0], Plain.values[0])) result += 4;
  if (identical(Plain.values, Plain.values)) result += 8;
  if (Plain.first != Plain.second) result += 16;
  return result + lookup[Plain.values[0]]! * 100 + lookup[list[1]]! * 1000;
}

int enumValuesImmutable() {
  try {
    Plain.values.add(Plain.first);
  } on UnsupportedError {
    return Plain.values.length;
  }
  return -1;
}

int enumSwitch(int index) {
  final value = Plain.values[index];
  return switch (value) {
    Plain.first => 10,
    Plain.second => 20,
    Plain.third => 30,
  };
}

int enumSwitchStatement(int index) {
  switch (Plain.values[index]) {
    case Plain.first:
      return 11;
    case Plain.second:
      return 22;
    case Plain.third:
      return 33;
  }
}

int enumConstantPattern(int index) {
  Object value = Plain.values[index];
  if (value case Plain.second) return 7;
  return -1;
}

String enhancedConstructors() =>
    '${Ranked.low.score}:${Ranked.low.label};'
    '${Ranked.middle.score}:${Ranked.middle.label};'
    '${Ranked.high.score}:${Ranked.high.label}';

int enhancedMembers(int amount) {
  final value = Ranked.middle;
  final bump = value.bump;
  return value.doubled +
      value.bump(amount) +
      bump(amount + 1) +
      (value + amount + 2) +
      Ranked.threshold +
      Ranked.scale(amount);
}

int enumObjectPattern(int index) {
  final Object value = Ranked.values[index];
  return switch (value) {
    Ranked(index: 1, observed: var score) => score + 100,
    Ranked(observed: var score, index: var position) => score + position,
    _ => -1,
  };
}

int enhancedFactories(bool high) {
  final pick = Ranked.pick;
  final value = pick(high);
  return (identical(value, Ranked.pick(high)) ? 100 : 0) + value.score;
}

int enhancedClosures(int amount) {
  final value = Ranked.high;
  final explicit = value.explicitCapture();
  final implicit = value.implicitCapture();
  final nested = value.nestedCapture(20);
  return explicit(amount) + implicit(amount) + nested(amount);
}

int enumInterfaceDispatch(int index, int amount) {
  final Scored value = Ranked.values[index];
  final bump = value.bump;
  return value.score + value.doubled + value.bump(amount) + bump(amount + 1);
}

String customEnumNames(int index) {
  final value = Renamed.values[index];
  final describe = value.toString;
  return '${value.name}:$value:${value.toString()}:${describe()}';
}

String privateEnumGetter(int index) {
  final value = PrivateGetter.values[index];
  return '${value.name}:${value.index}:${value.own}:$value';
}

String _enumReceiver(Enum value) =>
    '${value.index}:${value.name}:$value:${value.toString()}';

String _enumBoundReceiver<T extends Enum>(T value) {
  final describe = value.toString;
  return '${value.index}:${value.name}:$value:${describe()}';
}

String enumReceivers(bool renamed) =>
    renamed ? _enumReceiver(Renamed.item) : _enumReceiver(Plain.second);

String enumBoundReceivers(bool renamed) => renamed
    ? _enumBoundReceiver(Renamed.other)
    : _enumBoundReceiver(Plain.third);

String genericEnumValues() {
  var result = '';
  for (final value in Rich.values) {
    result += '${value.name}:${value.index}:${value.value}:$value;';
  }
  return result;
}

int genericEnumTypes() {
  final Object number = Rich.number;
  final Object text = Rich.text;
  final Object values = Rich.values;
  var result = 0;
  if (number is Rich<int>) result += 1;
  if (number is! Rich<String>) result += 2;
  if (text is Rich<String>) result += 4;
  if (number is Carrier<int>) result += 8;
  if (text is! Carrier<int>) result += 16;
  if (values is List<Rich<dynamic>>) result += 32;
  if (values is! List<Rich<int>>) result += 64;
  if (identical(Rich.number, Rich.values[0])) result += 128;
  return result;
}

String genericEnumInterfaceDispatch() {
  final Carrier<int> number = Rich.number;
  final Carrier<String> text = Rich.text;
  final read = text.read;
  return '${number.value}:${number.read()}:${text.value}:${read()}';
}

int genericEnumChecks(Object? candidate) {
  final checkNumber = Rich.number.checker();
  final checkText = Rich.text.checker();
  var result = 0;
  if (Rich.number.matches(candidate)) result += 1;
  if (Rich.text.matches(candidate)) result += 2;
  if (checkNumber(candidate)) result += 4;
  if (checkText(candidate)) result += 8;
  return result;
}

String enumObjectInterpolation(bool renamed) {
  final Object value = renamed ? Renamed.item : Plain.first;
  return 'value=$value';
}

String genericEnumStringForms() {
  final describe = Rich.number.toString;
  return '${Rich.number.toString()}/${describe()}/${Rich.text.toString()}';
}

class EnumConstants {
  static const offset = 17;
  static const chosen = Ranked.middle;
  static const order = <Plain>[Plain.third, Plain.first];
}

int classEnumStaticConstants() =>
    EnumConstants.offset +
    EnumConstants.chosen.score +
    EnumConstants.order[0].index +
    Ranked.bonus;

String enumShorthand(bool first) {
  final Plain value = first ? .first : .third;
  final Ranked ranked = first ? .middle : .high;
  return '${value.name}:${ranked.score}:${ranked.index}';
}

String nullableEnum(bool present) {
  final Plain? value = present ? Plain.second : null;
  final describe = value?.toString;
  return '${value?.index}:${value?.name}:${value?.toString()}:'
      '${describe == null ? 'absent' : describe()}';
}
