// ignore_for_file: dead_code, unnecessary_const, unnecessary_type_name_in_constructor, use_primary_constructors

const a = #_p;
const b = a == const Symbol('_p');
const selected = b ? 1 : 2;
const publicSelected = b ? #public : #other;

class FieldBox {
  final bool value = #_field == const Symbol('_field');
  const FieldBox();
}

class InitializerBox {
  final bool value;
  const InitializerBox()
    : value = #_initializer == const Symbol('_initializer');
}

class DefaultBox {
  final Object value;
  const DefaultBox([this.value = #_default]);
}

class AssertionBox {
  const AssertionBox() : assert(true || #_assert == const Symbol('_assert'));
}

class ParentBox {
  final bool value;
  const ParentBox() : value = #_parent == const Symbol('_parent');
}

class ChildBox extends ParentBox {
  const ChildBox();
}

class RedirectBox {
  final Object value;
  const RedirectBox() : this.target(#_redirect);
  const RedirectBox.target(this.value);
}

abstract class FactoryBox {
  const factory FactoryBox() = FieldBoxFactory;
}

class FieldBoxFactory implements FactoryBox {
  final bool value = #_factory == const Symbol('_factory');
  const FieldBoxFactory();
}

class SafeBox {
  final int value;
  const SafeBox([this.value = 1]);
}

class SafeNullDefault {
  final Object? value;
  const SafeNullDefault([this.value]);
}

class ReferencedInitializerBox {
  final int value;
  const ReferencedInitializerBox() : value = selected;
}

class ReferencedFieldBox {
  final int value = selected;
  const ReferencedFieldBox();
}

class ReferencedDefaultBox {
  final int value;
  const ReferencedDefaultBox([this.value = selected]);
}

class SuperArgumentBox extends SafeBox {
  const SuperArgumentBox() : super(selected);
}

class SafeInheritedBox extends SafeBox {
  const SafeInheritedBox([super.value]);
}

class UnsafeInheritedBox extends ReferencedDefaultBox {
  const UnsafeInheritedBox([super.value]);
}

class SafeInheritedAgain extends SafeInheritedBox {
  const SafeInheritedAgain([super.value]);
}

class UnsafeInheritedAgain extends UnsafeInheritedBox {
  const UnsafeInheritedAgain([super.value]);
}
