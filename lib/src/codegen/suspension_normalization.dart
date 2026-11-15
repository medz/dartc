import 'package:dartc/ir.dart';

import 'frame_description.dart';
import 'function_liveness.dart';
import 'heap_runtime.dart';

/// Exposes suspension and resumption as ordinary Dart calls and lexical closures.
///
/// Captured SSA values remain semantic operands; storage and layout are selected
/// only after the resulting program has been analyzed and rewritten.
final class SuspensionNormalization(
  final IrProgram program,
  final HeapRuntime runtime,
) {
  /// Returns synchronous graphs for source and SDK suspension bodies.
  IrProgram run() {
    if (program.functions.every((body) => body.bodyKind == .synchronous)) {
      return program;
    }
    return IrProgram(
      program.classes,
      [
        for (final body in program.functions)
          if (body.bodyKind == .synchronous)
            body
          else
            ..._SuspensionBody(body, runtime).run(),
      ],
      globals: program.globals,
      externals: program.externals,
    );
  }
}

final class _Continuation(
  final FunctionTarget target,
  final List<Value> captures,
  final Block? suspended,
);

final class _SuspensionBody(
  final IrFunction source,
  final HeapRuntime runtime,
) {
  late final flow = FunctionLiveness.source(source);
  late final inputs = {
    for (final block in source.blocks) block: flow.liveIn[block]!.toList(),
  };
  bool get sync => source.bodyKind == .syncGenerator;
  bool get stream => source.bodyKind == .asyncGenerator;
  static final contextType = CellType(.object);
  late final signature = sync ? SyncRuntime.callback : AsyncRuntime.callback;
  late final initial = continuation(inputs[source.entry]!, null);
  late final resumes = {
    for (final block in source.blocks)
      if (block.end is Await || block.end is Yield || block.end is YieldStream)
        block: continuation(captures(block.end), block),
  };

  SourceLocation location(Object key) {
    final found = source.sourceLocations[key];
    return SourceLocation(
      found?.position,
      function: found?.function ?? source.target,
      caller: found?.caller,
    );
  }

  _Continuation continuation(List<Value> captures, Block? suspended) =>
      _Continuation(
        FunctionTarget(
          null,
          'resume',
          signature.result,
          signature.parameters,
          kind: .closure,
          enclosing: source.target,
          sourceOffset: 0,
          captures: [if (!sync) contextType, ...captures.map((v) => v.type)],
          awaiterCapture: sync ? null : 0,
        ),
        captures,
        suspended,
      );

  List<Value> arguments(Jump edge) => [
    for (final value in inputs[edge.target]!)
      if ((value is BlockParameter ? edge.target.parameters.indexOf(value) : -1)
          case final index when index >= 0)
        edge.arguments[index]
      else
        value,
  ];

  List<Value> captures(Terminator end) {
    final edges = switch (end) {
      Await(:final onResume, :final onThrow) => [?onResume, ?onThrow],
      Yield(:final onResume, :final onCancel) => [onResume, ?onCancel],
      YieldStream(:final onResume, :final onCancel) => [onResume, onCancel],
      _ => throw StateError('Expected a suspension.'),
    };
    return {
      for (final edge in edges)
        for (final value in arguments(edge))
          if ((value is TestedValue ? value.test.operand : value)
              case final input
              when input is! Constant &&
                  input is! UnwindValue &&
                  input is! AwaitResult)
            input,
    }.toList();
  }

  List<IrFunction> run() {
    if (sync
        ? runtime.sync == null
        : runtime.async == null || stream && runtime.asyncGenerator == null) {
      throw UnsupportedError('Missing runtime entries for ${source.bodyKind}.');
    }
    final entry = Block(source.target.parameterTypes);
    final received = {
      for (final (index, value) in source.entry.parameters.indexed)
        value: entry.parameters[index],
    };
    final generated = <IrFunction>[];
    final element = source.yieldType ?? source.completionType!;
    if (sync) {
      final factory = FunctionTarget(
        null,
        'iterate',
        SyncRuntime.callback,
        [],
        kind: .closure,
        enclosing: source.target,
        sourceOffset: 0,
        captures: initial.target.captures,
      );
      final start = Block(factory.parameterTypes);
      start.finish(
        Return(
          start.emit(MakeClosure(initial.target, start.parameters.skip(1))),
        ),
      );
      generated.add(IrFunction(factory, [start]));
      final create = entry.emit(
        MakeClosure(factory, initial.captures.map((v) => received[v]!)),
      );
      entry.finish(
        Return(
          entry.emit(
            DirectCall(
              runtime.sync!.create,
              [create],
              typeArguments: [element],
            ),
          ),
        ),
      );
    } else {
      // Creation only installs the callback; the task is bound before first entry.
      final context = entry.emit(NewCell(contextType, null));
      final callback = entry.emit(
        MakeClosure(initial.target, [
          context,
          ...initial.captures.map((v) => received[v]!),
        ]),
      );
      final create = stream
          ? runtime.asyncGenerator!.create
          : runtime.async!.create;
      final start = stream
          ? runtime.asyncGenerator!.start
          : runtime.async!.start;
      final task = entry.emit(
        DirectCall(create, [callback], typeArguments: [element]),
      );
      entry.emit(WriteCell(context, task));
      entry.finish(
        Return(entry.emit(DirectCall(start, [task], typeArguments: [element]))),
      );
    }
    return [
      IrFunction(
        source.target,
        [entry],
        defaults: source.defaults,
        sourceLocations: {
          entry: location(source.entry),
          for (final operation in entry.instructions)
            operation: location(source.entry),
        },
      ),
      ...generated,
      for (final continuation in [initial, ...resumes.values])
        _Region(this, continuation).run(),
    ];
  }
}

