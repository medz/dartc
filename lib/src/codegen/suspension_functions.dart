import 'package:dartc/ir.dart';

import 'frame_description.dart';
import 'function_liveness.dart';
import 'function_representation.dart';
import 'heap_runtime.dart';
import 'selected_function.dart';
import 'storage_access.dart';

/// Assigns traced activations and resume entries to suspendable source bodies.
final class SuspensionFunctions(Iterable<IrFunction> functions) {
  final frames = <FunctionTarget, SuspensionFrame>{};

  this {
    for (final function in functions) {
      if (function.bodyKind != .synchronous) {
        frames[function.target] = SuspensionFrame(function, frames.length);
      }
    }
  }

  Iterable<IrClass> get classes =>
      frames.values.map((frame) => frame.declaration);
  Iterable<IrExternal> get entries => frames.values.expand(
    (frame) => [
      IrExternal(frame.resume),
      if (frame.synchronous) IrExternal(frame.clone),
    ],
  );
}

final class SuspensionFrame(final IrFunction source, int index) {
  final type = ClassType(null, 'SuspensionFrame$index');
  bool get synchronous => source.bodyKind == .syncGenerator;
  bool get streaming => source.bodyKind == .asyncGenerator;
  late final state = InstanceField(type, 'state', .integer);
  late final task = InstanceField(type, 'task', .object.nullable);
  late final resume = FunctionTarget(
    null,
    'resume',
    synchronous ? .boolean : .voidType,
    synchronous
        ? SyncRuntime.callback.parameters
        : AsyncRuntime.callback.parameters,
    owner: type,
    kind: .method,
  );
  late final clone = FunctionTarget(
    null,
    'clone',
    SyncRuntime.callback,
    [],
    owner: type,
    kind: .method,
  );
  final slots = <Value, InstanceField>{};

  IrClass get declaration => IrClass(
    type,
    [state, if (!synchronous) task, ...slots.values],
    members: [resume, if (synchronous) clone],
  );

