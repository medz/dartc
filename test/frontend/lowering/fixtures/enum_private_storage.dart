enum Code {
  first(7),
  second.named(value: -3),
  third.redirect(7);

  const new(this._name);
  const new named({required int value}) : _name = value;
  const new redirect(int value) : this.named(value: value);

  final int _name;
  int get own => _name;
}

enum const FixedName() {
  item;

  final String _name = 'own';
  String get own => _name;
}

enum const GenericName<T>(final T _name) {
  number<int>(42),
  text<String>('own');

  T get own => _name;
}

const alias = Code.second;
const nested = <Object>[Code.first, Code.third];
const record = (alias,);
const same = identical(alias, Code.second);
const different = identical(Code.first, Code.third);
const lookup = {Code.first: 11, Code.third: 33};

String privateEnumStorage(int index) {
  final value = Code.values[index];
  final Enum base = value;
  return '${value._name}:${value.name}:${value.index}:$value:${base.name}';
}

String privateEnumInitializers() =>
    '${FixedName.item.own}:${FixedName.item.name}:${FixedName.item.index}:'
    '${GenericName.number.own}:${GenericName.number.name}:'
    '${GenericName.text.own}:${GenericName.text.name}';
