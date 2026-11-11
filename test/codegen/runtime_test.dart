import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  final uri = Uri.parse('memory:runtime-contract');
  final entry = FunctionTarget(uri, 'entry', .integer, []);

  HeapRuntime withCritical(FunctionTarget function) => HeapRuntime(
    heapRuntime.program,
    allocate: heapRuntime.allocate,
    release: heapRuntime.release,
    primitives: heapRuntime.primitives,
    nonAllocating: [...heapRuntime.nonAllocating, function],
  );

  IrFunction mainBody(bool managed) {
    final block = Block();
    block.finish(
      Return(
        managed
            ? block.emit(
                CollectionLength(
                  block.emit(NewCollection(CoreTypes.listOf(.integer))),
                ),
              )
            : const Constant.integer(42),
      ),
    );
    return IrFunction(entry, [block]);
  }

  test('runtime entries must implement their machine boundary signatures', () {
    expect(
      () => HeapRuntime(
        heapRuntime.program,
        allocate: heapRuntime.release,
        release: heapRuntime.release,
        primitives: heapRuntime.primitives,
        nonAllocating: [],
      ),
      throwsArgumentError,
    );
    expect(
      () => HeapRuntime(
        heapRuntime.program,
        allocate: heapRuntime.allocate,
        release: heapRuntime.release,
        primitives: {
          heapRuntime.primitives.entries
                  .singleWhere((entry) => entry.value == .map)
                  .key:
              .fail,
        },
        nonAllocating: [],
      ),
      throwsArgumentError,
    );
  });

  for (final CodeGenerator generator in [
    Arm64CodeGenerator(const Target(.linux, .arm64)),
    X64CodeGenerator(const Target(.linux, .x64)),
  ]) {
    test('${generator.target} trims runtime from unmanaged programs', () {
      for (final managed in [false, true]) {
        final program = IrProgram([], [mainBody(managed)]);
        final module = generator.generate(
          program,
          definitions: [entry],
          runtime: heapRuntime,
        );
        for (final target in [heapRuntime.allocate, heapRuntime.release]) {
          expect(module.symbols.any((s) => s.name == target.name), managed);
        }
        if (managed) {
          expect(
            () => generator.generate(program, definitions: [entry]),
            throwsArgumentError,
          );
        }
      }
    });

    test(
      '${generator.target} rejects transitive allocation and exceptions',
      () {
        for (final allocates in [true, false]) {
          final leaf = FunctionTarget(uri, 'leaf', .integer, [.integer]);
          final caller = FunctionTarget(uri, 'critical', .integer, [.integer]);
          final call = Block(caller.parameterTypes);
          call.finish(Return(call.emit(DirectCall(leaf, call.parameters))));
          final body = Block(leaf.parameterTypes);
          if (allocates) {
            final boxed = body.emit(TypeView(body.parameters.single, .object));
            body.finish(Return(body.emit(ObjectHashCode(boxed, direct: true))));
          } else {
            body.finish(Throw(Constant.string('failure')));
          }
          expect(
            () => generator.generate(
              IrProgram([], [
                mainBody(true),
                IrFunction(caller, [call]),
                IrFunction(leaf, [body]),
              ]),
              definitions: [entry, caller, leaf],
              runtime: withCritical(caller),
            ),
            throwsA(
              isA<UnsupportedError>().having(
                (e) => e.message,
                'contract',
                contains('must not allocate'),
              ),
            ),
          );
        }
      },
    );

    test('${generator.target} rejects native calls inside collection', () {
      final foreign = FunctionTarget(uri, 'foreign', .integer, []);
      final critical = FunctionTarget(uri, 'critical', .integer, []);
      final block = Block();
      block.finish(Return(block.emit(DirectCall(foreign, []))));
      expect(
        () => generator.generate(
          IrProgram(
            [],
            [
              mainBody(true),
              IrFunction(critical, [block]),
            ],
            externals: [IrExternal(foreign)],
          ),
          definitions: [entry, critical, foreign],
          imports: {
            foreign: NativeImport(
              'foreign',
              NativeSignature(Int64, []),
              isLeaf: true,
            ),
          },
          runtime: withCritical(critical),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'contract',
            contains('foreign'),
          ),
        ),
      );
    });
  }
}
