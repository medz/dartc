import 'environment_default.dart'
    if (flavor == 'native') 'environment_selected.dart';

const stringValues = {
  'text': String.fromEnvironment('text', defaultValue: 'fallback'),
  'empty': String.fromEnvironment('empty', defaultValue: 'fallback'),
  'missing': String.fromEnvironment('missing', defaultValue: 'fallback'),
};
const integerValues = {
  'number': int.fromEnvironment('number', defaultValue: 99),
  'minimum': int.fromEnvironment('minimum', defaultValue: 99),
  'overflow': int.fromEnvironment('overflow', defaultValue: 99),
  'invalid': int.fromEnvironment('invalid', defaultValue: 99),
  'missing': int.fromEnvironment('missing', defaultValue: 99),
};
const booleanValues = {
  'enabled': bool.fromEnvironment('enabled', defaultValue: true),
  'invalid': bool.fromEnvironment('invalid', defaultValue: true),
  'empty': bool.fromEnvironment('empty', defaultValue: true),
  'missing': bool.fromEnvironment('missing', defaultValue: true),
};
const presence = {
  'empty': bool.hasEnvironment('empty'),
  'invalid': bool.hasEnvironment('invalid'),
  'missing': bool.hasEnvironment('missing'),
};

void check(bool value) {
  if (!value) throw StateError('Compilation environment');
}

void main() {
  final readString = String.fromEnvironment;
  final readInt = int.fromEnvironment;
  final readBool = bool.fromEnvironment;
  final hasValue = bool.hasEnvironment;
  for (final MapEntry(:key, :value) in stringValues.entries) {
    check(String.fromEnvironment(key, defaultValue: 'fallback') == value);
    check(readString(key, defaultValue: 'fallback') == value);
  }
  for (final MapEntry(:key, :value) in integerValues.entries) {
    check(int.fromEnvironment(key, defaultValue: 99) == value);
    check(readInt(key, defaultValue: 99) == value);
  }
  for (final MapEntry(:key, :value) in booleanValues.entries) {
    check(bool.fromEnvironment(key, defaultValue: true) == value);
    check(readBool(key, defaultValue: true) == value);
  }
  for (final MapEntry(:key, :value) in presence.entries) {
    check(bool.hasEnvironment(key) == value);
    check(hasValue(key) == value);
  }
  check(readString('missing') == '');
  check(readInt('missing') == 0);
  check(!readBool('missing'));
  print(selected);
  print('$stringValues|$integerValues|$booleanValues|$presence');
}
