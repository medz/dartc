import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart' show TypeKind;

import 'double_bits.dart';
import 'program_layout.dart';
import 'reference_equality.dart';
import 'selected_function.dart';
import 'storage_access.dart';
import 'value_carrier.dart';

/// Builds comparisons and hashes from runtime value identities.
final class ValueOperations(
  final SelectedFunction graph,
  final ProgramLayout layouts,
  final FunctionTarget invalid,
) {
  StorageRead _load(InstanceField field, Value receiver, List<Value> into) {
    final load = StorageRead(field, receiver);
    into.add(load);
    return load;
  }

  Block _functionIdentity(Value value, Block current) {
    final body = graph.instructions[current]!;
    final done = graph.addBlock([
      .integer,
      .object.nullable,
      TypeMetadata.list.nullable,
    ]);
    graph.ends[current] = Jump(done, [
      _load(layouts.closures.identity, value, body),
      _load(layouts.closures.identityAnchor, value, body),
      _load(layouts.closures.identityArguments, value, body),
    ]);
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
    Block Function(TypeTest, Block) prepareTest,
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
      block = prepareTest(a, block);
      graph.ends[block] = Branch(a, Jump(matching), Jump(next));
      final checked = prepareTest(b, matching);
      graph.ends[checked] = Branch(
        b,
        Jump(equal, [a.refinement(true) ?? left, b.refinement(true) ?? right]),
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
    // Records need no persistent identity; equality must still visit their fields.
    final body = graph.instructions[block]!;
    final actual = layouts.types.runtimeTypeOf(left, body);
    final kind = _load(TypeMetadata.kind, actual, body);
    final record = Equals(kind, Constant.integer(TypeKind.record.index));
    body.add(record);
    final ordinary = graph.addBlock();
    graph.ends[block] = Branch(
      record,
      Jump(done, [const Constant.boolean(false)]),
      Jump(ordinary),
    );
    block = ordinary;
    final identity =
        graph.shapeOf(left).isReference && graph.shapeOf(right).isReference
        ? ReferenceEquality(left, right)
        : const Constant.boolean(false);
    if (identity is ReferenceEquality) graph.instructions[block]!.add(identity);
    graph.ends[block] = Jump(done, [identity]);
    return done;
  }

  Block identityHash(
    Value value,
    Block block,
    Block Function(TypeTest, Block) prepareTest,
  ) {
    if (value.type == .nullType || layouts.isBoxable(value.type)) {
      return hashScalar(value, block);
    }
    final done = graph.addBlock([.integer]);
    for (final type in [
      ValueType.integer,
      ValueType.floating,
      ValueType.boolean,
    ]) {
      if (layouts.typeTest(value.type, type) == .constantFalse) continue;
      final scalar = graph.addBlock([type]), next = graph.addBlock();
      final test = TypeTest(value, type);
      block = prepareTest(test, block);
      graph.ends[block] = Branch(
        test,
        Jump(scalar, [test.refinement(true)!]),
        Jump(next),
      );
      final hashed = hashScalar(scalar.parameters.single, scalar);
      graph.ends[hashed] = Jump(done, hashed.parameters);
      block = next;
    }
    final hash = ObjectHashCode(value, direct: true);
    graph.instructions[block]!.add(hash);
    graph.ends[block] = Jump(done, [hash]);
    return done;
  }

  Block hashScalar(Value value, Block entry) {
    final carrier = valueCarrier(value.type);
    if (carrier != value.type) {
      value = TypeView(value, carrier);
      graph.instructions[entry]!.add(value);
    }
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
    final high = IntBinary.unchecked(
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
    final upper = IntBinary.unchecked(
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

    if (!graph.shapeOf(right).isReference) {
      graph.ends[entry] = result(false);
      return join;
    }
    var current = graph.addBlock();
    graph.ends[entry] = Branch(
      identity(left, right, entry),
      result(true),
      Jump(current),
    );
    if (left.type == .nullType || right.type == .nullType) {
      graph.ends[current] = result(false);
      return join;
    }
    for (final value in [left, right]) {
      final body = graph.instructions[current]!;
      final type = layouts.types.runtimeTypeOf(value, body);
      final kind = LoadField(TypeMetadata.kind, type);
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
