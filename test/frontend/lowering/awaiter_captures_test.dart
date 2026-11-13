import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  late IrProgram program;
  setUpAll(() async {
    program = await AnalysisSession(
      ['test/frontend/lowering/fixtures/awaiter_captures.dart'],
      sources: await SdkSources.load(),
    ).use((input) async => (await Lowering().lower(input)).program);
  });

  Iterable<FunctionTarget> children(String parent) => program.functions
      .map((function) => function.target)
      .where((target) => target.enclosing?.name == parent);

  test(
    'local and parameter pragmas identify their capture without reordering',
    () {
      for (final parent in ['local', 'parameter', 'multiple']) {
        final target = children(parent).single;
        expect(target.captures, [
          ValueType.string,
          ValueType.object,
        ], reason: parent);
        expect(target.awaiterCapture, 1, reason: parent);
      }
    },
  );

  test('links cross nested closures and retain mutable cell storage', () {
    final outer = children('nested').single;
    final inner = program.functions
        .singleWhere((function) => function.target.enclosing == outer)
        .target;
    for (final target in [outer, inner]) {
      expect(target.awaiterCapture, 0);
      expect(target.captures, [ValueType.object]);
    }
    for (final parent in ['boxed', 'boxedParameter']) {
      final target = children(parent).single;
      expect(target.awaiterCapture, 0);
      expect(target.captures, [CellType(ValueType.object)]);
    }
    final initializer = children('lazyCapture')
        .singleWhere((target) => target.name.startsWith('<initialize:'));
    expect(initializer.awaiterCapture, 0);
    expect(initializer.captures, [ValueType.object]);
    final reader = children('lazyCapture')
        .singleWhere((target) => target != initializer);
    expect(reader.awaiterCapture, isNull);
  });

  test(
    'only a captured variable with the genuine core pragma supplies a link',
    () {
      for (final parent in ['unused', 'unmarked', 'unrelated', 'impostor']) {
        expect(children(parent).single.awaiterCapture, isNull, reason: parent);
      }
    },
  );

  test(
    'official Future wait callbacks retain local and parameter awaiter links',
    () {
      final futureCallbacks = children('wait')
          .where((target) => target.enclosing!.owner?.name == 'Future')
          .toList();
      expect(futureCallbacks, isNotEmpty);
      for (final target in futureCallbacks) {
        final slot = target.awaiterCapture;
        expect(slot, isNotNull, reason: target.name);
        expect((target.captures[slot!] as ClassType).name, '_Future');
        expect(target.library, Uri.parse('dart:async'));
      }
      for (final name in ['_wait', '_waitAll']) {
        final callbacks = children(name)
            .where((target) => target.enclosing!.owner?.name == '_FutureResult')
            .toList();
        expect(callbacks, isNotEmpty, reason: name);
        for (final target in callbacks) {
          final slot = target.awaiterCapture;
          expect(slot, isNotNull, reason: name);
          expect(target.captures[slot!], FunctionType(.voidType, [.integer]));
        }
      }
    },
  );
}
