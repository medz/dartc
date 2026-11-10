import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class FunctionInstantiation() {
  final _library = NativeAssets(Target.host())
      .open('compiler/function_instantiation');
  late final staticFunctions = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'staticFunctions',
      );
  late final closures = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('closures');
  late final constructors = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('constructors');
  late final methods = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('methods');
  late final hashes = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'functionHashes',
      );
  late final types = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('typeHashes');
  late final exceptions = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('exceptions');
  late final lexicalConstructors = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'lexicalConstructors',
      );
  late final keepConstructor = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'keepConstructor',
      );
  late final callConstructor = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'callConstructor',
      );
  late final constructorFailures = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'constructorFailures',
      );

  void close() => _library.close();
}
