// Exercise checked generic entry types in the SDK differential fixture.
// ignore_for_file: unnecessary_type_check
import 'effects.dart';

extension CallInt on int {
  int call(int value, {int extra = 5}) {
    tick(4);
    return this + value + extra;
  }
}

extension CallNullable on int? {
  int call([int value = 6]) {
    tick(4);
    return (this ?? 20) + value;
  }
}

extension CallList<T> on List<T> {
  bool call<U extends T>(U value, {bool first = false}) {
    tick(4);
    return value is U && (first ? this[0] is T : T == num);
  }
}

class Host<T>(final T seed) {
  T get value {
    tick(2);
    return seed;
  }
}

extension HostValue<T> on Host<T> {
  T get extensionValue {
    tick(2);
    return seed;
  }
}

int get top {
  tick(2);
  return 9;
}

int direct(int seed) {
  final value = tick(seed);
  return value(tick(3)) + (value)(tick(7), extra: tick(8));
}

int virtualGetter(int seed) => Host(seed).value(tick(3));
int parenthesizedGetter(int seed) => (Host(seed).value)(tick(3));
int extensionGetter(int seed) => Host(seed).extensionValue(tick(3));
int explicitGetter(int seed) => CallInt(Host(seed).value)(tick(3));
int topGetter() => top(tick(3));
int explicit(int seed) => CallInt(tick(seed))(tick(3));
int lexical(int seed) => CallNullable(seed)();
int nullable(int? seed) => seed(tick(3));
int? nullAwareGetter(bool absent) {
  final host = absent ? null : Host(9);
  return host?.value(tick(3));
}

bool generic(int seed) {
  final List<int> ints = [seed];
  final List<num> numbers = ints;
  return numbers<int>(seed) &&
      ints(seed, first: true) &&
      CallList<num>(ints)<int>(seed);
}

T genericReceiver<T>(T value) => [value](value, first: true) ? value : throw 0;
int retainedType(int seed) => genericReceiver(seed);

int checkedReceiver(Object? value) {
  dynamic input = value;
  try {
    return CallInt(input)(tick(3));
  } finally {
    tick(8);
  }
}

int checkedArgument(Object? value) {
  dynamic input = value;
  try {
    return (1)(input, extra: tick(7));
  } finally {
    tick(8);
  }
}

int failure(int stage) {
  try {
    return CallInt(tick(stage == 1 ? -1 : 1))(tick(stage == 3 ? -3 : 3));
  } finally {
    tick(8);
  }
}

class RealCall() {
  int call(int value) => value + tick(10);
}

extension IgnoreReal on RealCall {
  int call(int value) => value + tick(11);
}

int realMember() => RealCall()(tick(3));
Object? dynamicMiss() {
  dynamic value = 1;
  return value(tick(3));
}

bool genericGetters(int seed) {
  final host = Host<List<num>>(<int>[seed]);
  return host.value<int>(seed) &&
      (host.value)<int>(seed) &&
      host.extensionValue<int>(seed);
}

bool? nullAwareGenericGetter(bool absent) {
  final Host<List<num>>? host = absent ? null : Host<List<num>>(<int>[1]);
  return host?.value<int>(tick(3));
}

bool genericReceiverCheck(bool valid) {
  dynamic value = valid ? <int>[1] : <String>['bad'];
  try {
    return CallList<num>(value)<int>(tick(3));
  } finally {
    tick(8);
  }
}

class FailingHost(final int stage) {
  int get value => tick(stage == 2 ? -2 : 2);
}

extension FailingValue on FailingHost {
  int get extensionValue => tick(stage == 2 ? -2 : 2);
}

int getterFailure(int stage, int form) {
  final host = FailingHost(stage);
  dynamic argument() {
    tick(stage == 3 ? -3 : 3);
    return stage == 1 ? 'bad' : 1;
  }

  try {
    return switch (form) {
      0 => host.value(argument()),
      1 => (host.value)(argument()),
      2 => host.extensionValue(argument()),
      _ => CallInt(host.value)(argument()),
    };
  } finally {
    tick(8);
  }
}
