import 'package:dartc/hir.dart';

import 'facts.dart';
import 'reduce.dart';

/// Where code is added, and what is known there.
typedef Place = ({HirBlock block, Scope scope, Memory memory});

/// Adds the code of a function, without what is not needed.
final class Emitter(final HirModule _module) {
  final List<HirBlock> blocks = [];

  /// Where code is added, or null where it never comes.
  Place? place;

  bool get isReachable => place != null;

  HirBlock newBlock([Iterable<HirType> parameters = const []]) {
    final block = HirBlock(parameters);
    blocks.add(block);
    return block;
  }

  /// Adds [instruction], unless its value is known.
  HirValue add(HirInstruction instruction) {
    final known = _known(instruction);
    if (known != null) return known;
    final reduced = _answer(instruction) ?? reduce(instruction);
    if (reduced is! HirInstruction || _isPlaced(reduced)) return reduced;
    if (!identical(reduced, instruction)) return add(reduced);
    return _place(instruction);
  }

  final _placed = Set<HirValue>.identity();
  bool _isPlaced(HirValue value) => _placed.contains(value);

  HirValue? _known(HirInstruction instruction) {
    final Place(:scope, :memory) = place!;
    if (keyOf(instruction) case final key?) return scope[key];
    return switch (instruction) {
      HirLoad(:final field, :final object) => memory.field(field, object),
      HirLoadGlobal(:final global) => memory.global(global),
      _ => null,
    };
  }

  /// What [instruction] asks about the class of an object, if that is known.
  HirValue? _answer(HirInstruction instruction) {
    final Set<HirClass> passing;
    switch (instruction) {
      case HirIsInstance(:final test):
        passing = _module.tests[test]!;
      case HirHasClass(:final target):
        passing = {target};
      default:
        return null;
    }
    final classes = place!.scope.classesOf(instruction.inputs.single);
    if (classes == null) return null;
    if (classes.every(passing.contains)) return HirConst(true);
    return classes.any(passing.contains) ? null : HirConst(false);
  }

  /// Says in [scope] what it means that [condition], on which code depends,
  /// [holds].
  void assume(Scope scope, HirValue condition, {required bool holds}) {
    final Set<HirClass> passing;
    switch (condition) {
      case HirIsInstance(:final test):
        passing = _module.tests[test]!;
      case HirHasClass(:final target):
        passing = {target};
      default:
        return;
    }
    final object = (condition as HirInstruction).inputs.single;
    final classes = scope.classesOf(object);
    if (holds) {
      scope.setClasses(object, classes?.intersection(passing) ?? passing);
    } else if (classes != null) {
      scope.setClasses(object, classes.difference(passing));
    }
  }

  HirInstruction _place(HirInstruction instruction) {
    final Place(:block, :scope, :memory) = place!;
    block.add(instruction);
    _placed.add(instruction);
    if (keyOf(instruction) case final key?) scope[key] = instruction;
    switch (instruction) {
      case HirLoad(:final field, :final object):
        memory.readField(field, object, instruction);
      case HirStore(:final field, :final object, :final value):
        if (field.isFinal) {
          scope[keyOf(HirLoad(field, object))!] = value;
        } else {
          memory.setField(field, object, value);
        }
      case HirLoadGlobal(:final global):
        memory.setGlobal(global, instruction);
      case HirStoreGlobal(:final global, :final value):
        memory.setGlobal(global, value);
      case HirCall() || HirVirtualCall():
        memory.clear();
      case HirMachine(:final op) when op != .classNumber:
        memory.clear();
      default:
        break;
    }
    return instruction;
  }

  /// Ends the block here.
  void end(HirTerminator terminator) {
    place!.block.end(terminator);
    place = null;
  }

  /// Says that [value] is made in another way.
  void addOutside(HirValue value) => _placed.add(value);
}
