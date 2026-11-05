import 'package:dartc/ir.dart';
import 'package:test/test.dart';

final _library = Uri.parse('memory:verifier-fastpath');

TypeParameterType _parameter(String name, {ValueType? defaultType}) {
  final result = TypeParameterType(name)
    ..initializeBound(ValueType.object.nullable);
  if (defaultType != null) result.initializeDefaultType(defaultType);
  return result;
}

FunctionTarget _target(String name) =>
    FunctionTarget(_library, name, .voidType, []);

void main() {
  test(
    'virtual parameter iterable is materialized once before covariance scan',
    () {
      final t = _parameter('T');
      final owner = ClassType(_library, 'GenericOwner', typeParameters: [t]);
      var iterations = 0;
      Iterable<ValueType> parameters() sync* {
        iterations++;
        yield t;
      }

      final target = FunctionTarget(
        _library,
        'method',
        .voidType,
        parameters(),
        owner: owner,
        kind: .method,
      );
      expect(iterations, 1);
      expect(target.signature.parameters.single, same(t));
      expect(target.covariantParameters, {0});
      expect(
        target.reifiedSignature.parameters.single,
        ValueType.object.nullable,
      );
    },
  );

  test('explicit covariance is preserved for nongeneric owners', () {
    final owner = ClassType(_library, 'NongenericOwner');
    final target = FunctionTarget(
      _library,
      'method',
      .voidType,
      [ValueType.integer],
      owner: owner,
      kind: .method,
      covariantParameters: [0],
    );
    expect(target.signature.parameters.single, ValueType.integer);
    expect(target.covariantParameters, {0});
    expect(
      target.reifiedSignature.parameters.single,
      ValueType.object.nullable,
    );
  });

  test(
    'scope cache distinguishes equal function types with different defaults',
    () {
      final foreign = _parameter('Foreign');
      final goodBinder = _parameter('T', defaultType: ValueType.integer);
      final badBinder = _parameter('T', defaultType: foreign);
      final good = FunctionType(.voidType, [], typeParameters: [goodBinder]);
      final bad = FunctionType(.voidType, [], typeParameters: [badBinder]);
      expect(good, bad);
      expect(identical(good, bad), isFalse);
      final block = Block();
      block.emit(ReifyType(good));
      block.emit(ReifyType(bad));
      block.finish(const Return());
      expect(
        () => IrFunction(_target('badDefault'), [block]),
        throwsStateError,
      );
    },
  );

  test('scope cache is local to each verification', () {
    final t = _parameter('T');
    final template = CoreTypes.listOf(t);
    Block body() {
      final block = Block();
      block.emit(ReifyType(template));
      block.finish(const Return());
      return block;
    }

    final generic = FunctionTarget(
      _library,
      'generic',
      .voidType,
      [],
      typeParameters: [t],
    );
    expect(() => IrFunction(generic, [body()]), returnsNormally);
    expect(() => IrFunction(_target('nongeneric'), [body()]), throwsStateError);
  });

  test('single-block verification rejects every outgoing edge form', () {
    for (final self in [true, false]) {
      for (final shape in [
        'jump',
        'branch',
        'throw',
        'exhaustiveness',
        'invoke',
      ]) {
        final block = Block();
        final destination = self ? block : (Block()..finish(const Return()));
        final edge = Jump(destination);
        switch (shape) {
          case 'jump':
            block.finish(edge);
          case 'branch':
            block.finish(Branch(const Constant.boolean(true), edge, edge));
          case 'throw':
            block.finish(Throw(const Constant.integer(1), onThrow: edge));
          case 'exhaustiveness':
            block.finish(ExhaustivenessFailure(edge));
          case 'invoke':
            final cast = TypeCast(const Constant.integer(1), .integer);
            block.finish(Invoke(cast, onReturn: edge, onThrow: edge));
        }
        expect(
          () => IrFunction(_target('edge'), [block]),
          throwsStateError,
          reason: '$shape edge to ${self ? "entry" : "missing block"}',
        );
      }
    }
  });

  test(
    'single-block verification rejects duplicate SSA and unterminated blocks',
    () {
      final op = IntBinary(
        .add,
        const Constant.integer(1),
        const Constant.integer(2),
      );
      final block = Block();
      block.emit(op);
      block.emit(op);
      block.finish(const Return());
      expect(() => IrFunction(_target('duplicate'), [block]), throwsStateError);
      expect(
        () => IrFunction(_target('unsealed'), [Block()]),
        throwsStateError,
      );
    },
  );

  test('edge-free throwing and unreachable terminators remain legal', () {
    final throwing = Block()..finish(Throw(const Constant.integer(1)));
    final exhaustive = Block()..finish(const ExhaustivenessFailure());
    final unreachable = Block();
    final cause = unreachable.emit(NullCheck(const Constant.nullValue()));
    unreachable.finish(Unreachable(cause));
    for (final block in [throwing, exhaustive, unreachable]) {
      expect(() => IrFunction(_target('terminal'), [block]), returnsNormally);
    }
  });

  test('single-block verification retains globals and closure checks', () {
    final parent = _target('parent');
    final child = FunctionTarget(
      _library,
      'child',
      .voidType,
      [],
      kind: .closure,
      enclosing: parent,
      sourceOffset: 1,
    );
    final global = GlobalVariable(
      _library,
      'global',
      ValueType.integer.nullable,
    );
    final block = Block();
    block.emit(MakeClosure(child, []));
    final loaded = block.emit(LoadGlobal(global));
    block.emit(StoreGlobal(global, loaded));
    block.finish(const Return());
    final function = IrFunction(parent, [block]);
    expect(function.closures, {child});
    expect(function.globals, {global});

    final invalid = Block();
    invalid.emit(MakeClosure(child, []));
    invalid.finish(const Return());
    expect(() => IrFunction(_target('unrelated'), [invalid]), throwsStateError);
  });
}
