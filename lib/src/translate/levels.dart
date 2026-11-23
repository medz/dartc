import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// One class or mixin whose members the objects of a class have.
///
/// A class has a level of its own, after one for each of its mixins, after
/// those of its superclass. Levels are told apart by themselves.
final class Level._(
  /// The class that declares this level.
  final ClassElement class_,

  /// What its members are declared by, as a type made of the type parameters
  /// of [class_].
  final InterfaceType type,
  final Level? superLevel,
) {
  InterfaceElement get element => type.element;
  bool get isMixin => element != class_;

  /// This level and those after which it comes.
  Iterable<Level> get chain sync* {
    for (Level? found = this; found != null; found = found.superLevel) {
      yield found;
    }
  }
}

/// The levels of the program's classes.
final class LevelTable() {
  final _levels = <ClassElement, Level>{};

  /// The level of [class_] itself.
  Level of(ClassElement class_) => _levels[class_] ??= _make(class_);

  Level _make(ClassElement class_) {
    final superclass = class_.supertype?.element;
    Level? found = superclass is ClassElement ? of(superclass) : null;
    for (final mixin in class_.mixins) {
      found = Level._(class_, mixin, found);
    }
    return Level._(class_, class_.thisType, found);
  }
}