  /// Spills only values crossing a suspension, then makes all resume edges explicit.
  SelectedFunction lower(
    FunctionRepresentation body,
    HeapRuntime runtime,
    FunctionTarget invalid,
  ) {
    final flow = FunctionLiveness(
      body,
      body.inputsOf,
      {},
      extraInputs: (end) => [if (end is Await) body.awaitTypes[end]!],
    );
    final saved = {
      ...body.entryParameters,
      for (final block in body.blocks)
        if (body.ends[block] is Await ||
            body.ends[block] is Yield ||
            body.ends[block] is YieldStream)
          ...flow.liveOut[block]!,
    };
    for (final value in saved) {
      final stored = body.typeOf(value);
      slots[value] = InstanceField(
        type,
        'slot${slots.length}',
        body.layouts.isReference(stored) ? .object.nullable : stored,
      );
    }
    body.layouts.defineStorage(declaration);
    final entry = Block(resume.parameterTypes);
    final result = SelectedFunction(
      resume,
      body.layouts,
      entry,
      sourceTarget: body.sourceTarget,
    );
    result.sourceLocations.addAll(body.sourceLocations);
    result.blocks.add(entry);
    result.instructions[entry] = [];
    result.blocks.addAll(body.blocks);
    result.parameterOverrides[body.entry] = body.entryParameters;
    result.aliases.addAll(body.aliases);
    result.boxes.addAll(body.boxes);
    result.tests.addAll(body.tests);
    result.invocations.addAll(body.invocations);
    result.resultTypes.addAll(body.resultTypes);
    final frame = entry.parameters.first;
    if (!synchronous) {
      final context = StorageRead(task, frame, type: .object);
      result.instructions[entry]!.add(context);
      result.stackContext = context;
    }

    Value reload(Value value, List<Value> into) {
      if (value is TestedValue) value = value.test.operand;
      final field = slots[value];
      if (field == null) return value;
      final load = StorageRead(field, frame, type: value.type);
      result.resultTypes[load] = body.typeOf(value);
      into.add(load);
      return load;
    }

    Jump transfer(Jump edge, [Map<Value, Value> incoming = const {}]) {
      final bridge = result.addBlock();
      final values = result.instructions[bridge]!;
      final jump = Jump(edge.target, edge.arguments);
      result.edgeArguments[jump] = [
        for (final value in body.argumentsOf(edge))
          incoming[value] ?? reload(value, values),
      ];
      result.ends[bridge] = jump;
      return Jump(bridge);
    }

    var dispatch = entry;
    final initial = result.addBlock();
    final initialArguments = [
      for (final value in body.entryParameters)
        reload(value, result.instructions[initial]!),
    ];
    final initialJump = Jump(body.entry, source.entry.parameters);
    result.edgeArguments[initialJump] = initialArguments;
    result.ends[initial] = initialJump;
    final next = result.addBlock();
    final currentState = StorageRead(state, frame);
    final fresh = Equals(currentState, const Constant.integer(0));
    result.instructions[entry]!.addAll([currentState, fresh]);
    result.ends[entry] = Branch(fresh, Jump(initial), Jump(next));
    dispatch = next;
    var stateId = 0;

    void suspend(Block continuation, List<Value> into, Block block) {
      stateId++;
      final following = result.addBlock();
      final match = Equals(currentState, Constant.integer(stateId));
      result.instructions[dispatch]!.add(match);
      result.ends[dispatch] = Branch(
        match,
        Jump(continuation),
        Jump(following),
      );
      dispatch = following;
      for (final entry in slots.entries) {
        if (body.layouts.isReference(entry.value.type) &&
            !flow.liveOut[block]!.contains(entry.key)) {
          into.add(
            StorageWrite(entry.value, frame, const Constant.nullValue()),
          );
        }
      }
      into.add(StorageWrite(state, frame, Constant.integer(stateId)));
    }

    for (final block in body.blocks) {
      final into = result.instructions[block] = <Value>[];
      for (final parameter in body.parametersOf(block)) {
        if (slots[parameter] case final field?) {
          into.add(StorageWrite(field, frame, parameter));
        }
      }
      for (final operation in body.instructions[block]!) {
        if (flow.omitted.contains(operation)) continue;
        result.operands[operation] = [
          for (final value in body.inputsOf(operation)) reload(value, into),
        ];
        into.add(operation);
        if (slots[operation] case final field?) {
          into.add(StorageWrite(field, frame, operation));
        }
      }
      final endStart = into.length, added = result.blocks.length;
      final end = body.ends[block]!;
      final description = frameDescription(
        body.sourceTarget,
        body.sourceLocations[block],
      );
      final location = description == null
          ? const Constant.nullValue()
          : Constant.string(description);
      switch (end) {
        case Await():
          final continuation = result.addBlock();
          final success = result.addBlock(), failure = result.addBlock();
          final failed = Equals(
            entry.parameters[2],
            const Constant.nullValue(),
            negated: true,
          );
          result.instructions[continuation]!.add(failed);
          result.ends[continuation] = Branch(
            failed,
            Jump(failure),
            Jump(success),
          );
          if (end.onResume case final edge?) {
            final returned = UncheckedCast(
              entry.parameters[1],
              end.result.type,
            );
            result.instructions[success]!.add(returned);
            result.ends[success] = transfer(edge, {end.result: returned});
          } else {
            final impossible = TypeCast(entry.parameters[1], .never);
            result.instructions[success]!.add(impossible);
            result.ends[success] = Unreachable(impossible);
          }
          final exception = UncheckedCast(entry.parameters[2], .object);
          final trace = UncheckedCast(entry.parameters[3], .stackTrace);
          result.instructions[failure]!.addAll([exception, trace]);
          result.ends[failure] = end.onThrow == null
              ? Throw(exception, stackTrace: trace)
              : transfer(end.onThrow!, {
                  UnwindValue.exception: exception,
                  UnwindValue.stackTrace: trace,
                });
          final value = reload(body.operandsForAwait[end]!, into);
          final argument = reload(body.awaitTypes[end]!, into);
          suspend(continuation, into, block);
          final activation = StorageRead(task, frame, type: .object);
          into.add(activation);
          final call = DirectCall(
            runtime.async!.awaitValue,
            [activation, value, location],
            typeArguments: [end.result.type],
          );
          result.operands[call] = [activation, value, location, argument];
          result.invocations[call] = runtime.async!.awaitValue;
          into.add(call);
          if (end.onThrow case final edge?) {
            final done = result.addBlock();
            result.ends[done] = const Return(Constant.nullValue());
            result.ends[block] = Invoke(
              call,
              onReturn: Jump(done),
              onThrow: transfer(edge),
            );
          } else {
            result.ends[block] = const Return(Constant.nullValue());
          }
        case Yield() when synchronous:
          final value = reload(body.operandsForYield[end]!, into);
          suspend(transfer(end.onResume).target, into, block);
          final call = DirectCall(runtime.sync!.yieldValue, [
            entry.parameters[1],
            value,
          ]);
          result.invocations[call] = runtime.sync!.yieldValue;
          into.add(call);
          result.ends[block] = const Return(Constant.boolean(true));
        case Yield() || YieldStream():
          final (operand, onResume, onCancel, onThrow, target) = switch (end) {
            Yield(:final onResume, :final onCancel) => (
              body.operandsForYield[end]!,
              onResume,
              onCancel!,
              null,
              runtime.asyncGenerator!.yieldValue,
            ),
            YieldStream(
              :final stream,
              :final onResume,
              :final onCancel,
              :final onThrow,
            ) =>
              (
                stream,
                onResume,
                onCancel,
                onThrow,
                runtime.asyncGenerator!.yieldStream,
              ),
            _ => throw StateError('Expected a generator suspension.'),
          };
          final continuation = result.addBlock();
          // Yield callbacks carry the SDK controller's cancellation flag.
          final cancelled = UncheckedCast(entry.parameters[1], .boolean);
          result.instructions[continuation]!.add(cancelled);
          result.ends[continuation] = Branch(
            cancelled,
            transfer(onCancel),
            transfer(onResume),
          );
          final value = reload(operand, into);
          suspend(continuation, into, block);
          final activation = StorageRead(task, frame, type: .object);
          into.add(activation);
          final call = DirectCall(target, [activation, value, location]);
          result.invocations[call] = target;
          into.add(call);
          final done = result.addBlock();
          result.ends[done] = const Return(Constant.nullValue());
          final after = onThrow == null ? block : result.addBlock();
          result.ends[after] = Branch(call, transfer(onCancel), Jump(done));
          if (onThrow != null) {
            result.ends[block] = Invoke(
              call,
              onReturn: Jump(after),
              onThrow: transfer(onThrow),
            );
          }
        case Return() when synchronous:
          result.ends[block] = const Return(Constant.boolean(false));
        case Return(:final value):
          final returned = reload(value ?? const Constant.nullValue(), into);
          final activation = StorageRead(task, frame, type: .object);
          into.add(activation);
          final complete = streaming
              ? runtime.asyncGenerator!.complete
              : runtime.async!.complete;
          final call = DirectCall(complete, [activation, returned]);
          result.invocations[call] = complete;
          into.add(call);
          result.ends[block] = const Return(Constant.nullValue());
        case final Jump edge:
          result.ends[block] = transfer(edge);
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          result.ends[block] = Branch(
            reload(condition, into),
            transfer(ifTrue),
            transfer(ifFalse),
          );
        case Invoke(:final operation, :final onReturn, :final onThrow):
          result.ends[block] = Invoke(
            operation,
            onReturn: onReturn == null ? null : transfer(onReturn),
            onThrow: transfer(onThrow),
          );
        case Throw(:final exception, :final stackTrace, :final onThrow):
          result.ends[block] = Throw(
            reload(exception, into),
            stackTrace: stackTrace == null ? null : reload(stackTrace, into),
            onThrow: onThrow == null ? null : transfer(onThrow),
          );
        case Unreachable():
          result.ends[block] = end;
        default:
          throw UnsupportedError('Suspension terminator: ${end.runtimeType}');
      }
      if (body.sourceLocations[block] case final location?) {
        for (final value in into.skip(endStart)) {
          result.sourceLocations[value] = location;
        }
        for (final next in result.blocks.skip(added)) {
          for (final value in result.instructions[next]!) {
            result.sourceLocations[value] = location;
          }
        }
      }
    }
    final failure = DirectCall(invalid, []);
    result.instructions[dispatch]!.add(failure);
    result.invocations[failure] = invalid;
    result.ends[dispatch] = Unreachable(failure);
    return result;
  }

