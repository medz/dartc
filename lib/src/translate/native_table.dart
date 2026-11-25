import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'native_callbacks.dart';
import 'conversions.dart';
import 'members.dart';
import 'native_calls.dart';
import 'native_fields.dart';
import 'native_scope.dart';
import 'native_types.dart';
import 'native_values.dart';
import 'scope.dart';
import 'types.dart';

/// The functions of C that a program calls.
final class NativeTable(final ProgramScope _scope, final SourceUnit _unit)
    implements NativeScope {
  @override
  late final types = NativeTypes(_scope.target);
  final _counts = <String, int>{};
  final _addresses = <Element, HirGlobal>{};

  /// Where the addresses of functions are kept.
  Iterable<HirGlobal> get globals => [..._addresses.values, ..._made.values];

  @override
  HirValue? function(
    FunctionBuilder builder,
    HirValue address,
    FunctionType native,
    FunctionType type,
    String owner,
  ) {
    final signature = types.signature(native);
    if (signature == null || parameterTypes(type) == null) return null;
    final number = _counts.update(owner, (n) => n + 1, ifAbsent: () => 0);
    final name = '$owner.#ffiClosure$number';
    final (class_, field) = _make(signature, type, name);
    final object = builder.create(class_);
    builder.add(HirStore(field, object, address));
    return object;
  }

  (HirClass, HirField) _make(
    NativeSignature signature,
    FunctionType type,
    String name,
  ) {
    final address = HirField('address', .integer);
    final class_ = HirClass('C ${describeType(type)}', null, [address]);
    final function = HirFunction('call C ${describeType(type)}', [
      .reference,
      ...parameterTypes(type)!,
    ], valueType(type.returnType));
    _scope
      ..addLocalFunction(function)
      ..addClosure(
        Closure(
          class_,
          type.formalParameters,
          () => function,
          (_, self) => [self],
          typeValue: (builder) => _scope.typeValue(builder, type)!,
          name: name,
          parameterName: (index) => 'arg${index + 1}',
        ),
      );
    final builder = FunctionBuilder(_unit, function, const []);
    final [self, ...arguments] = builder.inputs;
    NativeCalls(
      _scope,
      builder,
    ).forward(builder.add(HirLoad(address, self)), signature, arguments, type);
    builder.finish();
    return (class_, address);
  }

  late final _callbacks = NativeCallbackTable(_scope, _unit);
  final _made = <Object, HirGlobal>{};

  @override
  HirValue? staticCallback(
    FunctionBuilder builder,
    Object key,
    (FunctionType native, FunctionType type) types,
    HirValue Function() function,
    HirValue? Function() exceptional,
  ) {
    final (native, type) = types;
    final signature = this.types.signature(native);
    if (signature == null) return null;
    final global = _made[key] ??= HirGlobal('callback', .integer, 0);
    final known = builder.add(HirLoadGlobal(global));
    final zero = builder.add(HirConst(0));
    return builder.choose(
      builder.add(HirCompare(.notEqual, known, zero)),
      .integer,
      () => known,
      () {
        final callback = _callbacks.create(builder, signature, type, (
          function: function(),
          exceptional: exceptional(),
          isLater: false,
        ));
        final made = builder.call(
          HirCall(_scope.runtime('staticCallback'), [
            callback,
            builder.add(HirConst(this.types.passing(signature).stackBytes)),
          ]),
        )!;
        builder.add(HirStoreGlobal(global, made));
        return made;
      },
    );
  }

  @override
  HirValue? callable(
    FunctionBuilder builder,
    (FunctionType native, FunctionType type) types,
    HirValue function, {
    HirValue? exceptional,
    required bool isLater,
  }) {
    final (native, type) = types;
    final signature = this.types.signature(native);
    final list = _scope.typeList(builder, [native]);
    if (signature == null || list == null) return null;
    final callback = _callbacks.create(builder, signature, type, (
      function: function,
      exceptional: exceptional,
      isLater: isLater,
    ));
    final name = isLater ? 'listeningCallable' : 'localCallable';
    return builder.call(
      HirCall(_scope.runtime(name), [
        list,
        callback,
        builder.add(HirConst(this.types.passing(signature).stackBytes)),
      ]),
    );
  }

  @override
  bool define(FunctionBuilder builder, ExecutableElement element) {
    final variable = variableOfAccessor(element);
    if (variable != null) return _defineAccessor(builder, variable);
    final annotation = nativeAnnotation(element);
    final native = nativeTypeOf(element);
    if (annotation == null || native is! FunctionType) return false;
    final signature = types.signature(native);
    if (signature == null) return false;
    final address = addressOf(builder, element)!;
    NativeCalls(
      _scope,
      builder,
    ).forward(address, signature, builder.inputs, element.type);
    return true;
  }

  /// Reads [variable], or writes it if the function takes a value.
  bool _defineAccessor(
    FunctionBuilder builder,
    PropertyInducingElement variable,
  ) {
    final address = addressOf(builder, variable);
    final field = types.variable(variable);
    if (address == null || field == null) return false;
    final never = variable.library.typeProvider.neverType;
    final pointer = NativeValues(_scope, builder).pointer(address, never);
    final fields = NativeFields(_scope, builder);
    if (builder.inputs case [final value]) {
      fields.store(field, pointer, value);
      builder.end(HirReturn(builder.add(HirNull())));
    } else {
      final value = fields.load(field, pointer, isPointer: true);
      final type = builder.function.result!;
      builder.end(HirReturn(Conversions(_scope, builder).coerce(value, type)));
    }
    return true;
  }

  @override
  HirValue? addressOf(FunctionBuilder builder, Element element) {
    final annotation = nativeAnnotation(element);
    if (annotation == null) return null;
    final (:symbol, :asset) = annotation;
    // What the SDK declares is there from the start.
    if (element.library!.isInSdk) {
      return builder.add(HirNativeFunction(symbol));
    }
    final global = _addresses[element] ??= HirGlobal(
      'address of $symbol',
      .integer,
      0,
    );
    final known = builder.add(HirLoadGlobal(global));
    final zero = builder.add(HirConst(0));
    return builder.choose(
      builder.add(HirCompare(.notEqual, known, zero)),
      .integer,
      () => known,
      () {
        final found = builder.call(
          HirCall(_scope.runtime('resolveNative'), [
            builder.add(_scope.text(symbol)),
            builder.add(_scope.text(asset)),
          ]),
        )!;
        builder.add(HirStoreGlobal(global, found));
        return found;
      },
    );
  }

  final _makers = <InterfaceElement, HirClass>{};

  @override
  HirValue maker(FunctionBuilder builder, DartType type) {
    final element = (type as InterfaceType).element;
    final class_ = _makers[element] ??= _makeMaker(element);
    return builder.add(HirStatic(HirConstObject(class_, const {})));
  }

  HirClass _makeMaker(InterfaceElement element) {
    final type = element.thisType;
    final class_ = HirClass('make ${element.displayName}', null, const []);
    final function = HirFunction(class_.name, const [
      .reference,
      .reference,
      .integer,
    ], .reference);
    final declared = _scope.runtimeFunctionType('MakeCompound');
    _scope
      ..addLocalFunction(function)
      ..addClosure(
        Closure(
          class_,
          declared.formalParameters,
          () => function,
          (_, self) => [self],
          typeValue: (builder) => _scope.typeValue(builder, declared)!,
        ),
      );
    final builder = FunctionBuilder(_unit, function, const []);
    final [_, base, offset] = builder.inputs;
    final made = NativeValues(_scope, builder).wrap(base, type, offset);
    builder
      ..end(HirReturn(made))
      ..finish();
    return class_;
  }
}
