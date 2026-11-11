import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Lists() {
  final _library = NativeAssets(Target.host()).open('compiler/lists');
  late final slice = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64),
        int Function(int, int, int)
      >('listSlice');
  late final copy = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listCopy',
      );
  late final copyProtocol = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listCopyProtocol',
      );
  late final sliceMutability = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listSliceMutability',
      );
  late final sliceReferences = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listSliceReferences',
      );
  late final slicePattern = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listSlicePattern',
      );
  late final constantOnly = _library
      .lookupFunction<Int64 Function(), int Function()>('listConstantOnly');
  late final append = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listAppend');
  late final appendFailures = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listAppendFailures',
      );
  late final appendProtocol = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listAppendProtocol',
      );
  late final spread = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listSpread');
  late final appendReferences = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listAppendReferences',
      );
  late final iteratorProtocol = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'iteratorProtocol',
      );
  late final iteration = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listIteration',
      );
  late final iteratorMutation = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listIteratorMutation',
      );
  late final iteratorState = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listIteratorState',
      );
  late final iteratorFinish = _library
      .lookupFunction<Int64 Function(), int Function()>('listIteratorFinish');
  late final constants = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listConstants',
      );
  late final constMutation = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listConstMutation',
      );
  late final values = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listValues',
      );
  late final fixed = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listFixed',
      );
  late final resize = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listResize');
  late final references = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listReferences',
      );
  late final saved = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listSaved');
  late final cycles = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listCycles');
  late final failures = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listFailures',
      );
  late final dispatch = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listDispatch');
  late final factories = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listFactories',
      );
  late final doubles = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'listDoubles',
      );
  late final order = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listOrder');

  void close() => _library.close();
}
