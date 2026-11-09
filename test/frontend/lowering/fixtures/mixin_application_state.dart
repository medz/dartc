// ignore_for_file: annotate_overrides, use_primary_constructors, hash_and_equals
import 'mixin_application_state_private.dart' as foreign;

int sequence = 0;

mixin State {
  int value = ++sequence;
  int read() => value;
  int get observed => value;
  void write(int next) {
    value = next;
  }
}

class A with State {
  int get firstA => super.value;
  set firstA(int next) {
    super.value = next;
  }

  int firstRead() => super.read();
  int get firstObserved => super.observed;
  void firstWrite(int next) => super.write(next);
}

class B extends A with State {
  int get secondB => super.value;
  set secondB(int next) {
    super.value = next;
  }
}

String independentState() {
  sequence = 0;
  final value = B();
  return '${value.firstA}:${value.secondB}:${value.read()}:'
      '${value.firstRead()}:${value.observed}:${value.firstObserved}:'
      '$sequence';
}

String independentStateWrites() {
  sequence = 0;
  final value = B();
  value.firstA = 30;
  value.secondB = 40;
  final before = '${value.firstA}:${value.secondB}';
  value.firstWrite(50);
  return '$before:${value.firstA}:${value.secondB}:'
      '${value.firstRead()}:${value.firstObserved}';
}

mixin LazyState {
  late int lazy = ++sequence;
  late final int once = ++sequence;
  late final int assigned;
  late int unbound;
}

class LazyA with LazyState {
  int get firstLazy => super.lazy;
  set firstLazy(int next) {
    super.lazy = next;
  }

  int get firstOnce => super.once;
  int get firstAssigned => super.assigned;
  set firstAssigned(int next) {
    super.assigned = next;
  }

  int get firstUnbound => super.unbound;
}

class LazyB extends LazyA with LazyState {
  int get secondLazy => super.lazy;
  int get secondOnce => super.once;
  int get secondAssigned => super.assigned;
  set secondAssigned(int next) {
    super.assigned = next;
  }
}

String independentLazyState() {
  sequence = 0;
  final value = LazyB();
  final before = sequence;
  final first = value.firstLazy;
  final second = value.secondLazy;
  final firstFinal = value.firstOnce;
  final secondFinal = value.secondOnce;
  return '$before:$first:$second:$firstFinal:$secondFinal:'
      '${value.firstLazy}:${value.secondLazy}:'
      '${value.firstOnce}:${value.secondOnce}:$sequence';
}

String lazyAssignmentSkipsOnlyOwnInitializer() {
  sequence = 0;
  final value = LazyB();
  value.firstLazy = 90;
  return '${value.firstLazy}:${value.secondLazy}:$sequence';
}

String independentLateFinalWrites() {
  sequence = 0;
  final value = LazyB();
  value.firstAssigned = 10;
  value.secondAssigned = 20;
  return '${value.firstAssigned}:${value.secondAssigned}:$sequence';
}

int lateFinalSecondWrite() {
  sequence = 0;
  final value = LazyB();
  value.firstAssigned = 10;
  value.secondAssigned = 20;
  value.firstAssigned = 30;
  return value.firstAssigned;
}

int lateReadDoesNotBorrowOtherSlot() {
  sequence = 0;
  final value = LazyB();
  value.unbound = 8;
  return value.firstUnbound;
}

class Base {
  int f() => 1;
}

mixin Prefix on Base {
  int f() => super.f() + 10;
  int Function() superTearoff() => super.f;
  int Function() superClosure() =>
      () => super.f();
}

class PrefixA extends Base with Prefix {
  int firstCall() => super.f();
  int Function() firstTearoff() => super.superTearoff();
  int Function() firstClosure() => super.superClosure();
}

class PrefixB extends PrefixA with Prefix {
  int secondCall() => super.f();
  int Function() secondTearoff() => super.superTearoff();
  int Function() secondClosure() => super.superClosure();
}

class MostDerived extends PrefixB {
  int f() => 100;
}

String lexicalSuperCalls() {
  final value = MostDerived();
  return '${value.f()}:${value.firstCall()}:${value.secondCall()}';
}

String lexicalSuperTearoffs() {
  final value = MostDerived();
  final first = value.firstTearoff();
  final second = value.secondTearoff();
  return '${first()}:${second()}:${first == second}:'
      '${first == value.firstTearoff()}:${second == value.secondTearoff()}';
}

String lexicalSuperEscapedClosures() {
  final value = MostDerived();
  final first = value.firstClosure();
  final second = value.secondClosure();
  return '${first()}:${second()}:${value.f()}';
}

class HashBase {
  int get hashCode => 7;
}

mixin class HashMixin {
  int parentHash() => super.hashCode;
  int Function() parentHashClosure() =>
      () => super.hashCode;
}

class HashApplied extends HashBase with HashMixin {
  int get hashCode => 99;
}

String mixinClassLexicalSuper() {
  final value = HashApplied();
  final closure = value.parentHashClosure();
  return '${value.hashCode}:${value.parentHash()}:${closure()}';
}

class PrivateApplied with foreign.PrivateMixin {
  int _value() => 99;
  int localValue() => _value();
}

String privateClosureProvenance() {
  final value = PrivateApplied();
  final closure = value.privateClosure();
  final tearoff = value.privateTearoff();
  return '${value.localValue()}:${closure()}:${tearoff()}';
}

class BoundBase {
  int get boundValue => 23;
}

mixin BoundMixin on BoundBase {
  int fromBound() => boundValue;
}

class BoundApplied extends BoundBase with BoundMixin {}

class InterfaceOnly implements BoundMixin {
  int get boundValue => 19;
  int fromBound() => 31;
}

String constraintReceiverView() {
  final BoundMixin unrelated = InterfaceOnly();
  return '${BoundApplied().fromBound()}:${unrelated.fromBound()}:'
      '${isBoundBase(unrelated)}';
}

bool isBoundBase(Object value) => value is BoundBase;

String effects = '';
int effectSequence = 0;
int effect(String label) {
  effects += label;
  return ++effectSequence;
}

class EffectBase {
  int base = effect('B');
  new named([int value = 5]) {
    effects += 'b$value';
  }
}

mixin EffectM {
  int m = effect('M');
}

mixin EffectN {
  int n = effect('N');
}

class EffectC extends EffectBase with EffectM, EffectN {
  int c = effect('C');
  new() : super.named(effect('A')) {
    effects += 'c';
  }
}

class EffectAlias = EffectBase with EffectM, EffectN;

String constructorFieldEffects() {
  effects = '';
  effectSequence = 0;
  final value = EffectC();
  final concrete = '$effects:${value.c}:${value.n}:${value.m}:${value.base}';
  effects = '';
  effectSequence = 0;
  final alias = EffectAlias.named();
  return '$concrete/$effects:${alias.n}:${alias.m}:${alias.base}';
}
