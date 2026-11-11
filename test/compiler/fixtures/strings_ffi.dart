import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Strings() {
  final _library = NativeAssets(Target.host()).open('compiler/strings');
  late final length = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('stringLength');
  late final codeUnits = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'stringCodeUnits',
      );
  late final unitsState = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'stringUnitsState',
      );
  late final savedUnit = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'stringSavedUnit',
      );
  late final codesProtocol = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('stringCodesProtocol');
  late final encode = _library
      .lookupFunction<
        Int64 Function(
          Pointer<Int64>,
          Int64,
          Int64,
          Int64,
          Pointer<Uint16>,
          Int64,
        ),
        int Function(Pointer<Int64>, int, int, int, Pointer<Uint16>, int)
      >('encodeCharacters');
  late final read = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64, Int64),
        int Function(int, int, int, int)
      >('stringRead');
  late final failure = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('stringFailure');
  late final construct = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('stringConstruct');
  late final growth = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('stringGrowth');
  late final invalidCode = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'stringInvalidCode',
      );
  late final saved = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('stringSaved');

  void close() => _library.close();
}
