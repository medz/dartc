import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';

import 'builder.dart';
import 'closures.dart';
import 'conversions.dart';
import 'members.dart';
import 'native_scope.dart';
import 'native_types.dart';
import 'native_values.dart';
import 'scope.dart';

/// Translates uses of `dart:ffi` that depend on types known when compiling.
final class NativeMembers(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  late final _conversions = Conversions(_scope, _builder);
  late final _values = NativeValues(_scope, _builder);

  NativeScope get _natives => _scope.natives;

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  HirValue _number(int value) => _builder.add(HirConst(value));

  HirValue _truth(bool value) => _builder.add(HirConst(value));

  HirValue _sum(HirValue a, HirValue b) =>
      _builder.add(HirIntBinary(.add, a, b));

  HirValue? _call(String name, List<HirValue> arguments, {HirValue? types}) =>
      _builder.call(HirCall(_scope.runtime(name), [?types, ...arguments]));

  /// The C type that [type] is.
  NativeType _type(AstNode node, DartType type) =>
      _natives.types.of(type) ?? _unsupported(node, 'the C type $type');

  FunctionType _function(AstNode node, DartType? type) => type is FunctionType
      ? type
      : _unsupported(node, 'a C function of type $type');

  HirValue _typeList(AstNode node, DartType type) =>
      _scope.typeList(_builder, [type]) ??
      _unsupported(node, 'these type arguments');

  static DartType _argument(DartType type) =>
      (type as InterfaceType).typeArguments.single;

  static List<DartType> _typeArguments(AstNode node) =>
      node is InvocationExpression
      ? node.typeArgumentTypes ?? const []
      : const [];

  /// The result of calling the static member [element], if this translates it.
  HirValue? invoke(
    InvocationExpression node,
    Element element,
    HirValue Function(Expression argument) valueOf,
  ) {
    final owner = switch (element.enclosingElement) {
      InstanceElement(:final name) => name,
      _ => null,
    };
    switch ((owner, element.name)) {
      case (null, 'sizeOf'):
        return _number(_type(node, _typeArguments(node).single).size);
      case ('Pointer', 'fromFunction'):
        return _fromFunction(node, valueOf);
      case ('Struct' || 'Union', 'create'):
        return _create(node, valueOf);
      case ('Native', 'addressOf'):
        final given = node.argumentList.arguments.single.argumentExpression;
        final found = switch (given) {
          SimpleIdentifier(:final element?) ||
          PrefixedIdentifier(identifier: SimpleIdentifier(:final element?)) ||
          PropertyAccess(propertyName: SimpleIdentifier(:final element?)) =>
            element is ExecutableElement
                ? variableOfAccessor(element) ?? element
                : element,
          _ => null,
        };
        final address = found == null
            ? null
            : _natives.addressOf(_builder, found.baseElement);
        return address == null
            ? _unsupported(node, 'this address')
            : _values.pointer(address, node.staticType!);
    }
    return null;
  }

  /// How Dart has a function of C of type [native].
  FunctionType _ownType(AstNode node, FunctionType native, DartType? given) =>
      given is FunctionType
      ? given
      : _unsupported(node, 'a C function of type $native');

  HirValue _fromFunction(
    InvocationExpression node,
    HirValue Function(Expression argument) valueOf,
  ) {
    final native = _function(node, _typeArguments(node).single);
    final [function, ...rest] = [
      for (final argument in node.argumentList.arguments)
        argument.argumentExpression,
    ];
    final type = _ownType(node, native, function.staticType);
    final address = _natives.staticCallback(
      _builder,
      node,
      (native, type),
      () => valueOf(function),
      () => rest.isEmpty ? null : valueOf(rest.single),
    );
    return address == null
        ? _unsupported(node, 'a C function of type $native')
        : _values.pointer(address, node.staticType!);
  }

  /// Creates an object of `NativeCallable` with the constructor called [name].
  HirValue callable(
    Expression node,
    String? name,
    ArgumentList arguments,
    HirValue Function(Expression argument) valueOf,
  ) {
    final isLater = name == 'listener';
    if (!isLater && name != 'isolateLocal') _unsupported(node, 'this callable');
    final native = _function(node, _argument(node.staticType!));
    Expression? function, exceptional;
    for (final argument in arguments.arguments) {
      if (argument is NamedArgument) {
        exceptional = argument.argumentExpression;
      } else {
        function = argument.argumentExpression;
      }
    }
    final type = _ownType(node, native, function!.staticType);
    return _natives.callable(
          _builder,
          (native, type),
          valueOf(function),
          exceptional: exceptional == null ? null : valueOf(exceptional),
          isLater: isLater,
        ) ??
        _unsupported(node, 'a C function of type $native');
  }

  HirValue _create(
    InvocationExpression node,
    HirValue Function(Expression argument) valueOf,
  ) {
    final type = node.staticType!, size = _type(node, type).size;
    final arguments = node.argumentList.arguments;
    if (arguments.isEmpty) {
      return _values.wrap(_values.newMemory(_type(node, type)), type);
    }
    final data = valueOf(arguments.first.argumentExpression);
    final offset = arguments.length > 1
        ? valueOf(arguments[1].argumentExpression)
        : _number(0);
    final start = _call('checkData', [data, offset, _number(size)])!;
    return _values.wrap(data, type, start);
  }

  /// Uses the member [element] of an extension on [receiver], of a type, if
  /// this translates it.
  ({HirValue? result})? use(
    AstNode node,
    (HirValue, DartType) receiver,
    ExecutableElement element,
    List<HirValue> positional,
  ) {
    final (value, type) = receiver;
    final name = element.lookupName!;
    switch (element.enclosingElement?.name) {
      case 'NativeFunctionPointer':
        final native = _function(node, _argument(_argument(type)));
        final own = _function(node, (node as Expression).staticType);
        final address = _call('pointerAddress', [value])!;
        return (result: _asFunction(node, address, native, own));
      case 'DynamicLibraryExtension':
        final [native, own] = _typeArguments(node);
        final symbol = _call('lookupAddress', [value, positional.first])!;
        final function = _asFunction(
          node,
          symbol,
          _function(node, native),
          _function(node, own),
        );
        return (result: function);
      case 'AllocatorAlloc':
        final own = _typeArguments(node).single;
        final count = positional.firstOrNull ?? _number(1);
        final size = _number(_type(node, own).size);
        final bytes = _builder.add(HirIntBinary(.multiply, size, count));
        final types = _typeList(node, own);
        return (result: _call('allocateWith', [value, bytes], types: types));
      case 'StructPointer' || 'UnionPointer' || 'AbiSpecificIntegerPointer':
        return _usePointer(node, value, type, name, positional);
      case 'StructArray' || 'UnionArray' || 'AbiSpecificIntegerArray':
        return _useArray(node, value, _argument(type), name, positional);
      case 'ArrayArray':
        return _useArrays(node, value, _argument(type), name, positional);
      case final owner? when owner.endsWith('Address'):
        return _useAddress(node, value, type, owner);
    }
    return null;
  }

  HirValue _asFunction(
    AstNode node,
    HirValue address,
    FunctionType native,
    FunctionType type,
  ) =>
      _natives.function(
        _builder,
        address,
        native,
        type,
        ClosureTranslator.outerName(node),
      ) ??
      _unsupported(node, 'a C function of type $native');

  ({HirValue? result}) _usePointer(
    AstNode node,
    HirValue value,
    DartType type,
    String name,
    List<HirValue> positional,
  ) {
    final element = _argument(type), native = _type(node, element);
    HirValue offset(HirValue index) =>
        _builder.add(HirIntBinary(.multiply, index, _number(native.size)));
    HirValue address() => _call('pointerAddress', [value])!;
    switch (name) {
      case 'ref' || 'value':
        return (result: _load(value, _number(0), native, element));
      case 'ref=' || 'value=':
        _store(value, _number(0), native, positional.single);
      case '[]':
        final at = offset(positional.single);
        return (result: _load(value, at, native, element));
      case '[]=':
        final [index, given] = positional;
        _store(value, offset(index), native, given);
      case '+' || 'elementAt':
        final to = _sum(address(), offset(positional.single));
        return (result: _values.pointer(to, type));
      case '-':
        final to = _builder.add(
          HirIntBinary(.subtract, address(), offset(positional.single)),
        );
        return (result: _values.pointer(to, type));
      default:
        _unsupported(node, name);
    }
    return (result: null);
  }

  /// What is [offset] bytes after [base].
  HirValue _load(
    HirValue base,
    HirValue offset,
    NativeType native,
    DartType type,
  ) => native is NativeCompound
      ? _values.wrap(base, type, offset)
      : _values.loadScalar(
          _sum(_values.addressOf(base), offset),
          native,
          _conversions.types.intType,
        );

  void _store(
    HirValue base,
    HirValue offset,
    NativeType native,
    HirValue value,
  ) {
    if (native is NativeCompound) {
      _call('assignCompound', [base, offset, value, _number(native.size)]);
    } else {
      final at = _sum(_values.addressOf(base), offset);
      _values.storeScalar(at, native, _conversions.coerce(value, .integer));
    }
  }

  ({HirValue? result}) _useArray(
    AstNode node,
    HirValue array,
    DartType element,
    String name,
    List<HirValue> positional,
  ) {
    final native = _type(node, element), size = _number(native.size);
    HirValue base() => _call('baseOf', [array])!;
    HirValue offset() =>
        _call('elementOffset', [array, positional.first, size])!;
    switch (name) {
      case '[]':
        final at = offset();
        return (result: _load(base(), at, native, element));
      case '[]=':
        final at = offset();
        _store(base(), at, native, positional.last);
        return (result: null);
      case 'elements' when native is NativeInteger:
        final isSigned = _truth(native.isSigned);
        return (result: _call('integersOf', [array, size, isSigned]));
      case 'elements':
        final make = _natives.maker(_builder, element);
        final types = _typeList(node, element);
        return (
          result: _call('compoundsOf', [array, size, make], types: types),
        );
      default:
        _unsupported(node, name);
    }
  }

  ({HirValue? result}) _useArrays(
    AstNode node,
    HirValue array,
    DartType inner,
    String name,
    List<HirValue> positional,
  ) {
    var element = inner;
    while (element is InterfaceType &&
        NativeTypes.isFfi(element.element) &&
        element.element.name == 'Array') {
      element = element.typeArguments.single;
    }
    final size = _number(_type(node, element).size);
    final types = _typeList(node, _argument(inner));
    switch (name) {
      case '[]':
        return (
          result: _call('innerArray', [
            array,
            ...positional,
            size,
          ], types: types),
        );
      case '[]=':
        _call('setInnerArray', [array, ...positional, size], types: types);
        return (result: null);
      case 'elements':
        return (result: _call('innerArrays', [array, size], types: types));
      default:
        _unsupported(node, name);
    }
  }

  ({HirValue? result}) _useAddress(
    AstNode node,
    HirValue value,
    DartType type,
    String owner,
  ) {
    if (const ['IntAddress', 'DoubleAddress', 'BoolAddress'].contains(owner)) {
      _unsupported(node, 'the address of a field');
    }
    final types = _typeList(node, _argument((node as Expression).staticType!));
    return (result: _call('pointerTo', [value], types: types));
  }
}
