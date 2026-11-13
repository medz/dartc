import 'dart:ffi' show Abi;

import 'native_export.dart';
import 'c_identifier.dart';
import 'native_signature.dart';

/// Native function declarations with distinct exported names.
final class NativeExports(Iterable<NativeExport> functions) {
  /// Native functions in declaration order.
  final List<NativeExport> functions = .unmodifiable(functions);

  this {
    final names = <String>{};
    for (final function in this.functions) {
      if (!names.add(function.symbol)) {
        throw ArgumentError('Repeated native export: ${function.symbol}');
      }
    }
  }

  /// Writes declarations usable from both C and C++.
  ///
  /// [abi] is required for declarations containing ABI-specific integers.
  void writeHeader(StringSink output, {Abi? abi}) {
    final compounds = <NativeCompoundType>[];
    final declarations = <String, NativeTypeRef>{};
    final visited = <NativeTypeRef>{};
    final active = <NativeCompoundType>{};
    void collect(NativeTypeRef type, {bool pointer = false}) {
      if (pointer) {
        if (type is NativeCompoundType || type is NativeOpaqueType) {
          final name = switch (type) {
            NativeCompoundType(:final name) ||
            NativeOpaqueType(:final name) => name,
            _ => throw StateError('Expected native declaration'),
          };
          checkCIdentifier(name);
          if (declarations[name] case final previous?
              when !identical(previous, type)) {
            throw ArgumentError('Conflicting native type names: $name');
          }
          declarations[name] = type;
          return;
        }
      }
      if (active.contains(type)) {
        throw ArgumentError('Recursive native value: $type');
      }
      if (!visited.add(type)) return;
      switch (type) {
        case NativeCompoundType(:final fields):
          collect(type, pointer: true);
          active.add(type);
          for (final field in fields) {
            checkCIdentifier(field.name);
            collect(field.type);
          }
          active.remove(type);
          compounds.add(type);
        case NativePointerType(:final element):
          collect(element, pointer: true);
        case NativeArrayType(:final element):
          collect(element);
        case NativeFunctionType(:final signature):
          collect(signature.result);
          signature.parameters.forEach(collect);
        case NativeOpaqueType():
          collect(type, pointer: true);
        case NativeScalarType() || NativeAbiIntegerType():
          break;
      }
    }

    for (final function in functions) {
      collect(function.signature.result);
      function.signature.parameters.forEach(collect);
    }
    // Pointees need definitions too; following them later permits pointer cycles.
    for (var i = 0; i < declarations.length; i++) {
      final type = declarations.values.elementAt(i);
      if (type is NativeCompoundType) collect(type);
    }
    output.writeln(
      '#pragma once\n#include <stdint.h>\n#include <stdbool.h>\n\n#ifdef __cplusplus\nextern "C" {\n#endif\n',
    );
    for (final type in declarations.values) {
      output.writeln('${type.declaration('')};');
    }
    for (final type in compounds) {
      if (type.packing case final packing?) {
        output.writeln('#pragma pack(push, $packing)');
      }
      output.writeln('${type.declaration('')} {');
      for (final field in type.fields) {
        output.writeln('  ${field.type.declaration(field.name, abi: abi)};');
      }
      output.writeln('};');
      if (type.packing != null) output.writeln('#pragma pack(pop)');
    }
    if (declarations.isNotEmpty) output.writeln();
    for (final function in functions) {
      function.writeDeclaration(output, abi: abi);
    }
    output.writeln('\n#ifdef __cplusplus\n}\n#endif');
  }
}
