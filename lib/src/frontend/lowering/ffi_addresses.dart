import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'ffi.dart';
import 'function_context.dart';

/// Borrows storage for one leaf call without materializing Dart pointer objects.
final class FfiAddressArguments(
  final FunctionContext context,
  final Value? Function(ast.Expression) evaluate,
) {
  static bool containsAddress(ast.ArgumentList arguments) => arguments.arguments
      .any((argument) => _address(argument.argumentExpression) != null);

  static (GetterElement, ast.Expression)? _address(ast.Expression expression) {
    while (expression is ast.ParenthesizedExpression) {
      expression = expression.expression;
    }
    if (expression
        case ast.MethodInvocation(
          methodName: ast.SimpleIdentifier(element: final MethodElement method),
          target: final receiver?,
        )
        when isPointerCast(method)) {
      expression = receiver;
    }
    final (member, receiver) = switch (expression) {
      ast.PrefixedIdentifier(:final prefix, :final identifier) => (
        identifier.element,
        prefix,
      ),
      ast.PropertyAccess(:final target, :final propertyName) => (
        propertyName.element,
        target,
      ),
      _ => (null, null),
    };
    if (member is! GetterElement ||
        receiver == null ||
        member.library.uri != Uri.parse('dart:ffi')) {
      return null;
    }
    for (final name in const [
      'StructAddress',
      'UnionAddress',
      'ArrayAddress',
      'IntAddress',
      'DoubleAddress',
      'BoolAddress',
      'Int8ListAddress',
      'Int16ListAddress',
      'Int32ListAddress',
      'Int64ListAddress',
      'Uint8ListAddress',
      'Uint16ListAddress',
      'Uint32ListAddress',
      'Uint64ListAddress',
      'Float32ListAddress',
      'Float64ListAddress',
    ]) {
      if (member.baseElement ==
          member.library.getExtension(name)?.getGetter('address')) {
        return (
          member,
          receiver is ast.ExtensionOverride
              ? receiver.argumentList.arguments.single.argumentExpression
              : receiver,
        );
      }
    }
    return null;
  }

  /// Evaluates source operands once, then extracts addresses immediately before calling.
  Value? call(
    NativeReference reference,
    FunctionType signature,
    ast.ArgumentList arguments,
  ) {
    final values = <Value Function()>[];
    final owners = <int, Value>{};
    for (final argument in arguments.arguments) {
      final source = argument.argumentExpression;
      final address = _address(source);
      if (address == null) {
        final input = evaluate(source);
        if (input == null) return null;
        final value = context.normal(
          context.convert(
            input,
            context.typeOf(argument.correspondingParameter!.type, source),
          ),
        );
        if (value == null) return null;
        values.add(() => value);
      } else {
        final borrowed = _borrow(address.$1, address.$2);
        if (borrowed == null) return null;
        owners[values.length] = borrowed.owner;
        values.add(borrowed.address);
      }
    }
    final pointer = NativeSymbolAddress(reference);
    context.emit(pointer);
    final inputs = [for (final value in values) value()];
    return context.emit(
      NativeCall.symbol(pointer, signature, inputs, borrowedOwners: owners),
    );
  }

  Value _helper(LibraryElement library, String name, List<Value> arguments) =>
      context.emit(
        DirectCall(
          context.bindings.target(
            library.getTopLevelFunction(name)!,
            context.unit,
            context.unit.unit,
          ),
          arguments,
        ),
      );

  dart.DartType _bound(dart.DartType type) {
    while (type is dart.TypeParameterType) {
      type = type.bound;
    }
    return type;
  }

  Value? _owner(ast.Expression expression) {
    final value = evaluate(expression);
    if (value == null) return null;
    final type = context.typeOf(_bound(expression.staticType!), expression);
    return value.type == type ? value : context.emit(TypeView(value, type));
  }

  ({Value owner, Value Function() address})? _borrow(
    GetterElement getter,
    ast.Expression receiver,
  ) {
    final library = getter.library;
    final primitive = ['IntAddress', 'DoubleAddress', 'BoolAddress'].any(
      (name) =>
          getter.baseElement ==
          library.getExtension(name)?.getGetter('address'),
    );
    if (primitive) {
      if (receiver case ast.IndexExpression(
        target: final target?,
        :final index,
      )) {
        final owner = _owner(target);
        if (owner == null) return null;
        final input = evaluate(index);
        if (input == null) return null;
        final offset = context.normal(context.convert(input, .integer));
        if (offset == null) return null;
        if (_bound(target.staticType!) case dart.InterfaceType(:final element)
            when element == library.getClass('Array')) {
          return (
            owner: owner,
            address: () =>
                _helper(library, '_arrayElementAddress', [owner, offset]),
          );
        }
        return (
          owner: owner,
          address: () => _listAddress(library, owner, offset),
        );
      }
      final (member, target) = switch (receiver) {
        ast.PrefixedIdentifier(:final prefix, :final identifier) => (
          identifier.element,
          prefix,
        ),
        ast.PropertyAccess(:final target, :final propertyName) => (
          propertyName.element,
          target,
        ),
        _ => (null, null),
      };
      if (member is GetterElement && target != null) {
        final owner = _owner(target);
        if (owner == null) return null;
        final type = owner.type as ClassType;
        final index = nativeFieldIndex(member, type);
        if (index != null) {
          return (
            owner: owner,
            address: () => context.emit(
              IntBinary(
                .add,
                context.emit(NativeAddress(owner)),
                context.emit(
                  NativeFieldOffset(
                    type.nativeType as NativeCompoundType,
                    index,
                  ),
                ),
              ),
            ),
          );
        }
      }
      unsupported(context.unit, receiver, 'address of native scalar storage');
    }
    final owner = _owner(receiver);
    if (owner == null) return null;
    if (FfiTypes.isCompound(owner.type)) {
      return (owner: owner, address: () => context.emit(NativeAddress(owner)));
    }
    if (getter.baseElement ==
        library.getExtension('ArrayAddress')?.getGetter('address')) {
      return (
        owner: owner,
        address: () => _helper(library, '_arrayStart', [owner]),
      );
    }
    return (
      owner: owner,
      address: () => _listAddress(library, owner, const Constant.integer(0)),
    );
  }

  Value _listAddress(LibraryElement ffi, Value owner, Value index) {
    final library = ffi.fragments
        .expand((f) => f.importedLibraries)
        .firstWhere((l) => l.uri == Uri.parse('dart:typed_data'));
    return _helper(library, '_nativeListAddress', [owner, index]);
  }
}
