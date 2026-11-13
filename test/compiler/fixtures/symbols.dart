// shortcut: analyzer 14.7 drops private Symbol libraries, remove suppressions when its evaluator preserves them.
// ignore_for_file: equal_keys_in_const_map, equal_elements_in_const_set, const_eval_throws_exception, equal_keys_in_map_pattern, unreachable_switch_case

import 'symbols_dependency.dart' as other;
part 'symbols_part.dart';

const hidden = #_secret;
const keys = <Symbol, int>{hidden: 1, other.hidden: 2, Symbol('_secret'): 3};
const names = <Symbol>{hidden, other.hidden, Symbol('_secret')};
const nested = ([hidden, other.hidden], value: other.SymbolBox());
const checked = other.AssertSymbol();

class CapturedSymbols() implements other.SymbolContract {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.isMethod && invocation.memberName == #select
      ? invocation.positionalArguments.single
      : invocation.memberName;
}

int match(Symbol symbol) => switch (symbol) {
  #_secret => 1,
  other.hidden => 2,
  const Symbol('_secret') => 3,
  _ => 0,
};

void main() {
  final constructed = Symbol('_secret');
  print('local:${identical(hidden, partHidden)}:${hidden == partHidden}');
  print('foreign:${identical(hidden, other.hidden)}:${hidden == other.hidden}');
  print('constructor:${hidden == constructed}:${constructed == hidden}');
  print(
    'public:${identical(#visible, other.public)}:${#visible == Symbol('visible')}',
  );
  print(
    'folded:${other.equal}:${other.selected}:${const other.FieldSymbol().differs}',
  );
  print(
    'defaults:${identical(const other.SymbolBox(), const other.SymbolBox(other.hidden))}:'
    '${const other.InheritedSymbol().value == other.hidden}',
  );
  print(
    'constructors:${const other.SymbolFactory().value == other.hidden}:'
    '${const other.RedirectSymbol().value == other.hidden}',
  );
  print('covariance:${other.ForwardedSymbol().select() == other.hidden}');
  print(
    'nested:${identical(nested.$1[0], hidden)}:'
    '${identical(nested.$1[1], nested.value.value)}',
  );
  print(
    'collections:${keys[hidden]}:${keys[other.hidden]}:${keys[constructed]}:${names.length}',
  );
  print(
    'hash:${hidden.hashCode == partHidden.hashCode}:'
    '${names.contains(partHidden)}:${names.contains(constructed)}',
  );
  print(
    'patterns:${match(hidden)}:${match(other.hidden)}:${match(constructed)}',
  );
  final mapped = switch (keys) {
    {#_secret: final local, other.hidden: final foreign} => local + foreign,
    _ => 0,
  };
  print('map-pattern:$mapped');
  final receiver = CapturedSymbols();
  final dynamic dynamicReceiver = receiver;
  print(
    'invocations:${dynamicReceiver._secret() == hidden}:'
    '${other.callPrivate(receiver) == other.hidden}:'
    '${receiver.select() == other.hidden}',
  );
  print(
    'qualified:${identical(#_prefix.name, other.qualified)}:'
    '${#_prefix.name == const Symbol('_prefix.name')}',
  );
}
