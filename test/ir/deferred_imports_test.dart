import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final unit = Uri.parse('memory:entry'), library = Uri.parse('memory:library');
  final reference = DeferredImport(unit, 'p', library);
  test('deferred identity, effects and verified references are explicit', () {
    expect(reference, DeferredImport(unit, 'p', library));
    expect(reference, isNot(DeferredImport(unit, 'q', library)));
    expect(() => DeferredImport(unit, '', library), throwsArgumentError);
    expect(
      () => DeferredImport(unit, 'p', Uri.parse('relative.dart')),
      throwsArgumentError,
    );
    final load = LoadLibrary(reference), check = CheckLibraryLoaded(reference);
    expect(load.effects, containsAll([Effect.allocates, Effect.writesStorage]));
    expect(check.effects, {Effect.readsStorage, Effect.mayThrow});
    final block = Block([])..emit(check);
    block.finish(Return(block.emit(load)));
    final target = FunctionTarget(unit, 'load', load.type, []);
    final body = IrFunction(target, [block]);
    expect(body.deferredImports, {reference});
    expect(() => body.deferredImports.clear(), throwsUnsupportedError);
    final output = StringBuffer();
    body.writeTo(output);
    expect(
      output.toString(),
      contains('checkLibraryLoaded memory:entry::p -> memory:library'),
    );
    expect(
      output.toString(),
      contains('loadLibrary memory:entry::p -> memory:library'),
    );
  });

  test('one prefix cannot name two deferred libraries in a program', () {
    IrFunction body(String name, DeferredImport reference) {
      final block = Block([])..emit(CheckLibraryLoaded(reference));
      block.finish(const Return());
      return IrFunction(FunctionTarget(unit, name, .voidType, []), [block]);
    }

    expect(
      () => IrProgram([], [
        body('a', reference),
        body('b', DeferredImport(unit, 'p', Uri.parse('memory:other'))),
      ]),
      throwsArgumentError,
    );
    expect(
      IrProgram([], [body('a', reference), body('b', reference)]).functions,
      hasLength(2),
    );
  });
}
