import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

IrProgram objectGraphs() {
  final uri = Uri.parse('memory:objects');
  final base = ClassType(.parse('memory:base'), 'Base');
  final point = ClassType(uri, 'Point', superclass: base);
  final x = InstanceField(base, '_value', .integer, isFinal: true);
  final y = InstanceField(point, '_value', .floating, isFinal: true);
  final flag = InstanceField(point, 'flag', .boolean, isFinal: true);
  final a = ObjectConstant(point, {
    x: const .integer(40),
    y: const .floating(2.5),
    flag: const .boolean(true),
  });
  final b = ObjectConstant(point, {
    x: const .integer(-7),
    y: const .floating(-0.0),
    flag: const .boolean(false),
  });
  final parameter = TypeParameterType('T')
    ..initializeBound(ValueType.object.nullable)
    ..initializeDefaultType(.dynamicType);
  final box = ClassType(uri, 'Box', typeParameters: [parameter]);
  final item = InstanceField(box, 'item', parameter, isFinal: true);
  final boxed = ObjectConstant(box.instantiate([point]), {item: a});
  final functions = <IrFunction>[];
  final touch = FunctionTarget(uri, 'touch', .integer, []);
  final identity = FunctionTarget(
    uri,
    'identity',
    point,
    [],
    owner: point,
    kind: .method,
  );
  final identityBody = Block(identity.parameterTypes);
  identityBody.finish(Return(identityBody.parameters.single));
  functions.add(IrFunction(identity, [identityBody]));

  final choice = FunctionTarget(uri, 'choice', point, [.integer]);
  final choose = Block(choice.parameterTypes), join = Block([point]);
  final positive = choose.emit(
    IntBinary(
      .greaterThan,
      choose.parameters.single,
      const Constant.integer(0),
    ),
  );
  choose.finish(Branch(positive, Jump(join, [a]), Jump(join, [b])));
  join.finish(Return(join.parameters.single));
  functions.add(IrFunction(choice, [choose, join]));

  final integer = FunctionTarget(uri, 'integer_field', .integer, [.integer]);
  final body = Block(integer.parameterTypes);
  final selected = body.emit(DirectCall(choice, body.parameters));
  final touched = body.emit(DirectCall(touch, []));
  body.emit(DirectCall(identity, [a]));
  final view = body.emit(TypeView(selected, base));
  body.finish(
    Return(body.emit(IntBinary(.add, body.emit(LoadField(x, view)), touched))),
  );
  functions.add(IrFunction(integer, [body]));

  final floating = FunctionTarget(uri, 'double_field', .floating, [.integer]);
  final floatBody = Block(floating.parameterTypes);
  final chosen = floatBody.emit(DirectCall(choice, floatBody.parameters));
  floatBody.finish(Return(floatBody.emit(LoadField(y, chosen))));
  functions.add(IrFunction(floating, [floatBody]));

  final boolean = FunctionTarget(uri, 'bool_field', .integer, [.integer]);
  final boolBody = Block(boolean.parameterTypes), yes = Block(), no = Block();
  final instance = boolBody.emit(DirectCall(choice, boolBody.parameters));
  boolBody.finish(
    Branch(boolBody.emit(LoadField(flag, instance)), Jump(yes), Jump(no)),
  );
  yes.finish(Return(const Constant.integer(1)));
  no.finish(Return(const Constant.integer(0)));
  functions.add(IrFunction(boolean, [boolBody, yes, no]));

  final nested = FunctionTarget(uri, 'nested_field', .integer, []);
  final nestedBody = Block();
  final leaf = nestedBody.emit(LoadField(item, boxed));
  nestedBody.finish(Return(nestedBody.emit(LoadField(x, leaf))));
  functions.add(IrFunction(nested, [nestedBody]));

  final many = FunctionTarget(uri, 'many', .integer, List.filled(9, point));
  final manyBody = Block(many.parameterTypes);
  manyBody.emit(DirectCall(identity, [manyBody.parameters.first]));
  Value sum = const Constant.integer(0);
  for (final value in manyBody.parameters) {
    sum = manyBody.emit(
      IntBinary(.add, sum, manyBody.emit(LoadField(x, value))),
    );
  }
  manyBody.finish(Return(sum));
  functions.add(IrFunction(many, [manyBody]));
  final pressure = FunctionTarget(uri, 'stack_references', .integer, []);
  final pressureBody = Block();
  pressureBody.finish(
    Return(
      pressureBody.emit(
        DirectCall(many, [for (var i = 0; i < 9; i++) i.isEven ? a : b]),
      ),
    ),
  );
  functions.add(IrFunction(pressure, [pressureBody]));

  final rotate = FunctionTarget(uri, 'rotate', .integer, [.integer]);
  final start = Block(rotate.parameterTypes),
      loop = Block([point, point, .integer]),
      again = Block(),
      done = Block();
  start.finish(Jump(loop, [a, b, start.parameters.single]));
  final left = loop.parameters[0],
      right = loop.parameters[1],
      count = loop.parameters[2];
  final more = loop.emit(
    IntBinary(.greaterThan, count, const Constant.integer(0)),
  );
  loop.finish(Branch(more, Jump(again), Jump(done)));
  final remaining = again.emit(
    IntBinary(.subtract, count, const Constant.integer(1)),
  );
  again.finish(Jump(loop, [right, left, remaining]));
  done.finish(Return(done.emit(LoadField(x, left))));
  functions.add(IrFunction(rotate, [start, loop, again, done]));

  final nullable = FunctionTarget(uri, 'nullable', point.nullable, [.integer]);
  final nullBody = Block(nullable.parameterTypes),
      nullJoin = Block([point.nullable]);
  final nonzero = nullBody.emit(
    Equals(
      nullBody.parameters.single,
      const Constant.integer(0),
      negated: true,
    ),
  );
  nullBody.finish(
    Branch(
      nonzero,
      Jump(nullJoin, [a]),
      Jump(nullJoin, [const Constant.nullValue()]),
    ),
  );
  nullJoin.finish(Return(nullJoin.parameters.single));
  functions.add(IrFunction(nullable, [nullBody, nullJoin]));
  final checkNull = FunctionTarget(uri, 'check_null', .integer, [.integer]);
  final check = Block(checkNull.parameterTypes),
      isNull = Block(),
      notNull = Block();
  final maybe = check.emit(DirectCall(nullable, check.parameters));
  check.finish(
    Branch(
      check.emit(Equals(maybe, const Constant.nullValue())),
      Jump(isNull),
      Jump(notNull),
    ),
  );
  isNull.finish(Return(const Constant.integer(1)));
  notNull.finish(Return(const Constant.integer(0)));
  functions.add(IrFunction(checkNull, [check, isNull, notNull]));

  return IrProgram(
    [
      IrClass(base, [x]),
      IrClass(point, [y, flag], members: [identity]),
      IrClass(box, [item]),
    ],
    functions,
    externals: [IrExternal(touch)],
  );
}

ObjectModule objectValues(Target target) {
  final program = objectGraphs();
  final CodeGenerator generator = target.architecture == .arm64
      ? Arm64CodeGenerator(target)
      : X64CodeGenerator(target);
  return generator.generate(
    program,
    definitions: [
      ...program.functions.map((f) => f.target),
      program.externals.single.target,
    ],
    imports: {
      program.externals.single.target: NativeImport(
        'object_touch',
        NativeSignature(Int64, []),
      ),
    },
    exports: {
      for (final f in program.functions)
        if (f.target.returnType == .integer || f.target.returnType == .floating)
          if (f.target.parameterTypes.every((type) => type == .integer))
            f.target: NativeExport(
              f.target.name,
              NativeSignature(
                f.target.name == 'integer_field'
                    ? Int16
                    : f.target.returnType == .floating
                    ? Double
                    : Int64,
                List.filled(f.target.parameterTypes.length, Int64),
              ),
            ),
    },
  );
}
