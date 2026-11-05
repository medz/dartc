// ignore_for_file: annotate_overrides, unnecessary_type_check, use_primary_constructors, unnecessary_type_name_in_constructor, use_super_parameters
import 'effects.dart' as effects;
import 'mixins_private.dart' as foreign;

class Base {
  final int seed;
  Base([this.seed = 3]) {
    effects.tick(10);
  }
  Base.named({this.seed = 5}) {
    effects.tick(11);
  }
  Base.required({required this.seed}) {
    effects.tick(12);
  }
  int value() => seed;
}

mixin First on Object {
  int value() => 20;
  int invokeValue() => value();
  int add(int value, [int extra = 7]) => value + extra;
  int named({int value = 8}) => value;
  int get score => value() + 1;
  set score(int value) {
    effects.tick(value);
  }

  int Function() capture() =>
      () => value();
}

mixin Last {
  int value() => 30;
}

class Applied extends Base with First, Last {
  final int own = effects.tick(13);
  Applied(int seed) : super(seed) {
    effects.tick(14);
  }
}

class Own extends Base with First, Last {
  int value() => 40;
}

class Repeated extends Base with First, Last, First {}

class Alias = Base with First, Last;
class SecondAlias = Alias with First;

class Unrelated with First {}

class PrivateApplied with foreign.Foreign {
  int _value() => 99;
  int localValue() => _value();
}

String overrideOrder() {
  final applied = Applied(2);
  final own = Own();
  final repeated = Repeated();
  return '${applied.value()}:${applied.invokeValue()}:${applied.score}:'
      '${own.value()}:${own.invokeValue()}:${own.score}:'
      '${repeated.value()}:${repeated.invokeValue()}:${repeated.score}:'
      '${applied.seed}:${applied.own}';
}

String interfaceDispatch() {
  First first = Applied(2);
  Last last = Own();
  Base base = Repeated();
  final unrelated = Unrelated();
  return '${first.value()}:${first.invokeValue()}:${last.value()}:'
      '${base.value()}:${unrelated.invokeValue()}:'
      '${first is First}:${first is Last}:${first is Base}:'
      '${(base as First).score}:${unrelated is Base}';
}

String dynamicMembers() {
  dynamic value = Applied(2);
  value.score = 15;
  final method = value.add;
  final named = value.named;
  return '${value.value()}:${value.score}:${value.add(2)}:'
      '${value.add(2, 4)}:${method(3)}:${method(3, 5)}:'
      '${value.named()}:${named(value: 9)}';
}

String tearoffs() {
  final value = Applied(2);
  First first = value;
  dynamic dynamicValue = value;
  final method = value.add;
  final firstMethod = first.add;
  final dynamicMethod = dynamicValue.add;
  final other = Applied(2).add;
  final capture = first.capture();
  return '${method == firstMethod}:${method == dynamicMethod}:'
      '${method == other}:${method(2)}:${firstMethod(3, 4)}:'
      '${dynamicMethod(5)}:${capture()}';
}

String aliasConstructors() {
  final a = Alias();
  final b = Alias(6);
  final c = Alias.named();
  final d = Alias.named(seed: 7);
  final e = Alias.required(seed: 8);
  final f = SecondAlias.named(seed: 9);
  return '${a.seed}:${b.seed}:${c.seed}:${d.seed}:${e.seed}:${f.seed}:'
      '${a.value()}:${f.value()}:${f is First}:${f is Last}:${f is Base}';
}

String aliasConstructorTearoffs() {
  final create = Alias.new;
  final named = Alias.named;
  final required = Alias.required;
  return '${create().seed}:${create(6).seed}:${named().seed}:'
      '${named(seed: 7).seed}:${required(seed: 8).seed}';
}

String privateMembers() {
  final value = PrivateApplied();
  final method = value.foreignTearoff();
  return '${value.localValue()}:${value.foreignValue()}:'
      '${foreign.callForeign(value)}:${method()}:${foreign.isForeign(value)}';
}

class Earlier extends Base with First {
  int Function(int, [int]) earlierTearoff() => super.add;
  int earlierCall() => super.add(2);
}

class Later extends Earlier with Last, First {
  int Function(int, [int]) laterTearoff() => super.add;
  int laterCall() => super.add(2);
  int value() => 50;
  int parentValue() => super.value();
}

String superMembers() {
  final value = Later();
  final earlier = value.earlierTearoff();
  final later = value.laterTearoff();
  return '${value.earlierCall()}:${value.laterCall()}:'
      '${value.parentValue()}:${value.invokeValue()}:'
      '${earlier(3)}:${later(3)}:${earlier == later}:'
      '${earlier == value.earlierTearoff()}:${later == value.laterTearoff()}';
}

mixin Missing {
  dynamic noSuchMethod(Invocation invocation) =>
      100 + invocation.positionalArguments.length;
}

class Fallback with Missing {}

String missingMembers() {
  dynamic value = Fallback();
  return '${value.absent(1, 2)}:${value.absentNamed(amount: 3)}:'
      '${value.absentGetter}';
}

mixin class Plain {
  int plain() => 61;
}

class PlainApplied with Plain {}

String mixinClass() {
  final value = PlainApplied();
  Plain typed = value;
  return '${value.plain()}:${typed.plain()}:${value is Plain}';
}
