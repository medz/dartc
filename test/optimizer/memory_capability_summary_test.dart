import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_memory.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:test/test.dart';

void main() {
  final type = ClassType(null, 'Payload');
  FlowObject object() =>
      FlowObject(NewPayload(type, const Constant.integer(0)), Object());

  test('memory capability summaries belong to their byte version', () {
    final a = object(), b = object();
    final first = FlowMemory(0, 8).writeReference(0, FlowValue.object(a));
    expect(first.references.objects, {a});
    final second = first.writeReference(0, FlowValue.object(b));
    expect(second.references.objects, {b});
    expect(first.references.objects, {a});
    final cleared = second.writeReference(
      0,
      FlowValue.constant(const Constant.nullValue()),
    );
    expect(cleared.references.objects, isEmpty);
    expect(second.references.objects, {b});
  });

  test('joined, renamed and forgotten bytes retain current capabilities', () {
    final a = object(), b = object(), renamed = object();
    final first = FlowMemory(0, 8).writeReference(0, FlowValue.object(a));
    final second = FlowMemory(0, 8).writeReference(0, FlowValue.object(b));
    expect(first.references.objects, {a});
    expect(second.references.objects, {b});
    final joined = first.join(second);
    expect(joined.references.objects, {a, b});
    final mapped = joined.map(
      (value) => value.mapObjects((object) => object == a ? renamed : object),
    );
    expect(mapped.references.objects, {renamed, b});
    expect(joined.references.objects, {a, b});
    expect(mapped.invalidate().references.objects, {renamed, b});
  });

  test('shared alternatives preserve provenance and scalar backing facts', () {
    final backing = FlowObject(
      MaterializeValue(const Constant.integer(42)),
      Object(),
    );
    final scalar = FlowValue.constant(const Constant.integer(42))
        .withManagedBackings([backing]);
    final external = FlowValue.unknown(type, external: true);
    final once = FlowValue.joined([scalar, external]);
    final repeated = FlowValue.joined([
      scalar,
      external,
      scalar,
      external,
      external,
    ]);
    expect(repeated, once);
    expect(repeated.managedBackings, {backing});
    expect(repeated.externalUnknownTypes, {type});
  });
}
