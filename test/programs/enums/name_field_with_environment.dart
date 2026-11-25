enum FieldInitializer {
  item;

  final bool _name = .fromEnvironment('dart.library.js_interop');
}

enum ConstructorInitializer {
  item(-0.0);

  const ConstructorInitializer(double zero)
    : _name = (
        const bool.fromEnvironment('dart.library.js_util'),
        zero ==
            (const bool.fromEnvironment('dart.library.js_interop') ? 1.0 : 0.0),
      );

  final (bool, bool) _name;
}

void main() {
  print((
    FieldInitializer.item.name,
    FieldInitializer.item._name,
  )); // expect: (item, false)
  print((
    ConstructorInitializer.item.name,
    ConstructorInitializer.item._name,
  )); // expect: (item, (false, true))
}
