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
  /// Invalid or conflicting C tags and field names receive unique generated names.
  /// Dart identities, field order and native storage remain unchanged.
  void writeHeader(StringSink output, {Abi? abi}) {
    final compounds = <NativeCompoundType>[];
    final declarations = <NativeTypeRef, String>{};
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
          declarations[type] = name;
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
      final type = declarations.keys.elementAt(i);
      if (type is NativeCompoundType) collect(type);
    }
    final typeNames = Map<NativeTypeRef, String>.fromIterables(
      declarations.keys,
      _names(declarations.values, 'type'),
    );
    output.writeln(
      '#pragma once\n#include <stdint.h>\n#include <stdbool.h>\n\n#ifdef __cplusplus\nextern "C" {\n#endif\n',
    );
    for (final type in declarations.keys) {
      output.writeln('${type.declaration('', typeNames: typeNames)};');
    }
    for (final type in compounds) {
      if (type.packing case final packing?) {
        output.writeln('#pragma pack(push, $packing)');
      }
      output.writeln('${type.declaration('', typeNames: typeNames)} {');
      final names = _names(type.fields.map((f) => f.name), 'field').iterator;
      for (final field in type.fields) {
        names.moveNext();
        output.writeln(
          '  ${field.type.declaration(names.current, abi: abi, typeNames: typeNames)};',
        );
      }
      output.writeln('};');
      if (type.packing != null) output.writeln('#pragma pack(pop)');
    }
    if (declarations.isNotEmpty) output.writeln();
    for (final function in functions) {
      function.writeDeclaration(output, abi: abi, typeNames: typeNames);
    }
    output.writeln('\n#ifdef __cplusplus\n}\n#endif');
  }
}

Iterable<String> _names(Iterable<String> requested, String kind) sync* {
  final reserved = requested.where(isCIdentifier).toSet();
  final used = <String>{};
  var suffix = 0;
  for (var name in requested) {
    if (!isCIdentifier(name) || used.contains(name)) {
      do {
        name = 'dartc_${kind}_${++suffix}';
      } while (reserved.contains(name));
    }
    used.add(name);
    yield name;
  }
}
