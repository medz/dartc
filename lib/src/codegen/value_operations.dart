import 'package:dartc/ir.dart';

import 'double_bits.dart';
import 'program_layout.dart';
import 'reference_equality.dart';
import 'selected_graph.dart';
import 'storage_access.dart';
import 'type_values.dart';

/// Builds comparisons and hashes from runtime value identities.
final class ValueOperations(
  final SelectedGraph graph,
  final ProgramLayout layouts,
  final FunctionTarget invalid,
) {
  StorageRead _load(InstanceField field, Value receiver, List<Value> into) {
    final load = StorageRead(field, receiver);
    into.add(load);
    return load;
  }

  Block _functionIdentity(Value value, Block current) {
    final tag = _load(
      layouts.closures.tag,
      value,
      graph.instructions[current]!,
    );
    final done = graph.addBlock([
      .integer,
      .object.nullable,
      TypeValues.list.nullable,
    ]);
    for (final shape in layouts.closures.all) {
      final selected = graph.addBlock(), next = graph.addBlock();
      final match = Equals(tag, Constant.integer(shape.tag));
      graph.instructions[current]!.add(match);
      graph.ends[current] = Branch(match, Jump(selected), Jump(next));
      final body = graph.instructions[selected]!;
      final applied = shape.instantiation;
      final original = applied == null
          ? value
          : _load(applied.origin, value, body);
      final generic = applied?.generic ?? shape;
      final anchor = generic.target.kind == .closure
          ? original
          : generic.target.kind.isVirtual
          ? _load(generic.captures.single, original, body)
          : const Constant.nullValue();
      final arguments = applied == null
          ? layouts.types.argumentConstants(shape.identityArguments)
          : _load(applied.arguments, value, body);
      graph.ends[selected] = Jump(done, [
        Constant.integer(shape.identity),
        anchor,
        arguments,
      ]);
      current = next;
    }
    final failure = DirectCall(invalid, []);
    graph.instructions[current]!.add(failure);
    graph.ends[current] = Unreachable(failure);
    return done;
  }

  Block hashFunction(Value value, Block entry) {
    final identity = _functionIdentity(value, entry);
    final [declaration, anchor, arguments] = identity.parameters;
    final body = graph.instructions[identity]!;
    final receiverHash = ObjectHashCode(anchor, direct: true);
    final typesHash = DirectCall(layouts.types.argumentHash, [arguments]);
    body.addAll([receiverHash, typesHash]);
    Value hash = declaration;
    for (final value in [receiverHash, typesHash]) {
      final product = IntBinary(.multiply, hash, const Constant.integer(31));
      hash = IntBinary(.add, product, value);
      body.addAll([product, hash]);
    }
    final result = IntBinary(.bitAnd, hash, const Constant.integer(0x3fffffff));
    body.add(result);
    final done = graph.addBlock([.integer]);
    graph.ends[identity] = Jump(done, [result]);
    return done;
  }

  Block identical(
    Value left,
    Value right,
    Block block,
    void Function(TypeTest, List<Value>) prepareTest,
  ) {
    final done = graph.addBlock([.boolean]);
    for (final type in [
      ValueType.integer,
      ValueType.floating,
      ValueType.boolean,
    ]) {
      if (layouts.typeTest(left.type, type) == .constantFalse ||
          layouts.typeTest(right.type, type) == .constantFalse) {
        continue;
      }
      final matching = graph.addBlock(),
          equal = graph.addBlock([type, type]),
          next = graph.addBlock();
      final a = TypeTest(left, type), b = TypeTest(right, type);
      prepareTest(a, graph.instructions[block]!);
      graph.ends[block] = Branch(a, Jump(matching), Jump(next));
      prepareTest(b, graph.instructions[matching]!);
      graph.ends[matching] = Branch(
        b,
        Jump(equal, [a.refinement(true)!, b.refinement(true)!]),
        Jump(next),
      );
      Value av = equal.parameters[0], bv = equal.parameters[1];
      if (type == ValueType.floating) {
        av = DoubleBits(av);
        bv = DoubleBits(bv);
        graph.instructions[equal]!.addAll([av, bv]);
      }
      final comparison = Equals(av, bv);
      graph.instructions[equal]!.add(comparison);
      graph.ends[equal] = Jump(done, [comparison]);
      block = next;
    }
    final identity =
        layouts.isReference(left.type) && layouts.isReference(right.type)
        ? ReferenceEquality(left, right)
        : const Constant.boolean(false);
    if (identity is ReferenceEquality) graph.instructions[block]!.add(identity);
    graph.ends[block] = Jump(done, [identity]);
    return done;
  }

  Block hashScalar(Value value, Block entry) {
    final done = graph.addBlock([.integer]);
    if (value.type == .nullType) {
      graph.ends[entry] = Jump(done, [const Constant.integer(0)]);
      return done;
    }
    if (value.type == .boolean) {
      graph.ends[entry] = Branch(
        value,
        Jump(done, [const Constant.integer(1)]),
        Jump(done, [const Constant.integer(0)]),
      );
      return done;
    }
    final body = graph.instructions[entry]!;
    if (value.type == .integer) {
      value = NumericToDouble(value);
      body.add(value);
    }
    final zero = Equals(value, const Constant.floating(0));
    body.add(zero);
    final nonzero = graph.addBlock();
    graph.ends[entry] = Branch(
      zero,
      Jump(done, [const Constant.integer(0)]),
      Jump(nonzero),
    );
    final parts = graph.instructions[nonzero]!;
    final bits = DoubleBits(value);
    final high = IntBinary(
      .unsignedShiftRight,
      bits,
      const Constant.integer(32),
    );
    final folded = IntBinary(.bitXor, bits, high);
    final mixed = IntBinary(
      .multiply,
      folded,
      const Constant.integer(0x9e3779b9),
    );
    final upper = IntBinary(
      .unsignedShiftRight,
      mixed,
      const Constant.integer(16),
    );
    final combined = IntBinary(.bitXor, mixed, upper);
    final hash = IntBinary(
      .bitAnd,
      combined,
      const Constant.integer(0x3fffffff),
    );
    parts.addAll([bits, high, folded, mixed, upper, combined, hash]);
    graph.ends[nonzero] = Jump(done, [hash]);
    return done;
  }

  Block equalFunction(Equals operation, Block entry) {
    final Equals(:left, :right, :negated) = operation;
    final join = graph.addBlock([.boolean]);
    Jump result(bool equal) => Jump(join, [Constant.boolean(equal != negated)]);
    ReferenceEquality identity(Value a, Value b, Block block) {
      final comparison = ReferenceEquality(a, b);
      graph.instructions[block]!.add(comparison);
      return comparison;
    }

    if (layouts.representation(right.type) != .reference) {
      graph.ends[entry] = result(false);
      return join;
    }
    var current = graph.addBlock();
    graph.ends[entry] = Branch(
      identity(left, right, entry),
      result(true),
      Jump(current),
    );
    if (left.type == .nullType ||
        right.type == .nullType ||
        layouts.closures.methods.isEmpty &&
            layouts.closures.specializations.isEmpty) {
      graph.ends[current] = result(false);
      return join;
    }
    for (final value in [left, right]) {
      final body = graph.instructions[current]!;
      final type = layouts.types.runtimeTypeOf(value, body);
      final kind = LoadField(TypeValues.kind, type);
      final test = Equals(kind, Constant.integer(TypeKind.function.index));
      body.addAll([kind, test]);
      final next = graph.addBlock();
      graph.ends[current] = Branch(test, Jump(next), result(false));
      current = next;
    }
    final a = _functionIdentity(left, current);
    final b = _functionIdentity(right, a);
    final same = Equals(a.parameters[0], b.parameters[0]);
    graph.instructions[b]!.add(same);
    final anchor = graph.addBlock(), arguments = graph.addBlock();
    graph.ends[b] = Branch(same, Jump(anchor), result(false));
    graph.ends[anchor] = Branch(
      identity(a.parameters[1], b.parameters[1], anchor),
      Jump(arguments),
      result(false),
    );
    final equal = DirectCall(layouts.types.argumentEquality, [
      a.parameters[2],
      b.parameters[2],
    ]);
    graph.instructions[arguments]!.add(equal);
    graph.ends[arguments] = Branch(equal, result(true), result(false));
    return join;
  }
}
