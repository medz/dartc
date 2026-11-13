import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

const fixture = 'test/frontend/lowering/fixtures/source_locations.dart';

SourceLocation at(int line, int column, {bool part = false}) => (
  uri: Uri.base.resolve(
    part ? fixture.replaceFirst('.dart', '_part.dart') : fixture,
  ),
  line: line,
  column: column,
);

Iterable<Instruction> operations(IrFunction function) sync* {
  for (final block in function.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  late IrProgram program;
  setUpAll(() async {
    program = await AnalysisSession(
      [fixture],
      sources: await SdkSources.load(),
    ).use((input) async => (await Lowering().lower(input)).program);
  });
  IrFunction function(String name) =>
      program.functions.singleWhere((function) => function.target.name == name);
  List<SourceLocation?> calls(IrFunction function, String target) => [
    for (final operation in operations(function))
      if (operation is DirectCall && operation.target.name == target)
        function.sourceLocations[operation],
  ];

  test('declaration positions retain local, part and SDK source units', () {
    expect(function('callSites').target.declarationLocation, at(8, 1));
    expect(
      function('fromPart').target.declarationLocation,
      at(3, 1, part: true),
    );
    expect(
      program.externals
          .singleWhere((e) => e.target.name == 'leaf')
          .target
          .declarationLocation,
      at(5, 1),
    );
    final local = program.functions.singleWhere(
      (f) => f.target.enclosing?.name == 'nested',
    );
    expect(local.target.declarationLocation, at(16, 12));
    final sqrt = function('sqrt').target.declarationLocation!;
    expect(
      sqrt.uri.path,
      endsWith('/sdk/std/lib/_internal/vm/lib/math_patch.dart'),
    );
    expect((sqrt.line, sqrt.column), (130, 1));
  });

  test(
    'nested arguments and branch returns retain their distinct source sites',
    () {
      final body = function('callSites');
      expect(
        calls(body, 'leaf'),
        unorderedEquals([at(10, 12), at(10, 17), at(12, 10)]),
      );
      expect([
        for (final block in body.blocks)
          if (block.end is Return) body.sourceLocations[block],
      ], unorderedEquals([at(10, 5), at(12, 3)]));
      final guarded = function('guarded');
      expect(calls(guarded, 'leaf'), [at(30, 12)]);
      expect([
        for (final block in guarded.blocks)
          if (block.end is Throw) guarded.sourceLocations[block],
      ], contains(at(32, 5)));
    },
  );

  test(
    'local bodies, suspension, throws and part units preserve real positions',
    () {
      final local = program.functions.singleWhere(
        (function) => function.target.enclosing?.name == 'nested',
      );
      expect(calls(local, 'leaf'), [at(17, 12)]);
      final suspended = function('suspended');
      expect(calls(suspended, 'leaf'), [at(24, 31)]);
      expect(calls(suspended, 'pending'), [at(24, 23)]);
      expect(
        [
          for (final block in suspended.blocks)
            if (block.end is Await) suspended.sourceLocations[block],
        ],
        [at(24, 17)],
      );
      expect(
        [
          for (final block in suspended.blocks)
            if (block.end is Throw) suspended.sourceLocations[block],
        ],
        [at(25, 3)],
      );
      expect(calls(function('fromPart'), 'leaf'), [at(3, 19, part: true)]);
      expect(function('_sqrt').sourceLocations, isEmpty);
      final initializer = program.functions.singleWhere(
        (function) =>
            function.target.owner?.name == 'SourceChild' &&
            function.target.kind == .initializer,
      );
      expect(calls(initializer, 'leaf'), [at(41, 16)]);
      final parent = operations(initializer)
          .whereType<DirectCall>()
          .singleWhere((call) => call.target.owner?.name == 'SourceParent');
      expect(initializer.sourceLocations[parent], at(41, 10));

      final squareRootCall = calls(function('sqrt'), '_sqrt').single!;
      expect((squareRootCall.line, squareRootCall.column), (132, 23));
      expect(
        squareRootCall.uri.path,
        endsWith('/sdk/std/lib/_internal/vm/lib/math_patch.dart'),
      );
    },
  );
}
