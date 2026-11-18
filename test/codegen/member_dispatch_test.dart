import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test(
    'retained typed dispatch covers every receiver without a new failure call',
    () {
      final face = ClassType(null, 'Face', isAbstract: true);
      final left = ClassType(null, 'Left', interfaces: [face]);
      final right = ClassType(null, 'Right', interfaces: [face]);
      FunctionTarget method(ClassType owner, {bool isAbstract = false}) =>
          FunctionTarget(
            null,
            'write',
            .integer,
            [.integer],
            owner: owner,
            kind: .method,
            isAbstract: isAbstract,
          );
      final member = method(face, isAbstract: true),
          one = method(left),
          two = method(right);
      final root = FunctionTarget(null, 'root', .integer, [face, .integer]);
      final entry = Block(root.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            InstanceCall(member, entry.parameters.first, [
              entry.parameters.last,
            ]),
          ),
        ),
      );
      IrFunction implementation(FunctionTarget target, int value) {
        final block = Block(target.parameterTypes);
        block.emit(
          StoreNative(
            block.parameters.last,
            NativeScalarType(Int64),
            Constant.integer(value),
          ),
        );
        block.finish(Return(Constant.integer(value)));
        return IrFunction(target, [block]);
      }

      final source = IrProgram(
        [
          IrClass(face, [], members: [member]),
          IrClass(left, [], members: [one]),
          IrClass(right, [], members: [two]),
        ],
        [
          IrFunction(root, [entry]),
          implementation(one, 42),
          implementation(two, 43),
        ],
      );
      for (final platform in [
        const Target(.linux, .arm64),
        const Target(.linux, .x64),
      ]) {
        final prepared = Compiler(platform).prepare(source, roots: [root]);
        final body = prepared.program.implementationOf(root) as IrFunction;
        expect(
          body.blocks.expand((b) => b.instructions).whereType<InstanceCall>(),
          hasLength(1),
        );
        final binding = body.blocks
            .expand((b) => b.instructions)
            .whereType<InstanceCall>()
            .single
            .entryBinding!;
        expect(binding.entries.keys.toSet(), {one, two});
        expect(
          prepared.definitions,
          containsAll([root, ...binding.entries.values]),
        );
        final generator = platform.architecture == .arm64
            ? Arm64CodeGenerator(platform)
            : X64CodeGenerator(platform);
        expect(generator.generate(prepared).sections, isNotEmpty);
        final allocate = DynamicLibrary.process()
            .lookupFunction<
              Pointer<Int64> Function(Size, Size),
              Pointer<Int64> Function(int, int)
            >('calloc');
        final free = DynamicLibrary.process()
            .lookupFunction<
              Void Function(Pointer<Int64>),
              void Function(Pointer<Int64>)
            >('free');
        final storage = allocate(1, 8);
        if (storage == nullptr) throw StateError('calloc failed');
        try {
          final interpreter = IrInterpreter(prepared.program, {});
          for (final (type, expected) in [(left, 42), (right, 43)]) {
            storage.value = 0;
            final call = Block();
            call.finish(
              Return(
                call.emit(
                  DirectCall(root, [
                    ObjectConstant(type, {}),
                    Constant.integer(storage.address),
                  ]),
                ),
              ),
            );
            final invoke = IrFunction(
              FunctionTarget(null, 'invoke', .integer, []),
              [call],
            );
            expect(interpreter.run(invoke, []), expected);
            expect(storage.value, expected);
          }
        } finally {
          free(storage);
        }
      }
    },
  );
}
