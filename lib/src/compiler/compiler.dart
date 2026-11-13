import 'runtime.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:dartc/sdk.dart';

import 'output.dart';
import 'permissions.dart';

/// Compiles Dart programs and annotated native exports for an explicit target.
///
/// [resources] supplies fixed resources for embedded library use. When omitted,
/// sources are loaded from the dartc package; AOT callers must supply resources.
final class Compiler(final Target target, {final SdkSources? resources}) {
  /// Checks dependencies and returns the final bytes and C declarations.
  ///
  /// All non-SDK dependencies are checked before selecting native definitions.
  /// Analysis resources are closed before code generation. [output] selects
  /// the file kind and, for a shared library, its name. No output files change.
  /// Executables use `main` from the first library's exported namespace;
  /// parameterless synchronous and async entries are supported.
  ///
  /// [nativeSymbols] maps exact asset IDs and requested symbols to native names
  /// before platform symbol decoration.
  /// Missing bindings fail when referenced; no asset resolver fallback occurs.
  /// [linkInputs] supplies implementations for libraries and executables.
  /// Shared-library inputs follow the target loader's symbol lookup rules.
  /// Object and archive outputs retain unresolved imports for a later link.
  Future<Compilation> compile(
    List<String> paths, {
    Output output = const .object(),
    Map<String, Map<String, String>> nativeSymbols = const {},
    Iterable<LinkInput> linkInputs = const [],
  }) async {
    final inputs = linkInputs.toList();
    if (inputs.isNotEmpty &&
        output is! SharedLibraryOutput &&
        output is! ExecutableOutput) {
      throw ArgumentError(
        'Link inputs require shared library or executable output.',
      );
    }
    final sourceFiles = resources ?? await SdkSources.load();
    final (
      lowered,
      sources,
      runtime,
    ) = await AnalysisSession(
      paths,
      includeDependencies: true,
      sdk: DartSdk(sourceFiles),
      sources: sourceFiles,
      resources: const [
        'sdk/runtime/allocator.dart',
        'sdk/runtime/dispatch.dart',
        'sdk/runtime/numbers.dart',
        'sdk/runtime/console.dart',
        'sdk/runtime/stack_trace.dart',
      ],
    ).use((input) async {
      final lowered = await Lowering().lower(input);
      return (
        lowered,
        [
          for (final library in input.libraries)
            if (!input.resources.containsValue(library))
              for (final unit in library.units) File(unit.path).absolute.uri,
        ],
        bindRuntime(lowered),
      );
    });
    final (program: _, :exports, :imports, :entryPoint, runtime: _) = lowered;
    final program = runtime.program;
    if (output is ExecutableOutput && entryPoint == null) {
      throw ArgumentError('The first input library has no main function.');
    }
    final CodeGenerator generator = switch (target.architecture) {
      .arm64 => Arm64CodeGenerator(target),
      .x64 => X64CodeGenerator(target),
    };
    final definitions = program.reachableFrom(
      [...exports.keys, if (output is ExecutableOutput) entryPoint!],
      instantiatedTypes: [
        if (exports.values.any(
              (export) => export.signature.parameters.any(
                (type) => type is NativePointerType,
              ),
            ) ||
            imports.values.any(
              (import) => switch (import.type) {
                NativeFunctionType(
                  signature: NativeSignature(result: NativePointerType()),
                ) =>
                  true,
                _ => false,
              },
            ))
          FfiTypes.pointer,
      ],
    );
    final nativeImports = <FunctionTarget, NativeImport>{};
    final addresses = <NativeReference, String>{};
    String resolve(NativeReference reference) =>
        nativeSymbols[reference.assetId]?[reference.symbol] ??
        (throw ArgumentError(
          'Unbound native symbol ${reference.symbol} in asset ${reference.assetId}',
        ));
    for (final target in definitions) {
      final function = program.implementationOf(target);
      if (function is IrFunction) {
        for (final block in function.blocks) {
          for (final operation in block.instructions) {
            if (operation case NativeSymbolAddress(:final reference)) {
              addresses[reference] = resolve(reference);
            }
          }
        }
        continue;
      }
      if (runtime.primitives.containsKey(target)) continue;
      final reference = imports[target];
      if (reference?.type case NativeFunctionType(:final signature)
          when function is IrExternal) {
        nativeImports[target] = NativeImport(
          resolve(reference!),
          signature,
          isLeaf: reference.isLeaf,
        );
        continue;
      }
      throw UnsupportedError(
        'Native body unavailable: ${target.library}::'
        '${target.owner == null ? '' : '${target.owner!.name}.'}${target.name}',
      );
    }
    const entrySymbol = '.dartc.start';
    final object = generator.generate(
      program,
      definitions: definitions,
      exports: exports,
      imports: nativeImports,
      nativeSymbols: addresses,
      entryPoint: output is ExecutableOutput
          ? (function: entryPoint!, symbol: entrySymbol)
          : null,
      runtime: runtime,
    );
    final ObjectFormat format = switch (target.operatingSystem) {
      .macos => MachO(target),
      .linux => Elf(target),
    };
    final bytes = switch (output) {
      ObjectOutput() => format.encodeObject(object),
      StaticLibraryOutput() => ArchiveWriter(format).encode([object]),
      ExecutableOutput() => switch (target.operatingSystem) {
        .macos => MachOLinker(target),
        .linux => ElfLinker(target),
      }.linkExecutable([.object(object), ...inputs], entry: entrySymbol),
      SharedLibraryOutput(:final name) => switch (target.operatingSystem) {
        .macos => MachOLinker(target),
        .linux => ElfLinker(target),
      }.linkSharedLibrary([.object(object), ...inputs], name: name),
    };
    final header = StringBuffer();
    NativeExports(exports.values).writeHeader(header);
    return Compilation._(
      bytes,
      header.toString(),
      sources,
      output is ExecutableOutput,
    );
  }
}

