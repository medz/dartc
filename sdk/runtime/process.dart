import 'dart:convert';
import 'dart:ffi';

import '../../lib/runtime/contracts.dart';

/// Invokes main with OS-owned arguments, excluding the executable name.
@RuntimeEntry(.processMain)
void runMain(int argc, int argv, Function main) {
  final arguments = List<String>.filled(argc > 0 ? argc - 1 : 0, '');
  final pointers = Pointer<Pointer<Uint8>>.fromAddress(argv);
  for (var i = 1; i < argc; i++) {
    final pointer = pointers[i];
    var length = 0;
    while (pointer[length] != 0) {
      length++;
    }
    final decoded = utf8.decode(pointer.asTypedList(length));
    // argv contains text data, so a leading U+FEFF is not a stream signature.
    arguments[i - 1] =
        length >= 3 &&
            pointer[0] == 0xef &&
            pointer[1] == 0xbb &&
            pointer[2] == 0xbf
        ? '\ufeff$decoded'
        : decoded;
  }
  if (main is Function(Never, Never)) {
    (main as Function)(arguments, null);
  } else if (main is Function(Never)) {
    (main as Function)(arguments);
  } else {
    main();
  }
}
