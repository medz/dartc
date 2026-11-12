@patch
T unsafeCast<T>(dynamic value) => value as T;

@patch
class Symbol {
  final String? _privateLibrary = null;
  @patch
  const Symbol(String name) : _name = name;
  @patch
  bool operator ==(Object other) =>
      other is Symbol &&
      _name == other._name &&
      _privateLibrary == other._privateLibrary;
  @patch
  int get hashCode => _name.hashCode ^ (_privateLibrary?.hashCode ?? 0);
  @patch
  String toString() => 'Symbol("$_name")';
  @patch
  static String computeUnmangledName(Symbol symbol) => symbol._name;
}
