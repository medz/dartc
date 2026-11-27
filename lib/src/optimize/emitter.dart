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
      case HirRefine(:final value, :final classes):
        return _isKnownAs(value, classes) ? value : null;
      default:
        return null;
    }
    final classes = classesOf(instruction.inputs.single);
    if (classes == null) return null;
    if (classes.every(passing.contains)) return HirConst(true);
    return classes.any(passing.contains) ? null : HirConst(false);
  }

  /// Whether how [value] is made tells that it is of [classes], and not null.
  ///
  /// What is known here only is not enough: it is forgotten when the function
  /// is made anew.
  static bool _isKnownAs(HirValue value, Set<HirClass> classes) =>
      isObject(value) && classesOfMade(value)!.every(classes.contains);

  /// What [call] of the runtime's test of types gives, if the class of the
  /// object decides it.
  ///
  /// Where the type is a sealed type of the module, no class is of it but
  /// those that pass its test, so classes that are known tell both ways.
  HirValue? answerOf(HirCall call) {
    if (call
        case HirCall(
          :final target,
          arguments: [final object, HirStatic(object: final type)],
        )
        when target == _module.isInstance) {
      final test = _module.sealedTypes[type];
      if (test == null) return null;
      final classes = classesOf(object);
      if (classes == null || !isObject(object) && _unboxedAs(object) == null) {
        return null;
      }
      final passing = _module.tests[test]!;
      if (classes.every(passing.contains)) return add(HirConst(true));
      if (!classes.any(passing.contains)) return add(HirConst(false));
    }
    return null;
  }

  /// For each field, the classes of which it is the only one: those whose
  /// boxes have it.
  late final _boxes = () {
    final boxes = <HirField, Set<HirClass>>{};
    for (final class_ in _module.classes) {
      if (class_.fields case [final field]) {
        (boxes[field] ??= {}).add(class_);
      }
    }
    return boxes;
  }();

  /// The classes of boxes that [object] is one of, if it is unboxed where code
  /// is: elsewhere code never comes. It is then not null either.
  Set<HirClass>? _unboxedAs(HirValue object, [Scope? scope]) {
    if ((scope ?? place!.scope)[unboxingOf(object)] case HirUnbox(
      :final field,
    )) {
      return _boxes[field];
    }
    return null;
  }

  /// The classes that [value] can be of unless it is null, if they are known
  /// in [scope], or where code is.
  Set<HirClass>? classesOf(HirValue value, [Scope? scope]) {
    scope ??= place!.scope;
    final known = scope.classesOf(value), boxes = _unboxedAs(value, scope);
    if (boxes == null || known == null) return known ?? boxes;
    return known.every(boxes.contains) ? known : known.intersection(boxes);
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
    final classes = classesOf(object, scope);
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
      case HirUnbox(:final object):
        scope[unboxingOf(object)] = instruction;
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
