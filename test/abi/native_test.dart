import 'dart:ffi';
import 'dart:io';

import 'package:dartc/abi.dart';
import 'package:dartc/arm64.dart' as arm64;
import 'package:dartc/artifact.dart' as artifact;
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';
import 'package:dartc/x64.dart' as x64;
import 'package:test/test.dart';

artifact.ObjectFile aliasFunctions<R>(Target target, IntegerAbi<R> abi) {
  final bytes = <int>[], symbols = <artifact.Symbol>[];
  for (final subtract in [false, true]) {
    final left = abi.parameters[0], right = abi.parameters[1];
    if (subtract) {
      abi.subtract(right, left, right);
    } else {
      abi.add(right, left, right);
    }
    abi.returnValue(right);
    final code = abi.takeBytes();
    final name = subtract ? 'alias_subtract' : 'alias_add';
    symbols.add(
      artifact.Symbol(
        target.operatingSystem == .macos ? '_$name' : name,
        bytes.length,
        code.length,
      ),
    );
    bytes.addAll(code);
  }
  return artifact.ObjectFile(target, bytes, symbols);
}

void main() {
  test(
    'ABI arithmetic preserves aliased right operands on the real target',
    () async {
      final target = Target.host();
      final object = switch (target.architecture) {
        .arm64 => aliasFunctions(target, Arm64Abi(arm64.Assembler())),
        .x64 => aliasFunctions(target, X64Abi(x64.Assembler())),
      };
      Directory('build/domain-foundations').createSync(recursive: true);
      final directory = Directory('build/domain-foundations')
          .createTempSync('abi-');
      try {
        final file = File.fromUri(
          directory.uri.resolve(
            'aliases.${target.operatingSystem == .macos ? 'dylib' : 'so'}',
          ),
        );
        await Linker(target).link([object], file, .sharedLibrary);
        final library = DynamicLibrary.open(file.absolute.path);
        try {
          final add = library
              .lookupFunction<
                Int64 Function(Int64, Int64),
                int Function(int, int)
              >('alias_add');
          final subtract = library
              .lookupFunction<
                Int64 Function(Int64, Int64),
                int Function(int, int)
              >('alias_subtract');
          expect(add(40, 2), 42);
          expect(subtract(40, 2), 38);
          expect(subtract(2, 40), -38);
        } finally {
          library.close();
        }
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );
}
