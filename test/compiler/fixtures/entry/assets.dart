import 'package:dartc/abi.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';

import '../../../linker/fixtures/addresses.dart';

const entrySymbols = {
  'entry': {
    'constant': 'address_constant',
    'state': 'address_state',
    'zero': 'address_zero',
    'finish': 'finish',
    'table': 'dartc_address_table',
  },
};

List<LinkInput> entryInputs(Target target) => [
  ...addressModules(target).map(LinkInput.object),
  .sharedLibrary(
    target.operatingSystem == .macos
        ? '/usr/lib/libSystem.B.dylib'
        : 'libc.so.6',
    symbols: {target.nativeSymbol('finish'): target.nativeSymbol('_exit')},
  ),
];
