import 'environment_default.dart'
    if (flavor == 'native') 'environment_selected.dart';
import 'environment_default.dart'
    if (dart.library.js_interop) 'environment_default.dart'
    if (dart.library.io) 'environment_selected.dart'
    as platform;

const stringValues = {
  'text': String.fromEnvironment('text', defaultValue: 'fallback'),
  'empty': String.fromEnvironment('empty', defaultValue: 'fallback'),
  'missing': String.fromEnvironment('missing', defaultValue: 'fallback'),
  'dart.library.io': String.fromEnvironment(
    'dart.library.io',
    defaultValue: 'fallback',
  ),
  'dart.library.ffi': String.fromEnvironment(
    'dart.library.ffi',
    defaultValue: 'fallback',
  ),
  'dart.library.js_interop': String.fromEnvironment(
    'dart.library.js_interop',
    defaultValue: 'fallback',
  ),
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
  'dart.library.io': bool.fromEnvironment(
    'dart.library.io',
    defaultValue: true,
  ),
  'dart.library.js_util': bool.fromEnvironment(
    'dart.library.js_util',
    defaultValue: true,
  ),
  'dart.library.js_interop': bool.fromEnvironment(
    'dart.library.js_interop',
    defaultValue: true,
  ),
};
const presence = {
  'empty': bool.hasEnvironment('empty'),
  'invalid': bool.hasEnvironment('invalid'),
  'missing': bool.hasEnvironment('missing'),
  'dart.library.io': bool.hasEnvironment('dart.library.io'),
  'dart.library.js_interop': bool.hasEnvironment('dart.library.js_interop'),
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
  print(
    '${platform.selected}|$stringValues|$integerValues|$booleanValues|$presence',
  );
  print(const bool.hasEnvironment('dart.library.mirrors'));
}
