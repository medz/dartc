import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Frames() {
  final _library = NativeAssets(Target.host()).open('abi/frames');
  late final roundTrip = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'frame_round_trip',
      );

  void close() => _library.close();
}

final class FloatingFrames() {
  final _library = NativeAssets(Target.host()).open('abi/floating_frames');
  late final roundTrip = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'floating_frame',
      );

  void close() => _library.close();
}