/// A completed native file and C header, independent of analysis resources.
final class Compilation._(
  Uint8List bytes,

  /// C and C++ declarations for the native exports.
  final String header,
  Iterable<Uri> sources,
  final bool _executable,
) {
  /// Immutable final bytes, including any required linking and signing.
  final Uint8List bytes = bytes.asUnmodifiableView();

  final List<Uri> _sources = .unmodifiable(sources);

  /// Writes the completed file and, optionally, its C header.
  ///
  /// Writing to a new path does not change a shared library's compiled name.
  /// Input files and colliding destinations are protected. Each file is replaced
  /// after staging; the two-file update is not transactional if a filesystem
  /// error occurs between renames.
  /// Executables gain execute permission wherever their staged file is readable.
  Future<void> write(File output, {File? header}) async {
    final destinations = [output, ?header];
    final protected = {
      for (final source in _sources)
        if (source.scheme == 'file') _identity(File.fromUri(source)),
    };
    final names = <String>{};
    for (final file in destinations) {
      final name = _identity(file);
      final aliasesSource =
          file.existsSync() &&
          _sources.any(
            (source) =>
                source.scheme == 'file' &&
                FileSystemEntity.identicalSync(file.path, source.toFilePath()),
          );
      if (protected.contains(name) || aliasesSource || !names.add(name)) {
        throw ArgumentError(
          'Output would overwrite an input or another output: ${file.path}',
        );
      }
    }
    await _write(output, bytes, executable: _executable);
    if (header != null) await _write(header, utf8.encode(this.header));
  }

  String _identity(File file) {
    if (file.existsSync()) return file.resolveSymbolicLinksSync();
    final uri = file.absolute.uri.normalizePath();
    var parent = File.fromUri(uri).parent;
    final parts = [uri.pathSegments.last];
    while (!parent.existsSync()) {
      parts.insert(0, parent.uri.pathSegments.where((s) => s.isNotEmpty).last);
      parent = parent.parent;
    }
    return Directory(parent.resolveSymbolicLinksSync()).uri
        .resolveUri(Uri(pathSegments: parts))
        .toFilePath();
  }

  Future<void> _write(
    File file,
    List<int> bytes, {
    bool executable = false,
  }) async {
    await file.absolute.parent.create(recursive: true);
    final work = await file.absolute.parent.createTemp('.dartc-write-');
    try {
      final staged = File.fromUri(work.uri.resolve('output'));
      await staged.writeAsBytes(bytes);
      if (executable) makeExecutable(staged);
      await staged.rename(file.absolute.path);
    } finally {
      await work.delete(recursive: true);
    }
  }
}
