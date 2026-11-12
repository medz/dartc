import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'typed_data.dart';

final class NativeTypedData() {
  final _library = NativeAssets(Target.host()).open('compiler/typed_data');
  late final lists = _library
      .lookupFunction<
        MemoryReport Function(Int64, Double),
        MemoryReport Function(int, double)
      >('typedLists');
  late final bytes = _library
      .lookupFunction<
        MemoryReport Function(Double),
        MemoryReport Function(double)
      >('byteViews');
  late final overlap = _library
      .lookupFunction<Int64 Function(), int Function()>(
        'overlappingTypedViews',
      );
  late final readonly = _library
      .lookupFunction<Int32 Function(), int Function()>('readonlyTypedViews');
  late final bounds = _library
      .lookupFunction<Bool Function(Int32), bool Function(int)>('typedBounds');
  late final shared = _library
      .lookupFunction<MemoryReport Function(Int32), MemoryReport Function(int)>(
        'sharedNativeViews',
      );
  late final collections = _library
      .lookupFunction<Bool Function(Int32), bool Function(int)>(
        'typedCollections',
      );
  void close() => _library.close();
}
