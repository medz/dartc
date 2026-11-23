import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builtin_error.dart';
import 'classes.dart';
import 'closure.dart';
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
) {
  final _tests = <HirTypeTest, Set<HirClass>>{};
  final _exact = <ClassElement, HirTypeTest>{};

  /// Writes the name of the class of an object, if needed.
  HirFunction? describe;
  final _blocks = <HirBlock>[];

  /// The classes that pass the tests made here.
  Map<HirTypeTest, Set<HirClass>> get tests => _tests;

  /// A function reporting objects of any of [classes] that can be thrown.
  HirFunction build(
    Iterable<ClassElement> classes,
    Iterable<Closure> closures,
  ) {
    if (_errors.castTexts.isNotEmpty) {
      describe = _makeDescribe(classes, closures);
    }
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
        case null:
          _end(yes, '${_text(class_)}\n');
        case .nullCheck || .wrongType:
          _typeError(yes, exception, class_);
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
    for (final (i, text) in _errors.castTexts.indexed) {
      block = _caseOf(block, number, i + 1, (yes) {
        final field = _classes.classOf(class_).fields.last;
        _write(yes, BuiltinError.wrongType.text);
        yes.add(HirCall(describe!, [yes.add(HirLoad(field, exception))]));
        _end(yes, '$text\n');
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

  /// Makes a function that writes the name of the class of an object.
  HirFunction _makeDescribe(
    Iterable<ClassElement> classes,
    Iterable<Closure> closures,
  ) {
    var block = HirBlock([.reference]);
    final object = block.parameters.single;
    final start = _blocks.length;
    _blocks.add(block);
    final isNull = block.add(HirCompare(.equal, object, block.add(HirNull())));
    final (none, some) = _branch(block, isNull);
    _end(none, 'Null');
    block = some;
    for (final class_ in classes) {
      final test = _exactly(class_);
      final (yes, no) = _branch(block, block.add(HirIsInstance(test, object)));
      _end(yes, class_.displayName);
      block = no;
    }
    for (final Closure(:class_, :type) in closures) {
      final test = HirTypeTest(class_.name);
      _tests[test] = {class_};
      final (yes, no) = _branch(block, block.add(HirIsInstance(test, object)));
      _end(yes, describeType(type));
      block = no;
    }
    block.end(HirUnreachable());
    final function = HirFunction('describe', [.reference], null, false)
      ..define(_blocks.skip(start));
    _blocks.removeRange(start, _blocks.length);
    return function;
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
