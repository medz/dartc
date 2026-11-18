import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';

/// Makes native conversion, storage lifetimes and root publication ordinary IR.
///
/// With [managedContext], a nonleaf call publishes its source caller's frame from a raw-only bridge.
/// Every managed owner and compound result stays in that caller until return.
/// The bridge cannot be inlined because it observes its preserved caller frame.
final class NativeCallLowering({
  /// Storage owned by this module's lifecycle, independent of native ABI binding.
  final NativeData? managedContext,

  /// The actual terminal failure entry for an unlinked managed activation.
  final FunctionTarget? failure,
}) extends ProgramPass {
  final _bridges = <NativeSignature, IrFunction>{};

  this {
    if (managedContext case final context?) {
      _checkContext(context);
      if (failure == null) {
        throw ArgumentError('Managed publication requires its failure entry.');
      }
      _checkFailure(failure!);
    }
  }

  static void _checkContext(NativeData context) {
    if (!context.writable ||
        context.alignment < 8 ||
        context.bytes.length < RuntimeContext.size) {
      throw ArgumentError(
        'Publication requires writable runtime context storage.',
      );
    }
  }

  static void _checkFailure(FunctionTarget failure) {
    if (failure.kind != .function ||
        failure.typeParameters.isNotEmpty ||
        failure.signature != FunctionType(.never, [])) {
      throw ArgumentError('Publication failure must be a closed Never entry.');
    }
  }

  @override
  ProgramPassKind get kind => .lowering;

  @override
  IrProgram run(ProgramFlowFacts facts) {
    facts.checkProgram(facts.program);
    return lower(facts.program, definitions: facts.definitions);
  }

  /// Lowers supplied bodies without specializing or hiding their native effects.
  IrProgram lower(IrProgram program, {Iterable<FunctionTarget>? definitions}) {
    final selected = definitions?.toSet();
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      if (selected != null && !selected.contains(function.target)) {
        functions.add(function);
        continue;
      }
      final lowered =
          <
            Instruction,
            ({
              IrFunction body,
              List<Value> arguments,
              Map<TypeParameterType, ValueType> environment,
              Jump? handler,
            })
          >{};
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (operation is! NativeCall) continue;
          lowered[operation] = (
            body: _conversion(operation),
            arguments: operation.inputs.toList(),
            environment: const {},
            handler: switch (block.end) {
              Invoke(operation: final called, :final onThrow)
                  when identical(called, operation) =>
                onThrow,
              _ => null,
            },
          );
        }
      }
      final rewritten = lowered.isEmpty
          ? function
          : FunctionRewrite(function, executionShapes: program.executionShapes, lowered: lowered).run();
      changed |= !identical(rewritten, function);
      functions.add(rewritten);
    }
    if (!changed) return program;
    final present = functions.map((function) => function.target).toSet();
    return IrProgram(
      program.classes,
      [
        ...functions,
        for (final bridge in _bridges.values)
          if (!present.contains(bridge.target)) bridge,
      ],
      globals: program.globals,
      nativeBoundaries: program.nativeBoundaries,
      executionShapes: program.executionShapes,
      externals: program.externals,
    );
  }

  /// Gives an actual raw import an ordinary frame-publication body.
  ///
  /// Both declarations have the same scalar/address signature. [native] is the
  /// terminal foreign symbol; [entry] retains the original Dart call identity.
  static IrFunction importBridge(
    FunctionTarget entry,
    FunctionTarget native, {
    required NativeData managedContext,
    required FunctionTarget failure,
  }) {
    _checkContext(managedContext);
    _checkFailure(failure);
    if (entry.signature != native.signature ||
        entry.parameterTypes.any(
          (type) => type != .integer && type != .floating && type != .boolean,
        )) {
      throw ArgumentError('Native publication bridges require raw carriers.');
    }
    final entryBlock = Block(entry.parameterTypes);
    final (block, blocks) = _publish(entryBlock, managedContext, failure);
    final call = block.emit(DirectCall(native, entryBlock.parameters));
    block.finish(
      entry.returnType == .never
          ? Unreachable(call)
          : Return(entry.returnType == .voidType ? null : call),
    );
    return IrFunction(entry, blocks);
  }

  static (Block, List<Block>) _publish(
    Block entry,
    NativeData managedContext,
    FunctionTarget failure,
  ) {
    final block = Block(), failed = Block();
    final word = NativeScalarType(Int64);
    Value offset(Value base, int offset) =>
        block.emit(IntBinary(.add, base, Constant.integer(offset)));
    final context = entry.emit(NativeDataAddress(managedContext));
    final record = entry.emit(
      LoadNative(
        entry.emit(
          IntBinary(.add, context, Constant.integer(RuntimeContext.active)),
        ),
        word,
      ),
    );
    entry.finish(
      Branch(
        entry.emit(Equals(record, const Constant.integer(0))),
        Jump(failed),
        Jump(block),
      ),
    );
    failed.finish(Unreachable(failed.emit(DirectCall(failure, []))));
    block.emit(
      StoreNative(
        offset(record, RuntimeContext.suspendedSp),
        word,
        block.emit(FrameValue(.callerStackPointer)),
      ),
    );
    block.emit(
      StoreNative(
        offset(record, RuntimeContext.suspendedPc),
        word,
        block.emit(FrameValue(.returnAddress)),
      ),
    );
    return (block, [entry, block, failed]);
  }

  IrFunction _bridge(NativeSignature signature) =>
      _bridges.putIfAbsent(signature, () {
        final compound = signature.result is NativeCompoundType;
        final target = FunctionTarget(
          null,
          'nativeCallFrame',
          compound ? .voidType : FfiTypes.rawValueType(signature.result),
          [
            .integer,
            if (compound) .integer,
            ...signature.parameters.map(FfiTypes.rawValueType),
          ],
        );
        final entry = Block(target.parameterTypes);
        final (block, blocks) = _publish(entry, managedContext!, failure!);
        final call = block.emit(
          RawNativeCall(
            entry.parameters.first,
            signature,
            entry.parameters.skip(compound ? 2 : 1),
            resultStorage: compound ? entry.parameters[1] : null,
          ),
        );
        block.finish(Return(target.returnType == .voidType ? null : call));
        return IrFunction(target, blocks);
      });

  IrFunction _conversion(NativeCall operation) {
    final target = FunctionTarget(
      null,
      'nativeArguments',
      operation.type,
      operation.inputs.map((value) => value.type).toList(),
    );
    final block = Block(target.parameterTypes);
    final parameters = block.parameters;
    Value address(Value value) => FfiTypes.isPointer(value.type)
        ? block.emit(PointerAddress(value))
        : FfiTypes.isCompound(value.type)
        ? block.emit(NativeAddress(value))
        : value;
    final signature = operation.signature;
    final output = signature.result is NativeCompoundType
        ? block.emit(NativeView(operation.type as ClassType))
        : null;
    final resultStorage = output == null
        ? null
        : block.emit(NativeAddress(output));
    final pointer = address(parameters.first);
    final arguments = parameters
        .skip(1)
        .take(operation.arguments.length)
        .map(address)
        .toList();
    final Value result;
    if (managedContext != null && !operation.isLeaf) {
      result = block.emit(
        DirectCall(_bridge(signature).target, [
          pointer,
          ?resultStorage,
          ...arguments,
        ]),
      );
    } else {
      result = block.emit(
        RawNativeCall(
          pointer,
          signature,
          arguments,
          resultStorage: resultStorage,
          isLeaf: operation.isLeaf,
        ),
      );
    }
    // The publication bridge skips its own raw-only frame. These source values
    // remain roots at the actual caller PC, including borrowed leaf owners.
    for (final owner in parameters) {
      block.emit(KeepAlive(owner));
    }
    if (output != null) block.emit(KeepAlive(output));
    final Value returned =
        output ??
        (FfiTypes.isPointer(operation.type)
            ? block.emit(
                PointerFromAddress(result, operation.type as ClassType),
              )
            : result);
    block.finish(Return(operation.type == .voidType ? null : returned));
    return IrFunction(target, [block]);
  }
}
