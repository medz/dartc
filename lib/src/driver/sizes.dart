import 'package:dartc/emit.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/optimize.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';

import 'compile.dart';

/// One step of why a function is part of a program: `name` is there because
/// of `how`, which happened in the next step if there is one. `createdBy`
/// created the first objects that a call reached it on.
typedef WhyStep = ({String name, String how, String? createdBy});

/// The bytes of one function of a program.
final class FunctionSize(
  /// Its symbol.
  final String name,
  final int bytes, {

  /// What declares it, or null if the compiler made it.
  final Uri? library,

  /// The class, mixin or extension that declares it, if there is one.
  final String? owner,

  /// Why it is part of the program, from it to where the program starts.
  /// Functions that lowering makes have none.
  final List<WhyStep> why = const [],
});

/// What the bytes of a program are made of.
final class ProgramSizes(
  /// The bytes of the whole file.
  final int fileBytes,

  /// The bytes of each part of the file, by what the part is.
  final Map<String, int> parts,

  /// Each function, largest first.
  final List<FunctionSize> functions,
);

/// What the bytes of the program at [path], which uses [sdk], are made of.
///
/// Throws [CompileFailure] if the program has an error or is not supported
/// yet.
Future<ProgramSizes> measureSizes(
  String path,
  SdkSources sdk,
  CompileOptions options,
) async {
  final reasons = Reasons();
  final module = optimizeProgram(
    translateProgram(
      await loadProgram(path, sdk: sdk),
      target: options.target,
      checksAssertions: options.checksAssertions,
      reasons: reasons,
    ),
    enabled: options.optimizations,
  );
  final code = emitCode(
    lowerProgram(
      module,
      system: options.target.system,
      collectsAlways: options.collectsAlways,
    ),
    target: options.target,
    entry: entrySymbol,
  );
  final file = linkProgram(code, path, options);
  final parts = _partsOf(code);
  final rest = parts.values.fold(0, (sum, bytes) => sum + bytes);
  parts['headers, padding and tables of the loader'] = file.length - rest;
  return ProgramSizes(file.length, parts, _functionsOf(code, module, reasons));
}

/// The bytes of what [code] has, apart from what linking adds.
Map<String, int> _partsOf(EmittedCode code) {
  final parts = <String, int>{'code': code.text.length};
  void add(String part, int bytes) => parts[part] = (parts[part] ?? 0) + bytes;
  for (final MapEntry(key: name, value: bytes) in code.data.entries) {
    final part =
        emittedData[name] ??
        switch (name) {
          classTableSymbol => 'class table',
          _ when name.startsWith(typeTestsPrefix) => 'tests of types',
          _ => 'other constants',
        };
    add(part, bytes.length);
  }
  for (final MapEntry(key: name, value: entries) in code.tables.entries) {
    add(
      name == dispatchSymbol ? 'dispatch table' : 'other tables',
      4 * entries.length,
    );
  }
  for (final object in code.objects.values) {
    add(
      object.writable ? 'writable objects' : 'constant objects',
      object.bytes.length,
    );
  }
  return parts;
}

List<FunctionSize> _functionsOf(
  EmittedCode code,
  HirModule module,
  Reasons reasons,
) {
  final symbols = functionSymbols(module);
  final functions = {
    for (final MapEntry(:key, :value) in symbols.entries) value: key,
  };
  String nameOf(HirFunction function) =>
      symbols[function] ?? '${function.name} (left out by optimizing)';
  FunctionSize sizeOf(String name, int bytes) {
    final function = functions[name];
    if (function == null) return FunctionSize(name, bytes);
    return FunctionSize(
      name,
      bytes,
      library: reasons.libraryOf(function),
      owner: reasons.classOf(function),
      why: [
        for (final (found, reason) in reasons.chainTo(function))
          (
            name: nameOf(found),
            how: reason.how,
            createdBy: switch (reason.createdBy) {
              final creator? => nameOf(creator),
              null => null,
            },
          ),
      ],
    );
  }

  final starts = [
    for (final name in code.functionNames) (name, code.functions[name]!),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  final ends = [
    for (final (_, start) in starts.skip(1)) start,
    code.text.length,
  ];
  return [
    for (final (i, (name, start)) in starts.indexed)
      sizeOf(name, ends[i] - start),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));
}
