import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'native_aggregates.dart';

final class NativeAggregates() {
  final _library = NativeAssets(Target.host())
      .open('compiler/native_aggregates');
  late final translate = _library
      .lookupFunction<
        Point Function(Point, Double),
        Point Function(Point, double)
      >('translate');
  late final mixed = _library
      .lookupFunction<Mixed Function(Mixed, Int32), Mixed Function(Mixed, int)>(
        'changeMixed',
      );
  late final large = _library
      .lookupFunction<Large Function(Large, Int64), Large Function(Large, int)>(
        'changeLarge',
      );
  late final union = _library
      .lookupFunction<Choice Function(Choice), Choice Function(Choice)>(
        'negateChoice',
      );
  late final copyNativeState = _library
      .lookupFunction<
        Void Function(Pointer<Mixed>, Pointer<Mixed>),
        void Function(Pointer<Mixed>, Pointer<Mixed>)
      >('copyNativeState');
  late final accumulate = _library
      .lookupFunction<
        Void Function(Pointer<Mixed>, Double),
        void Function(Pointer<Mixed>, double)
      >('accumulate');
  late final packed = _library
      .lookupFunction<
        PackedValue Function(PackedValue),
        PackedValue Function(PackedValue)
      >('packed');
  late final nested = _library
      .lookupFunction<
        Nested Function(Nested, Bool),
        Nested Function(Nested, bool)
      >('nested');
  late final applyPoint = _library
      .lookupFunction<
        Point Function(Pointer<NativeFunction<PointTransform>>, Point, Double),
        Point Function(Pointer<NativeFunction<PointTransform>>, Point, double)
      >('applyPoint');
  late final applyLarge = _library
      .lookupFunction<
        Large Function(Pointer<NativeFunction<LargeTransform>>, Large, Int64),
        Large Function(Pointer<NativeFunction<LargeTransform>>, Large, int)
      >('applyLarge');
  late final stackPoint = _library
      .lookupFunction<
        Point Function(
          Double,
          Double,
          Double,
          Double,
          Double,
          Double,
          Double,
          Point,
          Double,
        ),
        Point Function(
          double,
          double,
          double,
          double,
          double,
          double,
          double,
          Point,
          double,
        )
      >('stackPoint');
  final _process = DynamicLibrary.process();
  late final arrays = _library
      .lookupFunction<
        Arrays Function(Arrays, Int32),
        Arrays Function(Arrays, int)
      >('updateArrays');
  late final arrayBounds = _library
      .lookupFunction<Int32 Function(Arrays, Int32), int Function(Arrays, int)>(
        'arrayBounds',
      );
  late final copyArrays = _library
      .lookupFunction<
        Arrays Function(Arrays, Arrays),
        Arrays Function(Arrays, Arrays)
      >('copyArrays');
  late final copyArrayPrefix = _library
      .lookupFunction<Arrays Function(Arrays), Arrays Function(Arrays)>(
        'copyArrayPrefix',
      );
  late final arrayViews = _library
      .lookupFunction<Arrays Function(Arrays), Arrays Function(Arrays)>(
        'updateArrayViews',
      );
  late final arrayViewFailure = _library
      .lookupFunction<Bool Function(Arrays, Int32), bool Function(Arrays, int)>(
        'arrayViewFailure',
      );
  late final retainArrayViews = _library
      .lookupFunction<Void Function(Double), void Function(double)>(
        'retainArrayViews',
      );
  late final readArrayViews = _library
      .lookupFunction<Arrays Function(Int32), Arrays Function(int)>(
        'readArrayViews',
      );
  late final sumVariableRows = _library
      .lookupFunction<
        Double Function(Pointer<VariableRows>, Int32),
        double Function(Pointer<VariableRows>, int)
      >('sumVariableRows');
  late final variablePrefix = _library.lookup<NativeFunction<VariablePrefix>>(
    'changeVariablePrefix',
  );
  late final callVariablePrefix = _library
      .lookupFunction<
        Double Function(
          Pointer<NativeFunction<VariablePrefix>>,
          Pointer<VariableRows>,
        ),
        double Function(
          Pointer<NativeFunction<VariablePrefix>>,
          Pointer<VariableRows>,
        )
      >('callVariablePrefix');
  late final shiftVariablePoints = _library
      .lookupFunction<
        Void Function(Pointer<VariablePoints>, Int32, Double),
        void Function(Pointer<VariablePoints>, int, double)
      >('shiftVariablePoints');
  late final sumVariableGrid = _library
      .lookupFunction<
        Int64 Function(Pointer<VariableGrid>, Int32),
        int Function(Pointer<VariableGrid>, int)
      >('sumVariableGrid');
  late final retainVariableRow = _library
      .lookupFunction<Bool Function(Double), bool Function(double)>(
        'retainVariableRow',
      );
  late final readVariableRow = _library
      .lookupFunction<Double Function(Int32), double Function(int)>(
        'readVariableRow',
      );
  late final _allocate = _process
      .lookupFunction<
        Pointer<Void> Function(IntPtr, IntPtr),
        Pointer<Void> Function(int, int)
      >('calloc');
  late final _free = _process
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  Pointer<T> allocate<T extends NativeType>(int bytes) {
    final value = _allocate(1, bytes).cast<T>();
    if (value == nullptr) {
      throw StateError('Cannot allocate native fixture storage.');
    }
    return value;
  }

  void free(Pointer<NativeType> state) => _free(state.cast());
  void close() => _library.close();
}
