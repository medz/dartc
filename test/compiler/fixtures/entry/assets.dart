import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm64;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import '../../../linker/fixtures/addresses.dart';

const entrySymbols = {
  'entry': {
    'constant': 'address_constant',
    'state': 'address_state',
    'zero': 'address_zero',
    'finish': 'finish',
  },
};

List<LinkInput> entryInputs(Target target) {
  final inputs = addressModules(target).map(LinkInput.object).toList();
  if (target.operatingSystem == .macos) {
    inputs.add(
      .sharedLibrary(
        '/usr/lib/libSystem.B.dylib',
        symbols: {'_finish': '__exit'},
      ),
    );
  } else {
    final bytes = target.architecture == .arm64
        ? (arm64.Assembler()
                ..loadImmediate(.x8, 94)
                ..supervisorCall(0))
              .finish()
        : (x64.Assembler()
                ..loadImmediate(.rax, 231)
                ..syscall())
              .finish();
    inputs.add(
      .object(
        ObjectModule(
          target,
          [Section.code(bytes)],
          [Symbol(target.nativeSymbol('finish'), 0, 0, bytes.length)],
        ),
      ),
    );
  }
  return inputs;
}
