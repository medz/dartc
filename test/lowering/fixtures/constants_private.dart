// ignore_for_file: unnecessary_type_name_in_constructor, use_primary_constructors

class PrivateBase<T> {
  final T _value;
  const PrivateBase(this._value);
  T get baseValue => _value;
}
