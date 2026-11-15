import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/runtime/contracts.dart';
import 'package:test/test.dart';

void main() {
  for (final issue in ['missing', 'duplicate', 'signature']) {
    test('runtime entry references reject $issue definitions', () async {
      final sources = _EntrySources(await SdkSources.load(), issue);
      await expectLater(
        AnalysisSession(
          const [],
          sdk: DartSdk(sources),
          sources: sources,
          resources: const ['sdk/patches/fixtures/entry_reference.dart'],
        ).use(Lowering().lower),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains(
              issue == 'duplicate'
                  ? 'Repeated runtime entry'
                  : 'Incompatible runtime entry declaration',
            ),
          ),
        ),
      );
    });
  }

  test('runtime bindings are confined to supplied SDK sources', () async {
    final result = await AnalysisSession(
      ['test/frontend/lowering/fixtures/system_native.dart'],
      sources: await SdkSources.load(),
      includeDependencies: true,
    ).use(Lowering().lower);
    final user = result.imports.entries.singleWhere(
      (entry) => entry.value.symbol == 'getpid',
    );
    final clock = result.imports.entries.singleWhere(
      (entry) => entry.value.symbol == 'clock_gettime',
    );
    expect(result.runtime.systemFunctions.containsKey(user.key), isFalse);
    expect(result.runtime.nonAllocating, isNot(contains(user.key)));
    expect(result.runtime.systemFunctions[clock.key], SystemLibrary.c);
    expect(clock.value.isLeaf, isTrue);
    final definition = result.program.functions.singleWhere(
      (body) => body.target.name == 'untrustedDefinition',
    );
    final reference = result.program.externals.singleWhere(
      (body) => body.target.name == 'untrustedReference',
    );
    expect(result.runtime.entries.values, isNot(contains(definition.target)));
    expect(result.runtime.aliases.containsKey(reference.target), isFalse);
    expect(
      result.program.implementationOf(reference.target),
      isA<IrExternal>(),
    );
  });
}

final class _EntrySources(final SdkSources base, final String issue)
    extends SdkSources {
  late final files = <String, Uint8List>{
    'sdk/patches/fixtures/entry_reference.dart': Uint8List.fromList(
      utf8.encode(
        "import '../../../lib/runtime/contracts.dart';\n"
        '@RuntimeEntry(.recordError)\n'
        '${issue == 'signature' ? 'external int reference(int value);' : 'external void reference(Object error, StackTrace trace);'}\n',
      ),
    ),
    if (issue != 'signature')
      'sdk/patches/core.dart': Uint8List.fromList(
        utf8.encode(
          issue == 'missing'
              ? utf8
                    .decode(base.read('sdk/patches/core.dart'))
                    .replaceFirst('@runtime.RuntimeEntry(.recordError)', '')
              : '${utf8.decode(base.read('sdk/patches/core.dart'))}\n@runtime.RuntimeEntry(.recordError)\nvoid _duplicate(Object error, StackTrace trace) {}\n',
        ),
      ),
  };
  @override
  Iterable<String> get paths => {...base.paths, ...files.keys};
  @override
  bool contains(String path) => files.containsKey(path) || base.contains(path);
  @override
  int? length(String path) => files[path]?.length ?? base.length(path);
  @override
  Uint8List read(String path) => files[path] ?? base.read(path);
}
