import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _type = ClassType(null, 'Bytes');
final _layout = ProgramLayout([
  IrClass(_type, []),
], nativeLayout: NativeLayout(const Target(.linux, .x64)));
final _u8 = NativeScalarType(Uint8);
final _i64 = NativeScalarType(Int64);
Object? _number(FlowValue value) => (value.constant as ScalarConstant?)?.value;

Value _payloadAddress(Block block, Value owner) => block.emit(
  IntBinary(
    .add,
    block.emit(ReferenceAddress(owner)),
    Constant.integer(_layout.objectLayout(_type).size),
  ),
);

ProgramFlowFacts _analyze(
  FunctionTarget root,
  List<Block> blocks, {
  List<IrClass> classes = const [],
}) => ProgramFlow(IrProgram(classes, [IrFunction(root, blocks)]), [
  (target: root, arguments: []),
], memoryLayout: _layout).facts;

void main() {
  for (final prior in [false, true]) {
    test('a native aggregate result may carry the pointee prior=$prior', () {
      final root = FunctionTarget(null, 'root', .integer, []);
      final block = Block();
      final output = block.emit(
        NativeDataAddress(NativeData(List.filled(8, 0))),
      );
      final owner = block.emit(NewPayload(_type, const Constant.integer(8)));
      final address = _payloadAddress(block, owner);
      final pointerType = NativePointerType(_i64);
      final compound = NativeCompoundType('Result', [
        NativeField('pointer', pointerType),
      ]);
      if (prior) {
        block.emit(
          RawNativeCall(
            const Constant.integer(1),
            NativeSignature.types(NativeTypeRef.of(Void), [pointerType]),
            [address],
            isLeaf: true,
          ),
        );
      }
      block.emit(
        RawNativeCall(
          const Constant.integer(2),
          NativeSignature.types(compound, [if (!prior) pointerType]),
          [if (!prior) address],
          isLeaf: true,
          resultStorage: output,
        ),
      );
      final read = block.emit(LoadNative(output, _i64));
      block.finish(const Return(Constant.integer(1)));
      final facts = _analyze(root, [block], classes: [IrClass(_type, [])]);
      final object = facts.valueOf(owner).objects.single;
      expect(
        facts.valueOf(read).references.objects.contains(object) ||
            facts.valueOf(read).addresses.any((p) => p.base == object),
        isTrue,
      );
    });
  }
  for (final raw in [false, true]) {
    for (final prior in [false, true]) {
      test(
        'native writes a retained pointer through an argument (raw=$raw, prior=$prior)',
        () {
          final root = FunctionTarget(null, 'root', .integer, []);
          final block = Block();
          final owner = block.emit(
            NewPayload(_type, const Constant.integer(8)),
          );
          final address = _payloadAddress(block, owner);
          final output = block.emit(
            NativeDataAddress(NativeData(List.filled(8, 0))),
          );
          final private = block.emit(NativeDataAddress(NativeData([97])));
          void host(String name, List<Value> addresses) {
            final signature = NativeSignature.types(NativeTypeRef.of(Void), [
              for (final _ in addresses) NativePointerType(_i64),
            ]);
            final symbol = block.emit(
              NativeSymbolAddress(
                NativeReference(
                  'fixture',
                  name,
                  NativeFunctionType(signature),
                  isLeaf: true,
                ),
              ),
            );
            if (raw) {
              block.emit(
                RawNativeCall(symbol, signature, addresses, isLeaf: true),
              );
            } else {
              block.emit(
                NativeCall.symbol(
                  symbol,
                  FunctionType(.voidType, [
                    for (final _ in addresses) FfiTypes.int64Pointer,
                  ]),
                  [
                    for (final value in addresses)
                      block.emit(
                        PointerFromAddress(value, FfiTypes.int64Pointer),
                      ),
                  ],
                ),
              );
            }
          }

          if (prior) host('stash', [address]);
          host('writePointer', [output, if (!prior) address]);
          final read = block.emit(LoadNative(output, _i64));
          block.finish(Return(block.emit(LoadNative(private, _u8))));
          final facts = _analyze(root, [block], classes: [IrClass(_type, [])]);
          final written = facts.valueOf(read);
          final pointee = facts.valueOf(owner).objects.single;
          expect(
            written.references.objects.contains(pointee) ||
                written.addresses.any((a) => a.base == pointee),
            isTrue,
          );
          expect(_number(facts.returnedBy(root)), 97);
        },
      );
    }
  }
  for (final raw in [false, true]) {
    test('native can store a pointer obtained by reentry (raw=$raw)', () {
      final callback = FunctionTarget(null, 'callback', .integer, []);
      final callbackBody = Block();
      final owner = callbackBody.emit(
        NewPayload(_type, const Constant.integer(8)),
      );
      callbackBody.finish(Return(_payloadAddress(callbackBody, owner)));
      final callbackSignature = NativeSignature(Int64, []);
      final callbackType = NativePointerType(
        NativeFunctionType(callbackSignature),
      );
      final declaration = StaticCallbackTarget(
        callback,
        FunctionType(FfiTypes.int64, []),
        exceptionalReturn: const Constant.integer(0),
      );

      final root = FunctionTarget(null, 'root', .integer, []);
      final block = Block();
      final out = block.emit(NativeDataAddress(NativeData(List.filled(8, 0))));
      final callee = block.emit(NativeCallbackAddress(declaration));
      final signature = NativeSignature.types(NativeTypeRef.of(Void), [
        NativePointerType(_i64),
        callbackType,
      ]);
      final host = block.emit(
        NativeSymbolAddress(
          NativeReference(
            'fixture',
            'storeCallbackResult',
            NativeFunctionType(signature),
          ),
        ),
      );
      if (raw) {
        block.emit(RawNativeCall(host, signature, [out, callee]));
      } else {
        final dartType = FfiTypes.resolve(callbackType);
        block.emit(
          NativeCall.symbol(
            host,
            FunctionType(.voidType, [FfiTypes.int64Pointer, dartType]),
            [
              block.emit(PointerFromAddress(out, FfiTypes.int64Pointer)),
              block.emit(PointerFromAddress(callee, dartType)),
            ],
          ),
        );
      }
      final read = block.emit(LoadNative(out, _i64));
      block.finish(const Return(Constant.integer(1)));
      final facts = ProgramFlow(
        IrProgram(
          [IrClass(_type, [])],
          [
            IrFunction(root, [block]),
            IrFunction(callback, [callbackBody]),
          ],
        ),
        [(target: root, arguments: [])],
        memoryLayout: _layout,
      ).facts;
      final pointee = facts.valueOf(owner).objects.single;
      expect(
        facts.returnedBy(callback).addresses.any((a) => a.base == pointee),
        isTrue,
      );
      final written = facts.valueOf(read);
      expect(
        written.references.objects.contains(pointee) ||
            written.addresses.any((a) => a.base == pointee),
        isTrue,
      );
    });
  }
  for (final later in [false, true]) {
    for (final raw in [false, true]) {
      test('native can return a retained pointee raw=$raw later=$later', () {
        final root = FunctionTarget(null, 'root', .integer, []);
        final block = Block();
        final owner = block.emit(NewPayload(_type, const Constant.integer(8)));
        final address = _payloadAddress(block, owner);
        final pointer = block.emit(
          PointerFromAddress(address, FfiTypes.int64Pointer),
        );
        Instruction call(bool consume, bool hasArg) {
          final signature = NativeSignature.types(
            consume ? NativeTypeRef.of(Void) : NativePointerType(_i64),
            [if (hasArg) NativePointerType(_i64)],
          );
          if (raw) {
            return block.emit(
              RawNativeCall(const Constant.integer(1), signature, [
                if (hasArg) address,
              ], isLeaf: true),
            );
          }
          final symbol = block.emit(
            NativeSymbolAddress(
              NativeReference(
                'test',
                consume ? 'stash' : 'get',
                NativeFunctionType(signature),
                isLeaf: true,
              ),
            ),
          );
          return block.emit(
            NativeCall.symbol(
              symbol,
              FunctionType(consume ? .voidType : FfiTypes.int64Pointer, [
                if (hasArg) FfiTypes.int64Pointer,
              ]),
              [if (hasArg) pointer],
            ),
          );
        }

        if (later) {
          call(true, true);
        }
        final result = call(false, !later);
        block.finish(const Return(Constant.integer(1)));
        final facts = _analyze(root, [block], classes: [IrClass(_type, [])]);
        final returned = facts.valueOf(result);
        final object = facts.valueOf(owner).objects.single;
        expect(
          returned.references.objects.contains(object) ||
              returned.addresses.any((pointer) => pointer.base == object),
          isTrue,
          reason: 'result may alias same allocated payload',
        );
      });
    }
  }
  for (final raw in [false, true]) {
    for (final forward in [false, true]) {
      test(
        'only pointers in the actual by-value ABI bytes cross raw=$raw forward=$forward',
        () {
          final word = NativeCompoundType('Word', [NativeField('tag', _i64)]);
          final view = ClassType(null, 'Word', nativeType: word);
          final root = FunctionTarget(null, 'root', .integer, []);
          final entry = Block();
          final source = entry.emit(
            NativeDataAddress(NativeData(List.filled(16, 0))),
          );
          final outside = entry.emit(NativeDataAddress(NativeData([42])));
          final field = entry.emit(
            IntBinary(.add, source, const Constant.integer(8)),
          );
          entry.emit(StoreNative(field, _i64, outside));
          final arg = raw
              ? source
              : entry.emit(NativeView(view, address: source));
          final block = forward ? Block([arg.type]) : entry;
          if (forward) {
            entry.finish(Jump(block, [arg]));
          }
          final passed = forward ? block.parameters.single : arg;
          final signature = NativeSignature.types(NativeTypeRef.of(Void), [
            word,
          ]);
          if (raw) {
            block.emit(
              RawNativeCall(const Constant.integer(1), signature, [
                passed,
              ], isLeaf: true),
            );
          } else {
            final symbol = block.emit(
              NativeSymbolAddress(
                NativeReference(
                  'test',
                  'readWord',
                  NativeFunctionType(signature),
                  isLeaf: true,
                ),
              ),
            );
            block.emit(
              NativeCall.symbol(symbol, FunctionType(.voidType, [view]), [
                passed,
              ]),
            );
          }
          block.finish(Return(block.emit(LoadNative(outside, _u8))));
          final facts = _analyze(
            root,
            [entry, if (forward) block],
            classes: [IrClass(view, [])],
          );
          expect(
            facts.returnedBy(root).constant?.structuralKey,
            const Constant.integer(42).structuralKey,
          );
        },
      );
    }
  }

  for (final raw in [false, true]) {
    for (final borrow in [false, true]) {
      test(
        'foreign argument writes and retention (raw=$raw, borrow=$borrow)',
        () {
          final signature = NativeSignature(Void, [Pointer<Int64>]);
          final root = FunctionTarget(null, 'root', .integer, []);
          final block = Block();
          final private = block.emit(NativeDataAddress(NativeData([42])));
          final owner = block.emit(
            NewPayload(_type, const Constant.integer(8)),
          );
          final address = _payloadAddress(block, owner);
          block.emit(StoreNative(address, _i64, const Constant.integer(7)));
          final symbol = block.emit(
            NativeSymbolAddress(
              NativeReference(
                'fixture',
                'consume',
                NativeFunctionType(signature),
                isLeaf: true,
              ),
            ),
          );
          final call = block.emit(
            raw
                ? RawNativeCall(
                    symbol,
                    signature,
                    [address],
                    isLeaf: true,
                    borrowedArguments: [if (borrow) 0],
                  )
                : NativeCall.symbol(
                    symbol,
                    FunctionType(.voidType, [FfiTypes.int64Pointer]),
                    [
                      borrow
                          ? address
                          : block.emit(
                              PointerFromAddress(
                                address,
                                FfiTypes.int64Pointer,
                              ),
                            ),
                    ],
                    borrowedOwners: {if (borrow) 0: owner},
                  ),
          );
          final after = block.emit(LoadNative(address, _i64));
          block.emit(StoreNative(address, _i64, const Constant.integer(19)));
          block.emit(
            RawNativeCall(
              const Constant.integer(1),
              NativeSignature(Void, []),
              const [],
              isLeaf: true,
            ),
          );
          final later = block.emit(LoadNative(address, _i64));
          block.finish(Return(block.emit(LoadNative(private, _u8))));
          final facts = _analyze(root, [block], classes: [IrClass(_type, [])]);
          expect(_number(facts.returnedBy(root)), 42);
          expect(_number(facts.valueOf(after)), isNull);
          expect(_number(facts.valueOf(later)), borrow ? 19 : null);
          expect(
            facts.effectsOf(call),
            containsAll([
              Effect.allocates,
              Effect.mayThrow,
              Effect.readsStorage,
              Effect.writesStorage,
            ]),
          );
          expect(facts.effectsOf(call), isNot(contains(Effect.callsUserCode)));
          expect(facts.hasUnknownCall(call), isFalse);
        },
      );
    }
  }

  for (final integerCarrier in [false, true]) {
    test(
      'by-value ABI inputs expose pointees and output is a bounded write (integer carrier=$integerCarrier)',
      () {
        final root = FunctionTarget(null, 'root', .integer, []);
        final block = Block();
        final input = block.emit(
          NativeDataAddress(NativeData(List.filled(8, 0))),
        );
        final pointee = block.emit(NativeDataAddress(NativeData([8])));
        block.emit(StoreNative(input, _i64, pointee));
        final output = block.emit(
          NativeDataAddress(NativeData(List.filled(9, 5))),
        );
        final tail = block.emit(
          IntBinary(.add, output, const Constant.integer(8)),
        );
        final pair = NativeCompoundType('ByValue', [
          NativeField('address', NativePointerType(_i64)),
        ]);
        final argument = integerCarrier
            ? block.emit(IntBinary(.bitXor, input, const Constant.integer(0)))
            : input;
        block.emit(
          RawNativeCall(
            const Constant.integer(1),
            NativeSignature.types(pair, [pair]),
            [argument],
            resultStorage: output,
            isLeaf: true,
          ),
        );
        final readInput = block.emit(LoadNative(input, _i64));
        final readPointee = block.emit(LoadNative(pointee, _u8));
        final readOutput = block.emit(LoadNative(output, _u8));
        block.emit(
          RawNativeCall(
            const Constant.integer(1),
            NativeSignature(Void, []),
            const [],
            isLeaf: true,
          ),
        );
        block.finish(Return(block.emit(LoadNative(tail, _u8))));
        final facts = ProgramFlow(
          IrProgram([], [
            IrFunction(root, [block]),
          ]),
          [(target: root, arguments: [])],
          memoryLayout: _layout,
        ).facts;
        if (!integerCarrier) {
          expect(
            facts.valueOf(readInput).addresses,
            facts.valueOf(pointee).addresses,
          );
          expect(facts.valueOf(readInput).unknownTypes, isEmpty);
        }
        expect(_number(facts.valueOf(readPointee)), isNull);
        expect(_number(facts.valueOf(readOutput)), isNull);
        expect(_number(facts.returnedBy(root)), 5);
      },
    );
  }

  for (final copy in [false, true]) {
    test('an aggregate argument reads its own bytes (copy=$copy)', () {
      final word = NativeCompoundType('Word', [
        NativeField('p', NativePointerType(_i64)),
      ]);
      final view = ClassType(null, 'Word', nativeType: word);
      final root = FunctionTarget(null, 'root', .integer, []);
      final block = Block();
      final input = block.emit(
        NativeDataAddress(NativeData(List.filled(8, 0))),
      );
      final pointee = block.emit(NativeDataAddress(NativeData([8])));
      block.emit(StoreNative(input, _i64, pointee));
      final argument = block.emit(NativeView(view, address: input, copy: copy));
      block.emit(StoreNative(input, _i64, const Constant.integer(0)));
      final signature = NativeSignature.types(NativeTypeRef.of(Void), [word]);
      final symbol = block.emit(
        NativeSymbolAddress(
          NativeReference(
            'test',
            'consume',
            NativeFunctionType(signature),
            isLeaf: true,
          ),
        ),
      );
      block.emit(
        NativeCall.symbol(symbol, FunctionType(.voidType, [view]), [argument]),
      );
      block.finish(Return(block.emit(LoadNative(pointee, _u8))));
      final facts = _analyze(root, [block], classes: [IrClass(view, [])]);
      expect(_number(facts.returnedBy(root)), copy ? null : 8);
    });
  }

  for (final byValue in [false, true]) {
    test(
      'a temporary native read retains its input store (byValue=$byValue)',
      () {
        final root = FunctionTarget(null, 'root', .voidType, []);
        final block = Block();
        final owner = block.emit(NewPayload(_type, const Constant.integer(8)));
        final address = _payloadAddress(block, owner);
        block.emit(StoreNative(address, _i64, const Constant.integer(47)));
        final parameter = byValue
            ? NativeCompoundType('ByValue', [NativeField('field', _i64)])
            : NativePointerType(_i64);
        block.emit(
          RawNativeCall(
            const Constant.integer(1),
            NativeSignature.types(NativeTypeRef.of(Void), [parameter]),
            [address],
            isLeaf: true,
            borrowedArguments: [if (!byValue) 0],
          ),
        );
        block.finish(const Return());
        final facts = _analyze(root, [block], classes: [IrClass(_type, [])]);
        final optimized = const ProgramStorageElimination().run(facts);
        expect(
          optimized.functions.single.entry.instructions
              .whereType<StoreNative>(),
          hasLength(1),
        );
      },
    );
  }
}
