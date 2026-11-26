// official: Dart 3.14.0 leaves out the check of the implicitly covariant write (pkg/front_end, field/declaration.dart).
class Box<T> {
  late final T value;
}

class CheckedBox<T> {
  covariant late final T value;
}

void main() {
  final narrow = Box<String>();
  Box<Object> wide = narrow;
  try {
    wide.value = 42;
    print('stored');
  } on TypeError {
    print('TypeError'); // expect: TypeError
  }
  wide.value = 'a';
  print(narrow.value); // expect: a
  try {
    wide.value = 'b';
  } on Error catch (e) {
    print(e); // expect: LateInitializationError: Field 'value' has already been initialized.
  }
  final checked = CheckedBox<String>();
  CheckedBox<Object> checkedWide = checked;
  try {
    checkedWide.value = 42;
    print('stored');
  } on TypeError {
    print('TypeError'); // expect: TypeError
  }
}
