import 'dart:ffi';
import 'dart:io';

import 'package:dartc/layout/memory.dart';
import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

void main(List<String> arguments) {
  final library = NativeAssets(Target.host()).open('compiler/heap_runtime');
  final create = library
      .lookupFunction<Void Function(Int64), void Function(int)>(
        'createManaged',
      );
  create(42);
  final value = int.parse(arguments[1]);
  stdout.writeln('armed');
  if (arguments[0] == 'entry') {
    final context = library.lookupFunction<Int64 Function(), int Function()>(
      'phaseContext',
    )();
    Pointer<Int64>.fromAddress(context + RuntimeContext.phase).value = value;
    library.lookupFunction<Int64 Function(Int64), int Function(int)>(
      'capacity',
    )(1);
  } else {
    library.lookupFunction<Void Function(Int64), void Function(int)>(
      arguments[0],
    )(value);
  }
  exit(99);
}
