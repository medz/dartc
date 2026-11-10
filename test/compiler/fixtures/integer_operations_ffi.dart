import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'integer_operations.dart' show BinaryNative;

typedef BinaryDart = int Function(int, int);

final class IntegerOperations() {
  final _library = NativeAssets(Target.host())
      .open('compiler/integer_operations');

  late final truncate = _library.lookupFunction<BinaryNative, BinaryDart>(
    'truncate',
  );
  late final modulo = _library.lookupFunction<BinaryNative, BinaryDart>(
    'modulo',
  );
  late final remainder = _library.lookupFunction<BinaryNative, BinaryDart>(
    'remainder',
  );
  late final divideCompound = _library.lookupFunction<BinaryNative, BinaryDart>(
    'divideCompound',
  );
  late final divisionFailure = _library
      .lookupFunction<BinaryNative, BinaryDart>('divisionFailure');
  late final divisionType = _library
      .lookupFunction<Int64 Function(), int Function()>('divisionType');

  late final multiply = _library.lookupFunction<BinaryNative, BinaryDart>(
    'multiply',
  );
  late final bitAnd = _library.lookupFunction<BinaryNative, BinaryDart>(
    'bitAnd',
  );
  late final bitOr = _library.lookupFunction<BinaryNative, BinaryDart>('bitOr');
  late final bitXor = _library.lookupFunction<BinaryNative, BinaryDart>(
    'bitXor',
  );
  late final complement = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('complement');
  late final same = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('same');
  late final overlap = _library.lookupFunction<BinaryNative, BinaryDart>(
    'overlap',
  );
  late final compound = _library.lookupFunction<BinaryNative, BinaryDart>(
    'compound',
  );
  late final accumulate = _library.lookupFunction<BinaryNative, BinaryDart>(
    'accumulate',
  );

  void close() => _library.close();
}
