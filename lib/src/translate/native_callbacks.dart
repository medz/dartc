import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

import 'builder.dart';
import 'closure.dart';
import 'conversions.dart';
import 'native_values.dart';
import 'scope.dart';
import 'types.dart';

/// What a function of C that a program makes does.
typedef NativeCallback = ({
  /// The function that it calls.
  HirValue function,

  /// What it gives if that throws, if it gives anything. A function that is
  /// called later lets that happen.
  HirValue? exceptional,
  bool isLater,
});

/// Makes functions of C that call functions of programs.
final class NativeCallbackTable(
  final ProgramScope _scope,
  final SourceUnit _unit,
) {
  /// A function of the runtime that does what [callback] does for functions of
  /// C of [signature], which is of [type] in Dart.
  HirValue create(
    FunctionBuilder builder,
    NativeSignature signature,
    FunctionType type,
    NativeCallback callback,
  ) {
    _scope.addCallbacks();
    final (:function, :exceptional, :isLater) = callback;
    final target = HirField('function', .reference);
    final other = HirField('exceptional', .reference);
    final class_ = HirClass('callback ${describeType(type)}', null, [
      target,
      other,
    ]);
    final body = HirFunction(class_.name, const [
      .reference,
      .integer,
      .integer,
    ], .reference);
    final declared = _scope.runtimeFunctionType('Callback');
    _scope
      ..addLocalFunction(body)
      ..addClosure(
        Closure(
          class_,
          declared,
          declared.formalParameters,
          () => body,
          (_, self) => [self],
          typeValue: (builder) => _scope.typeValue(builder, declared)!,
        ),
      );
    final own = FunctionBuilder(_unit, body, const []);
    final [self, ..._] = own.inputs;
    _define(
      own,
      signature,
      type,
      own.add(HirLoad(target, self)),
      exceptional == null || isLater
          ? null
          : () => own.add(HirLoad(other, self)),
      isLater: isLater,
    );
    final object = builder.create(class_);
    builder
      ..add(HirStore(target, object, function))
      ..add(
        HirStore(
          other,
          object,
          exceptional == null
              ? builder.add(HirNull())
              : Conversions(_scope, builder).coerce(exceptional, .reference),
        ),
      );
    return object;
  }

  void _define(
    FunctionBuilder builder,
    NativeSignature signature,
    FunctionType type,
    HirValue function,
    HirValue Function()? exceptional, {
    required bool isLater,
  }) {
    final passing = _scope.natives.types.passing(signature);
    final values = NativeValues(_scope, builder);
    final conversions = Conversions(_scope, builder);
    final [_, block, stack] = builder.inputs;
    final result = signature.result;
    void finish(HirValue? value) {
      if (value != null && result is! NativeVoid && !isLater) {
        values.storeResult(block, passing.result, result, value);
      }
      builder.end(HirReturn(builder.add(HirNull())));
    }

    void work() {
      final arguments = [
        for (final (i, native) in signature.parameters.indexed)
          conversions.coerce(
            values.load(
              block,
              passing.parameters[i],
              native,
              type.formalParameters[i].type,
              stack: stack,
            ),
            .reference,
          ),
      ];
      final selector = _scope.callSelector(0, arguments.length, const []);
      final given = builder.call(
        HirVirtualCall(selector, function, arguments),
      )!;
      finish(
        result is NativeVoid
            ? null
            : conversions.coerce(given, valueType(type.returnType)!),
      );
    }

    if (isLater) {
      work();
    } else {
      final caught = builder.handler();
      builder
        ..within(caught, work)
        ..enter(caught);
      final value = exceptional?.call();
      finish(
        value == null
            ? null
            : conversions.coerce(value, valueType(type.returnType)!),
      );
    }
    builder.finish();
  }
}