final class _Region(
  final _SuspensionBody owner,
  final _Continuation continuation,
) {
  late final entry = Block(continuation.target.parameterTypes);
  late final blocks = <Block>[entry];
  final copies = <Block, Block>{};
  final pending = <Block>[];
  final locations = <Object, SourceLocation>{};
  late final captured = <Value, Value>{
    for (final (index, value) in continuation.captures.indexed)
      value: entry.parameters[index + (owner.sync ? 1 : 2)],
  };
  late final supplied = entry.parameters
      .skip(continuation.target.argumentOffset)
      .toList();

  Block block(Object origin, [Iterable<ValueType> parameters = const []]) {
    final result = Block(parameters);
    blocks.add(result);
    locations[result] = owner.location(origin);
    return result;
  }

  // Explicit live inputs preserve loop redefinitions when a region is resumed.
  Block copy(Block original) => copies.putIfAbsent(original, () {
    pending.add(original);
    return block(original, owner.inputs[original]!.map((v) => v.type));
  });

  T emit<T extends Instruction>(Block into, T operation, Object origin) {
    locations[operation] = owner.location(origin);
    return into.emit(operation);
  }

  Value read(Map<Value, Value> values, Value value) => value is Constant
      ? value
      : values[value] ??
            (throw StateError(
              'Missing continuation value: ${value.runtimeType}',
            ));

  Jump edge(
    Jump source,
    Value Function(Value) value,
    Object origin, {
    Map<UnwindValue, Value> unwind = const {},
  }) {
    final arguments = owner.arguments(source);
    final target = copy(source.target);
    Value mapped(Value input) =>
        input is UnwindValue ? unwind[input] ?? input : value(input);
    if (!arguments.any((v) => v is TestedValue)) {
      return Jump(target, arguments.map(mapped));
    }
    // The branch establishes these refinements even when its test was captured.
    final raw = [
      for (final v in arguments) v is TestedValue ? v.test.operand : v,
    ];
    final bridge = block(origin, raw.map((v) => v.type));
    final refined = [
      for (final (index, v) in arguments.indexed)
        if (v is TestedValue)
          emit(bridge, UncheckedCast(bridge.parameters[index], v.type), origin)
        else
          bridge.parameters[index],
    ];
    bridge.finish(Jump(target, refined));
    return Jump(bridge, raw.map(mapped));
  }

  Value task(Block into, Object origin) =>
      emit(into, ReadCell(entry.parameters[1]), origin);

  Value next(Block into, Block original, Value Function(Value) value) {
    final next = owner.resumes[original]!;
    return emit(
      into,
      MakeClosure(next.target, [
        if (!owner.sync) entry.parameters[1],
        ...next.captures.map(value),
      ]),
      original,
    );
  }

  IrFunction run() {
    final suspended = continuation.suspended;
    locations[entry] = owner.location(suspended ?? owner.source.entry);
    Value capture(Value value) => read(captured, value);
    if (suspended == null) {
      entry.finish(
        Jump(
          copy(owner.source.entry),
          owner.inputs[owner.source.entry]!.map(capture),
        ),
      );
    } else {
      switch (suspended.end) {
        case Await(:final result, :final onResume, :final onThrow):
          final success = block(suspended), failure = block(suspended);
          final failed = emit(
            entry,
            Equals(supplied[1], const Constant.nullValue(), negated: true),
            suspended,
          );
          entry.finish(Branch(failed, Jump(failure), Jump(success)));
          if (onResume == null) {
            final impossible = emit(
              success,
              TypeCast(supplied[0], .never),
              suspended,
            );
            success.finish(Unreachable(impossible));
          } else {
            final returned = emit(
              success,
              UncheckedCast(supplied[0], result.type),
              suspended,
            );
            success.finish(
              edge(
                onResume,
                (v) => v == result ? returned : capture(v),
                suspended,
              ),
            );
          }
          final exception = emit(
            failure,
            UncheckedCast(supplied[1], .object),
            suspended,
          );
          final trace = emit(
            failure,
            UncheckedCast(supplied[2], .stackTrace),
            suspended,
          );
          if (onThrow == null) {
            failure.finish(Throw(exception, stackTrace: trace));
          } else {
            failure.finish(
              edge(
                onThrow,
                capture,
                suspended,
                unwind: {
                  UnwindValue.exception: exception,
                  UnwindValue.stackTrace: trace,
                },
              ),
            );
          }
        case Yield(:final onResume) when owner.sync:
          entry.finish(edge(onResume, capture, suspended));
        case Yield(:final onResume, onCancel: final onCancel!) ||
            YieldStream(:final onResume, :final onCancel):
          final cancelled = emit(
            entry,
            UncheckedCast(supplied[0], .boolean),
            suspended,
          );
          entry.finish(
            Branch(
              cancelled,
              edge(onCancel, capture, suspended),
              edge(onResume, capture, suspended),
            ),
          );
        default:
          throw StateError('Expected a continuation.');
      }
    }
    for (var index = 0; index < pending.length; index++) {
      lower(pending[index]);
    }
    return IrFunction(continuation.target, blocks, sourceLocations: locations);
  }

  void lower(Block original) {
    final into = copies[original]!;
    final values = <Value, Value>{
      for (final (index, value) in owner.inputs[original]!.indexed)
        value: into.parameters[index],
    };
    Value value(Value input) => read(values, input);
    Jump jump(Jump source) => edge(source, value, original);
    for (final operation in original.instructions) {
      values[operation] = emit(into, operation.mapInputs(value), operation);
    }
    final end = original.end;
    switch (end) {
      case final Jump source:
        into.finish(jump(source));
      case Branch(:final condition, :final ifTrue, :final ifFalse):
        into.finish(Branch(value(condition), jump(ifTrue), jump(ifFalse)));
      case Invoke(:final operation, :final onReturn, :final onThrow):
        final called = operation.mapInputs(value);
        values[operation] = called;
        locations[called] = owner.location(operation);
        into.finish(
          Invoke(
            called,
            onReturn: onReturn == null ? null : jump(onReturn),
            onThrow: jump(onThrow),
          ),
        );
      case Throw(
        :final exception,
        :final stackTrace,
        :final onThrow,
        :final isRecorded,
      ):
        final error = value(exception);
        final trace = stackTrace == null ? null : value(stackTrace);
        final handler = onThrow == null ? null : jump(onThrow);
        into.finish(
          isRecorded
              ? Throw.recorded(error, trace!, onThrow: handler)
              : Throw(error, stackTrace: trace, onThrow: handler),
        );
      case ExhaustivenessFailure(:final onThrow):
        into.finish(
          ExhaustivenessFailure(onThrow == null ? null : jump(onThrow)),
        );
      case Unreachable(:final cause):
        into.finish(Unreachable(value(cause)));
      case Return(:final value):
        if (owner.sync) {
          into.finish(const Return(Constant.boolean(false)));
        } else {
          final complete = owner.stream
              ? owner.runtime.asyncGenerator!.complete
              : owner.runtime.async!.complete;
          emit(
            into,
            DirectCall(complete, [
              task(into, original),
              value == null ? const Constant.nullValue() : read(values, value),
            ]),
            original,
          );
          into.finish(const Return());
        }
      case Yield(:final value) when owner.sync:
        final callback = next(into, original, (v) => read(values, v));
        emit(
          into,
          DirectCall(owner.runtime.sync!.yieldValue, [
            supplied[0],
            read(values, value),
            callback,
          ]),
          original,
        );
        into.finish(const Return(Constant.boolean(true)));
      case Await(:final operand, :final result, :final onThrow):
        final callback = next(into, original, value);
        final call = DirectCall(
          owner.runtime.async!.awaitValue,
          [task(into, original), value(operand), location(original), callback],
          typeArguments: [result.type],
        );
        if (onThrow == null) {
          emit(into, call, original);
          into.finish(const Return());
        } else {
          final done = block(original)..finish(const Return());
          locations[call] = owner.location(original);
          into.finish(
            Invoke(call, onReturn: Jump(done), onThrow: jump(onThrow)),
          );
        }
      case Yield() || YieldStream():
        final (operand, cancel, failure, target) = switch (end) {
          Yield(:final value, onCancel: final cancel!) => (
            value,
            cancel,
            null,
            owner.runtime.asyncGenerator!.yieldValue,
          ),
          YieldStream(:final stream, :final onCancel, :final onThrow) => (
            stream,
            onCancel,
            onThrow,
            owner.runtime.asyncGenerator!.yieldStream,
          ),
          _ => throw StateError('Expected a stream suspension.'),
        };
        final callback = next(into, original, value);
        final call = DirectCall(target, [
          task(into, original),
          value(operand),
          location(original),
          callback,
        ]);
        final done = block(original)..finish(const Return());
        if (failure == null) {
          emit(into, call, original);
          into.finish(Branch(call, jump(cancel), Jump(done)));
        } else {
          final returned = block(original, [.boolean]);
          locations[call] = owner.location(original);
          into.finish(
            Invoke(
              call,
              onReturn: Jump(returned, [call]),
              onThrow: jump(failure),
            ),
          );
          returned.finish(
            Branch(returned.parameters.single, jump(cancel), Jump(done)),
          );
        }
    }
  }

  Constant location(Block source) {
    final description = frameDescription(
      owner.source.target,
      owner.source.sourceLocations[source],
    );
    return description == null
        ? const Constant.nullValue()
        : Constant.string(description);
  }
}
