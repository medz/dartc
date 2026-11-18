import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  test('default preparation can consume its rewritten runtime program', () {
    final root = FunctionTarget(null, 'root', .integer, []);
    final program = IrProgram([], [
      IrFunction(root, [Block()..finish(const Return(Constant.integer(42)))]),
    ]);
    final compiler = Compiler(const Target(.linux, .arm64));
    final first = compiler.prepare(
      program,
      roots: [root],
      runtime: heapRuntime,
    );
    final second = compiler.prepare(
      first.program,
      roots: [root],
      runtime: heapRuntime,
    );
    expect(second.definitions, {root});
    for (final prepared in [first, second]) {
      expect(prepared.runtime!.program, same(prepared.program));
      expect(prepared.runtime!.types!.program, same(prepared.program));
      expect(
        IrInterpreter(
          prepared.program,
          {},
        ).run(prepared.program.implementationOf(root) as IrFunction, []),
        42,
      );
    }
  });

  test('current runtime body is authoritative after source rewriting', () {
    final root = FunctionTarget(null, 'root', .integer, []);
    final compiler = Compiler(const Target(.linux, .arm64));
    final first = compiler.prepare(
      IrProgram([], [
        IrFunction(root, [Block()..finish(const Return(Constant.integer(42)))]),
      ]),
      roots: [root],
      runtime: heapRuntime,
    );
    final query = heapRuntime.context!;
    final read = FunctionTarget(null, 'readCurrentContext', .integer, []);
    final call = Block();
    call.finish(Return(call.emit(DirectCall(query, []))));
    final current = IrProgram(
      first.program.classes,
      [
        for (final body in first.program.functions)
          if (body.target != query) body,
        IrFunction(query, [
          Block()..finish(const Return(Constant.integer(73))),
        ]),
        IrFunction(read, [call]),
      ],
      globals: first.program.globals,
      externals: first.program.externals,
    );
    final second = compiler.prepare(
      current,
      roots: [read],
      runtime: heapRuntime,
    );
    expect(
      IrInterpreter(
        second.program,
        {},
      ).run(second.program.implementationOf(read) as IrFunction, []),
      73,
    );
    expect(second.runtime!.program, same(second.program));
  });

  test('repreparation retains the lowered module and shared entry writes', () {
    final shared = GlobalVariable(
      Uri.parse('memory:runtime-reprepare'),
      'shared',
      .integer.nullable,
    );
    final write = FunctionTarget(null, 'write', .voidType, [.integer]);
    final store = Block(write.parameterTypes);
    store.emit(StoreGlobal(shared, store.parameters.single));
    store.finish(const Return());
    final read = FunctionTarget(null, 'read', .integer.nullable, []);
    final load = Block();
    load.finish(Return(load.emit(LoadGlobal(shared))));
    final source = IrProgram(
      heapRuntime.program.classes,
      [
        ...heapRuntime.program.functions,
        IrFunction(write, [store]),
        IrFunction(read, [load]),
      ],
      globals: [...heapRuntime.program.globals, shared],
      externals: heapRuntime.program.externals,
    );
    final binding = heapRuntime.rebind(source);
    final compiler = Compiler(const Target(.linux, .arm64));
    final first = compiler.prepare(
      source,
      roots: [write, read],
      runtime: binding,
    );
    final second = compiler.prepare(
      first.program,
      roots: [write, read],
      runtime: binding,
    );
    final holders = first.program.functions
        .expand((f) => f.moduleObjects)
        .toSet();
    expect(holders, isNotEmpty);
    expect(
      second.program.functions.expand((f) => f.moduleObjects).toSet(),
      holders,
    );
    for (final prepared in [first, second]) {
      expect(prepared.program.globals, isNot(contains(shared)));
      final runner = IrInterpreter(prepared.program, {});
      final reader = prepared.program.implementationOf(read) as IrFunction;
      final writer = prepared.program.implementationOf(write) as IrFunction;
      expect(runner.run(reader, []), isNull);
      runner.run(writer, [37]);
      expect(runner.run(reader, []), 37);
      runner.run(writer, [-8]);
      expect(runner.run(reader, []), -8);
    }
  });

  test('repreparation retains shared reference storage without resurrecting globals', () {
    final shared = GlobalVariable(
      Uri.parse('memory:runtime-reprepare'),
      'shared',
      .string.nullable,
    );
    final write = FunctionTarget(null, 'write', .voidType, [.string]);
    final store = Block(write.parameterTypes);
    store.emit(StoreGlobal(shared, store.parameters.single));
    store.finish(const Return());
    final read = FunctionTarget(null, 'read', .string.nullable, []);
    final load = Block();
    load.finish(Return(load.emit(LoadGlobal(shared))));
    final source = IrProgram(
      heapRuntime.program.classes,
      [
        ...heapRuntime.program.functions,
        IrFunction(write, [store]),
        IrFunction(read, [load]),
      ],
      globals: [...heapRuntime.program.globals, shared],
      externals: heapRuntime.program.externals,
    );
    final binding = heapRuntime.rebind(source);
    final compiler = Compiler(const Target(.linux, .arm64));
    final first = compiler.prepare(
      source,
      roots: [write, read],
      runtime: binding,
    );
    final second = compiler.prepare(
      first.program,
      roots: [write, read],
      runtime: binding,
    );
    final holders = first.program.functions
        .expand((f) => f.moduleObjects)
        .toSet();
    expect(holders, isNotEmpty);
    expect(
      second.program.functions.expand((f) => f.moduleObjects).toSet(),
      holders,
    );
    for (final prepared in [first, second]) {
      expect(prepared.program.globals, isNot(contains(shared)));
      final runner = IrInterpreter(prepared.program, {});
      final reader = prepared.program.implementationOf(read) as IrFunction;
      final writer = prepared.program.implementationOf(write) as IrFunction;
      expect(runner.run(reader, []), isNull);
      runner.run(writer, ['first']);
      expect(runner.run(reader, []), 'first');
      runner.run(writer, ['second']);
      expect(runner.run(reader, []), 'second');
    }
  });

  test(
    'partial graph composition still rejects conflicting runtime bodies',
    () {
      final query = heapRuntime.context!;
      final source = IrProgram([], [
        IrFunction(query, [
          Block()..finish(const Return(Constant.integer(73))),
        ]),
      ]);
      expect(
        () =>
            Compiler(const Target(.linux, .arm64))
                .prepare(source, roots: [query], runtime: heapRuntime),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('Conflicting runtime definition'),
          ),
        ),
      );
    },
  );

  test(
    'explicit rebinding rejects missing required bodies and machine leaves',
    () {
      final source = heapRuntime.program;
      final missingBody = IrProgram(
        source.classes,
        source.functions.where((body) => body.target != heapRuntime.allocate),
        globals: source.globals,
        externals: source.externals,
      );
      final primitive = heapRuntime.primitives.keys.first;
      final missingPrimitive = IrProgram(
        source.classes,
        source.functions,
        globals: source.globals,
        externals: source.externals.where((body) => body.target != primitive),
      );
      expect(() => heapRuntime.rebind(missingBody), throwsArgumentError);
      expect(() => heapRuntime.rebind(missingPrimitive), throwsArgumentError);
    },
  );

  test(
    'type owners reject a new constructor identity after helpers are cached',
    () {
      final source = heapRuntime.program;
      final old = source.classes.singleWhere(
        (c) => c.type == TypeMetadata.list,
      );
      final original = old.constructors['new']!;
      final originalBody = source.implementationOf(original) as IrFunction;
      final replacement = FunctionTarget(
        original.library,
        original.name,
        original.returnType,
        original.signature.parameters,
        owner: original.owner,
        kind: original.kind,
      );
      final rewritten = <IrFunction>[];
      for (final body in source.functions) {
        if (body.target == original) {
          rewritten.add(
            IrFunction(
              replacement,
              originalBody.blocks,
              defaults: originalBody.defaults,
              typeBindings: originalBody.typeBindings,
            ),
          );
          continue;
        }
        final operations = <Instruction, Instruction>{};
        for (final block in body.blocks) {
          for (final op in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ]) {
            if (op
                case Construct(
                  :final initializer,
                  :final arguments,
                  :final instantiatedType,
                )
                when initializer == original) {
              operations[op] = Construct(
                replacement,
                arguments,
                instantiatedType: instantiatedType,
              );
            }
          }
        }
        rewritten.add(FunctionRewrite(body, operations: operations).run());
      }
      final changed = IrProgram(
        [
          for (final declaration in source.classes)
            if (declaration != old) declaration,
          IrClass(
            old.type,
            old.fields,
            members: old.members.values,
            constructors: [replacement],
          ),
        ],
        rewritten,
        globals: source.globals,
        externals: source.externals,
      );
      final owner = TypeImplementations(runtime: heapRuntime.types);
      final parameter = TypeParameterType('Element')
        ..initializeBound(.object.nullable);
      final template = owner.values.instantiate(CoreTypes.listOf(parameter));
      expect(
        owner.values.functions
            .singleWhere((body) => body.target == template.target)
            .callees,
        contains(original),
      );
      expect(
        () => owner.rebind(heapRuntime.types!.rebind(changed)),
        throwsArgumentError,
      );
    },
  );
}