  IrFunction wrapper(HeapRuntime runtime) {
    final entry = Block(source.target.parameterTypes);
    final frame = entry.emit(NewPayload(type, const Constant.integer(0)));
    final callback = entry.emit(
      BindMethod(synchronous ? clone : resume, frame, direct: true),
    );
    if (synchronous) {
      entry.finish(
        Return(
          entry.emit(
            DirectCall(
              runtime.sync!.create,
              [callback],
              typeArguments: [source.yieldType!],
            ),
          ),
        ),
      );
      return IrFunction(source.target, [entry], defaults: source.defaults);
    }
    final create = streaming
        ? runtime.asyncGenerator!.create
        : runtime.async!.create;
    final start = streaming
        ? runtime.asyncGenerator!.start
        : runtime.async!.start;
    final element = streaming ? source.yieldType! : source.completionType!;
    final activation = entry.emit(
      DirectCall(create, [callback], typeArguments: [element]),
    );
    entry.emit(StoreField(task, frame, activation));
    entry.finish(
      Return(
        entry.emit(DirectCall(start, [activation], typeArguments: [element])),
      ),
    );
    return IrFunction(source.target, [entry], defaults: source.defaults);
  }

  IrFunction factory(List<BlockParameter> parameters) {
    final entry = Block(clone.parameterTypes);
    final frame = entry.emit(NewPayload(type, const Constant.integer(0)));
    for (final parameter in parameters) {
      final field = slots[parameter]!;
      final value = entry.emit(LoadField(field, entry.parameters.first));
      entry.emit(StoreField(field, frame, value));
    }
    entry.finish(Return(entry.emit(BindMethod(resume, frame, direct: true))));
    return IrFunction(clone, [entry]);
  }

  /// Installs arguments before the first callback can enter the activation.
  void initialize(
    FunctionRepresentation wrapper,
    List<BlockParameter> parameters,
  ) {
    for (final values in wrapper.instructions.values) {
      final index = values.indexWhere(
        (value) => value is NewPayload && value.type == type,
      );
      if (index < 0) continue;
      final frame = values[index];
      values.insertAll(index + 1, [
        for (final (i, parameter) in parameters.indexed)
          StorageWrite(slots[parameter]!, frame, wrapper.entryParameters[i]),
      ]);
      return;
    }
    throw StateError('Missing suspension activation allocation.');
  }
}
