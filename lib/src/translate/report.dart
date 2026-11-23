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
) {
  final _tests = <HirTypeTest, Set<HirClass>>{};
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
      final test = HirTypeTest('exactly ${class_.displayName}');
      _tests[test] = {_classes.classOf(class_)};
      final isThis = block.add(HirIsInstance(test, exception));
      final (yes, no) = _branch(block, isThis);
      switch (error) {
        case null:
          _end(yes, '${_text(class_)}\n');
        case .late:
          _late(yes, exception, class_);
        case .negativeShift:
          _write(yes, error.text);
          if (_writeNumber case final write?) {
            yes.add(HirCall(write, [_number(yes, exception, class_)]));
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

  HirValue _number(HirBlock block, HirValue object, ClassElement class_) =>
      block.add(HirLoad(_classes.classOf(class_).fields.single, object));

  void _late(HirBlock start, HirValue exception, ClassElement class_) {
    final number = _number(start, exception, class_);
    var block = start;
    for (final (i, name) in _errors.lateNames.indexed) {
      final same = block.add(
        HirCompare(.equal, number, block.add(HirConst(i))),
      );
      final (yes, no) = _branch(block, same);
      _end(
        yes,
        '${BuiltinError.late.text}Field \'$name\' '
        'has been assigned during initialization.\n',
      );
      block = no;
    }
    block.end(HirUnreachable());
  }

  /// What `toString` gives for objects of [class_].
  String _text(ClassElement class_) {
    // Traces are no use as exceptions; they have no text yet.
    if (class_.library.isInSdk) return '';
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
