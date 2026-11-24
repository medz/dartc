import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/native.dart';

import 'exports.dart';
import 'native_types.dart';

/// Writes what C and C++ need to call exported functions.
final class HeaderWriter(final NativeTypes _types) {
  /// The structs and unions that are declared, in an order in which each comes
  /// after those that it has in it.
  final _compounds = <InterfaceElement>{};
  final _opaque = <InterfaceElement>{};
  final _names = <InterfaceElement, String>{};

  /// The header for [exports].
  String write(Iterable<Export> exports) {
    final prototypes = [
      for (final (:name, element: _, :native, unit: _, node: _) in exports)
        '${_function(native, name)};',
    ];
    final bodies = [for (final compound in _compounds) _declaration(compound)];
    final ahead = [
      for (final element in {..._opaque, ..._compounds}) '${_tag(element)};',
    ];
    return [
      '#pragma once\n',
      '#include <stdbool.h>',
      '#include <stdint.h>\n',
      '#ifdef __cplusplus\nextern "C" {\n#endif\n',
      if (ahead.isNotEmpty) '${ahead.join('\n')}\n',
      for (final body in bodies) '$body\n',
      ...prototypes,
      '\n#ifdef __cplusplus\n}\n#endif\n',
    ].join('\n');
  }

  /// What [element] is called, as no two can be called alike.
  String _name(InterfaceElement element) => _names[element] ??= () {
    final own = element.displayName;
    final base = _isC(own) ? own : 'dartc_$own';
    var name = base;
    for (var i = 2; _names.containsValue(name); i++) {
      name = '${base}_$i';
    }
    return name;
  }();

  static const _words = {
    'alignas', 'alignof', 'and', 'asm', 'auto', 'bool', 'break', 'case', //
    'catch', 'char', 'class', 'const', 'constexpr', 'continue', 'default',
    'delete', 'do', 'double', 'else', 'enum', 'explicit', 'export', 'extern',
    'false', 'float', 'for', 'friend', 'goto', 'if', 'inline', 'int', 'long',
    'mutable', 'namespace', 'new', 'noexcept', 'not', 'nullptr', 'operator',
    'or', 'private', 'protected', 'public', 'register', 'restrict', 'return',
    'short', 'signed', 'sizeof', 'static', 'struct', 'switch', 'template',
    'this', 'throw', 'true', 'try', 'typedef', 'typename', 'union',
    'unsigned', 'using', 'virtual', 'void', 'volatile', 'while', 'xor',
  };

  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z_0-9]*$');

  static bool _isC(String name) =>
      _identifier.hasMatch(name) && !_words.contains(name);

  String _tag(InterfaceElement element) {
    final isUnion = element.allSupertypes.any(
      (type) => NativeTypes.isFfi(type.element) && type.element.name == 'Union',
    );
    return '${isUnion ? 'union' : 'struct'} ${_name(element)}';
  }

  /// Declares [declarator] as a function of [type].
  String _function(FunctionType type, String declarator) {
    final parameters = [
      for (final parameter in type.formalParameters)
        _declare(parameter.type, ''),
    ];
    final list = parameters.isEmpty ? 'void' : parameters.join(', ');
    return _declare(type.returnType, '$declarator($list)');
  }

  /// Declares [declarator] as one of [type].
  String _declare(DartType type, String declarator) {
    final element = (type as InterfaceType).element;
    String plain(String name) => declarator.isEmpty
        ? name
        : declarator.startsWith('*')
        ? '$name $declarator'
        : '$name $declarator';
    if (NativeTypes.isFfi(element)) {
      if (element.name == 'Pointer') {
        return _pointer(type.typeArguments.single, declarator);
      }
      if (element.name == 'Void') return plain('void');
    }
    switch (_types.of(type)) {
      case NativeInteger(:final size, :final isSigned):
        return plain('${isSigned ? '' : 'u'}int${size * 8}_t');
      case NativeBoolean():
        return plain('bool');
      case NativeFloating(:final size):
        return plain(size == 4 ? 'float' : 'double');
      case NativeCompound():
        _add(element);
        return plain(_tag(element));
      case _:
        // Only pointers to it are used.
        _opaque.add(element);
        return plain(_tag(element));
    }
  }

  String _pointer(DartType to, String declarator) {
    if (to is InterfaceType && NativeTypes.isFfi(to.element)) {
      if (to.element.name == 'NativeFunction') {
        final function = to.typeArguments.single;
        if (function is FunctionType) {
          return _function(function, '(*$declarator)');
        }
      }
      if (const ['NativeType', 'Opaque', 'Handle'].contains(to.element.name)) {
        return 'void *$declarator';
      }
    }
    return to is InterfaceType
        ? _declare(to, '*$declarator')
        : 'void *$declarator';
  }

  void _add(InterfaceElement element) {
    if (_compounds.contains(element) || !_adding.add(element)) return;
    // Those that it has in it come first.
    for (final field in element.fields) {
      _fieldText(element, field);
    }
    _compounds.add(element);
  }

  final _adding = <InterfaceElement>{};

  String _declaration(InterfaceElement element) {
    final packing = _types.compound(element)!.packing;
    final fields = [
      for (final field in element.fields) ?_fieldText(element, field),
    ];
    final body = '${_tag(element)} {\n${fields.join()}};';
    return packing == null
        ? body
        : '#pragma pack(push, $packing)\n$body\n#pragma pack(pop)';
  }

  String? _fieldText(InterfaceElement owner, FieldElement field) {
    final found = _types.field(owner, field);
    if (found == null) return null;
    final own = field.displayName;
    final name = _isC(own) ? own : 'dartc_$own';
    final sizes = found.dimensions.map((size) => '[$size]').join();
    var type = field.type;
    while (type is InterfaceType &&
        NativeTypes.isFfi(type.element) &&
        type.element.name == 'Array') {
      type = type.typeArguments.single;
    }
    final text = switch ((type, found.type)) {
      (InterfaceType(element: final element), _)
          when !element.library.isDartCore =>
        _declare(type, '$name$sizes'),
      (_, NativeInteger(:final size, :final isSigned)) =>
        '${isSigned ? '' : 'u'}int${size * 8}_t $name',
      (_, NativeBoolean()) => 'bool $name',
      (_, NativeFloating(:final size)) =>
        '${size == 4 ? 'float' : 'double'} $name',
      _ => throw StateError('No field of $type.'),
    };
    return '  $text;\n';
  }
}
