const hidden = #_secret;
const public = #visible;
const qualified = #_prefix.name;
const constructed = Symbol('_secret');
const equal = hidden == constructed;
const selected = equal ? 1 : 2;

class const SymbolBox([@override final Symbol value = #_secret])
    implements SymbolFactory;

abstract class SymbolFactory {
  const factory() = SymbolBox;
  Symbol get value;
}

class const RedirectSymbol.target(final Symbol value) {
  const new() : this.target(#_secret);
}

class SymbolParent() {
  Object? select([Object value = 0]) => value;
}

abstract class CovariantSymbol() extends SymbolParent {
  @override
  Object? select([covariant Symbol value = #_secret]);
}

class ForwardedSymbol() extends CovariantSymbol;

class const InheritedSymbol([super.value]) extends SymbolBox;

class const FieldSymbol() {
  final bool differs = #_secret != const Symbol('_secret');
}

class const AssertSymbol() {
  this : assert(#_secret != const Symbol('_secret'));
}

abstract class SymbolContract() {
  Symbol select([Symbol value = #_secret]);
}

Symbol callPrivate(dynamic receiver) => receiver._secret();
