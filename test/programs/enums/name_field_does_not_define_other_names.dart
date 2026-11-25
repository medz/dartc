enum Value {
  item;

  final int _name = 1;
}

void main() {
  print(Value.item._name$dartc);
  // error 20: The member '_name$dartc' isn't defined for the type 'Value'.
}
