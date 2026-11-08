import 'package:dartc/compiler.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';

import '../test/codegen/fixtures/aliases.dart';
import '../test/linker/fixtures/functions.dart';
import '../test/linker/fixtures/symbols.dart';
import '../test/native_assets.dart';

Future<void> main() async {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final assets = NativeAssets(target);
      await assets.directory.create(recursive: true);
      final arithmetic = await Compiler(target)
          .compile(['test/compiler/fixtures/arithmetic.dart']);
      await arithmetic.write(
        assets.file('compiler/arithmetic.o'),
        header: assets.file('compiler/arithmetic.h'),
      );
      await arithmetic.write(
        assets.file('compiler/arithmetic.a'),
        kind: .staticLibrary,
      );
      await arithmetic.write(
        assets.library('compiler/arithmetic'),
        kind: .sharedLibrary,
      );

      final linker = Linker(target);
      await linker.link(
        [aliases(target)],
        assets.library('codegen/aliases'),
        .sharedLibrary,
      );
      final inputs = [
        functions(target, {'first': 40}),
        functions(target, {'second': 2}),
      ];
      await linker.link(inputs, assets.file('linker/values.a'), .staticLibrary);
      await linker.link(
        inputs,
        assets.library('linker/values'),
        .sharedLibrary,
      );
      for (final (i, object) in inputs.indexed) {
        await assets.file('linker/$i.o').writeAsBytes(switch (os) {
          .macos => MachO.encode(object),
          .linux => Elf.encode(object),
        });
      }
      await linker.link(
        [functions(target, symbolValues)],
        assets.library('linker/symbols'),
        .sharedLibrary,
      );
      print('Built test assets for $target.');
    }
  }
}
