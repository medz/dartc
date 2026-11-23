import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builtin_error.dart';
import 'classes.dart';
import 'constant.dart';
import 'error_table.dart';
import 'members.dart';
import 'types.dart';

/// Makes the function that reports what nothing catches.
final class ReportBuilder(
  final Declarations _declarations,
  final ClassTable _classes,
  final ErrorTable _errors,

  /// The static classes of the objects that programs throw.
  final Set<ClassElement> _thrown,

  /// Writes a number to standard error.
  final HirFunction? _writeNumber,

  /// A function of the runtime.
  final HirFunction Function(String name) _runtime,
) {
  final _tests = <HirTypeTest, Set<HirClass>>{};
  final _exact = <ClassElement, HirTypeTest>{};
  final _blocks = <HirBlock>[];

  /// The classes that pass the tests made here.
  Map<HirTypeTest, Set<HirClass>> get tests => _tests;

  /// A function reporting objects of any of [classes] that can be thrown.
  HirFunction build(Iterable<ClassElement> classes) {
    var block = HirBlock([.reference]);
    final exception = block.parameters.single;
    _blocks.add(block);
    _write(block, 'Unhandled exception:\n');
    for (final class_ in classes) {
      final error = _errors.builtin(class_);
      if (error == null && !_thrown.any((t) => isSubclass(class_, t))) continue;
      final isThis = block.add(HirIsInstance(_exactly(class_), exception));
      final (yes, no) = _branch(block, isThis);
      switch (error) {
        case null when class_.library.isInSdk:
          _plain(yes, exception, class_);
        case null when class_.typeParameters.isNotEmpty:
          _generic(yes, exception, class_);
        case null:
          _end(yes, '${_text(class_)}\n');
        case .nullCheck || .wrongType:
          _typeError(yes, exception, class_);
        case .missingMember:
          _missing(yes, exception, class_);
        case .late:
          _late(yes, exception, class_);
        case .negativeShift:
          _write(yes, error.text);
          if (_writeNumber case final write?) {
            yes.add(HirCall(write, [_field(yes, exception, class_)]));
          }
          _end(yes, '\n');
        default:
          _end(yes, '${error.text}\n');
      }
      block = no;
    }
    block.end(HirUnreachable());
    return HirFunction('report', [.reference], null, false)..define(_blocks);
  }

  (HirBlock, HirBlock) _branch(HirBlock block, HirValue condition) {
    final yes = HirBlock(), no = HirBlock();
    _blocks.addAll([yes, no]);
    block.end(HirBranch(condition, HirEdge(yes), HirEdge(no)));
    return (yes, no);
  }

  void _write(HirBlock block, String text) => block.add(HirWriteError(text));

  void _end(HirBlock block, String text) {
    _write(block, text);
    block.end(HirReturn());
  }

  /// An object whose class has type parameters.
  void _generic(HirBlock block, HirValue exception, ClassElement class_) {
    final text = _text(class_);
    final instance = "Instance of '${class_.displayName}'";
    if (text != instance) return _end(block, '$text\n');
    _write(block, "Instance of '");
    _call(block, 'writeObjectType', exception);
    _end(block, "'\n");
  }

  /// Calls the function [name] of the runtime.
  void _call(HirBlock block, String name, HirValue argument) =>
      block.add(HirCall(_runtime(name), [argument]));

  HirValue _field(HirBlock block, HirValue object, ClassElement class_) =>
      block.add(HirLoad(_classes.classOf(class_).fields.first, object));

  /// A number or a stack trace.
  ///
  /// Doubles and traces, which are no use as exceptions, have no text yet.
  void _plain(HirBlock block, HirValue exception, ClassElement class_) {
    switch (class_.name) {
      case 'int':
        if (_writeNumber case final write?) {
          block.add(HirCall(write, [_field(block, exception, class_)]));
        }
        _end(block, '\n');
      case 'bool':
        final (yes, no) = _branch(block, _field(block, exception, class_));
        _end(yes, 'true\n');
        _end(no, 'false\n');
      default:
        _end(block, '\n');
    }
  }

  /// A null check or a value of a wrong type.
  void _typeError(HirBlock start, HirValue exception, ClassElement class_) {
    final number = _field(start, exception, class_);
    var block = _caseOf(start, number, 0, (yes) {
      _end(yes, '${BuiltinError.nullCheck.text}\n');
    });
    final [_, object, type] = _classes.classOf(class_).fields;
    for (final (i, (name, ending)) in _errors.castTexts.indexed) {
      block = _caseOf(block, number, i + 1, (yes) {
        _write(yes, BuiltinError.wrongType.text);
        _call(yes, 'writeObjectType', yes.add(HirLoad(object, exception)));
        _write(yes, "' is not a subtype of type '");
        if (name == null) {
          _call(yes, 'writeType', yes.add(HirLoad(type, exception)));
        } else {
          _write(yes, name);
        }
        _end(yes, "'$ending\n");
      });
    }
    block.end(HirUnreachable());
  }

  /// A member that an object has not. Its arguments have no text yet.
  void _missing(HirBlock start, HirValue exception, ClassElement class_) {
    final [number, object, _] = _classes.classOf(class_).fields;
    final which = start.add(HirLoad(number, exception));
    final value = start.add(HirLoad(object, exception));
    _write(start, BuiltinError.missingMember.text);
    var block = start;
    for (final (i, (kind, name)) in _errors.missing.indexed) {
      block = _caseOf(block, which, i, (yes) {
        final isNull = yes.add(HirCompare(.equal, value, yes.add(HirNull())));
        final (none, some) = _branch(yes, isNull);
        _end(none, "The $kind '$name' was called on null.\n");
        _write(some, "Class '");
        _call(some, 'writeObjectType', value);
        _end(some, "' has no instance $kind '$name'.\n");
      });
    }
    block.end(HirUnreachable());
  }

  /// Does [work] where [number] is [value]. Returns where it is not.
  HirBlock _caseOf(
    HirBlock block,
    HirValue number,
    int value,
    void Function(HirBlock yes) work,
  ) {
    final same = block.add(
      HirCompare(.equal, number, block.add(HirConst(value))),
    );
    final (yes, no) = _branch(block, same);
    work(yes);
    return no;
  }

  /// A test for objects of [class_] itself.
  HirTypeTest _exactly(ClassElement class_) => _exact[class_] ??= () {
    final test = HirTypeTest('exactly ${class_.displayName}');
    _tests[test] = {_classes.classOf(class_)};
    return test;
  }();

  void _late(HirBlock start, HirValue exception, ClassElement class_) {
    final number = _field(start, exception, class_);
    var block = start;
    for (final (i, name) in _errors.lateNames.indexed) {
      block = _caseOf(block, number, i, (yes) {
        _end(
          yes,
          '${BuiltinError.late.text}Field \'$name\' '
          'has been assigned during initialization.\n',
        );
      });
    }
    block.end(HirUnreachable());
  }

  /// What `toString` gives for objects of [class_].
  String _text(ClassElement class_) {
    final object = class_.library.typeProvider.objectElement;
    final member = object.getMethod('toString')!;
    final found = implementationIn(class_, member)!;
    if (found.library.isInSdk) return "Instance of '${class_.displayName}'";
    return switch (_declarations[found]?.$2) {
          MethodDeclaration(
            body: ExpressionFunctionBody(:final expression) ||
                BlockFunctionBody(
                  block: Block(
                    statements: [ReturnStatement(:final expression?)],
                  ),
                ),
          ) =>
            constantText(expression.unParenthesized),
          _ => null,
        } ??
        (throw _declarations.unsupported(
          found,
          'throwing an object with this toString',
        ));
  }
}
