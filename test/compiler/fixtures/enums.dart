import '../../frontend/lowering/fixtures/enum_private_storage.dart';
import '../../frontend/lowering/fixtures/enum_private_storage_use.dart';

void main() {
  for (var index = 0; index < Code.values.length; index++) {
    print(privateEnumStorage(index));
  }
  print(privateEnumInitializers());
  print(crossLibraryEnumStorage());
  final byName = Code.values.byName;
  print('${byName('second').own}:${Code.values.asNameMap()['third']!.own}');
  final ordered = Code.values.toList()..sort(Enum.compareByName);
  print(ordered.map((value) => value.name).join(','));
  print(
    '${Enum.compareByIndex(Code.third, Code.first)}:'
    '${identical(Code.first, Code.values.first)}',
  );
  try {
    byName('missing');
    throw StateError('Missing name accepted');
  } on ArgumentError catch (error) {
    print('${error.name}:${error.invalidValue}');
  }
}
