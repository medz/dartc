import 'package:dartc/abi.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import 'calls.dart';
import 'functions.dart';

List<ObjectModule> archiveModules(Target target) {
  final [root, helper] = callModules(target);
  final wrapper = helper.symbols.first, leaf = helper.symbols.last;
  final cycle = ObjectModule(
    target,
    helper.sections,
    [
      Symbol(
        target.nativeSymbol('archive_callback'),
        0,
        wrapper.offset,
        wrapper.size,
        exported: true,
      ),
      Symbol(target.nativeSymbol('leaf'), 0, leaf.offset, leaf.size),
    ],
    imports: [target.nativeSymbol('helper')],
    relocations: [
      for (final r in helper.relocations)
        Relocation(r.section, r.offset, r.encoding, 2),
    ],
  );
  final intermediate = ObjectModule(
    target,
    root.sections,
    [
      Symbol(target.nativeSymbol('helper'), 0, wrapper.offset, wrapper.size),
      root.symbols.last,
    ],
    imports: [target.nativeSymbol('leaf')],
    relocations: root.relocations,
  );
  final unused = functions(target, {'helper': 99, 'unused': 999});
  return [
    root,
    cycle,
    intermediate,
    ObjectModule(target, unused.sections, unused.symbols, imports: ['absent']),
  ];
}
