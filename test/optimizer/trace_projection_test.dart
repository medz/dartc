import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  test('callee-produced explicit trace retains storage at an exceptional continuation', () {
    final uri = Uri.parse('memory:trace-exit'),
        trace = ClassType(uri, 'UserTrace', interfaces: [ValueType.stackTrace]);
    final field = InstanceField(trace, 'code', .integer);
    final raise = FunctionTarget(uri, 'raise', .never, []),
        catchIt = FunctionTarget(uri, 'catchIt', .integer, []);
    final body = Block(), caller = Block(), handler = Block([.stackTrace]);
    final fresh = body.emit(NewPayload(trace, const Constant.integer(0)));
    body.emit(StoreField(field, fresh, const Constant.integer(73)));
    body.finish(Throw(const Constant.integer(42), stackTrace: fresh));
    caller.finish(
      Invoke(
        DirectCall(raise, []),
        onReturn: null,
        onThrow: Jump(handler, [UnwindValue.stackTrace]),
      ),
    );
    final asTrace = handler.emit(
          UncheckedCast(handler.parameters.single, trace),
        ),
        read = handler.emit(LoadField(field, asTrace));
    handler.finish(Return(read));
    final entry = IrFunction(catchIt, [caller, handler]);
    final terminal = FunctionTarget(uri, 'abort', .never, []),
        abort = Block(),
        spin = Block();
    abort.finish(Jump(spin));
    spin.finish(Jump(spin));
    final graph = IrProgram(
      [
        IrClass(trace, [field]),
      ],
      [
        IrFunction(raise, [body]),
        entry,
        IrFunction(terminal, [abort, spin]),
      ],
    );
    final f = ProgramFlow(graph, [
      (target: catchIt, arguments: []),
    ], allocationFailure: terminal).facts;
    final val = f.returnedBy(catchIt);
    final thrown = f.thrownBy(raise).stackTrace;
    final caught = f.valueOf(asTrace);
    expect(thrown.objects, hasLength(1));
    expect(caught.objects, hasLength(1));
    expect(
      f.pointStateOf(read)!.before.containsObject(caught.objects.single),
      isTrue,
    );
    expect(val.integers?.constant, 73);
  });
}
