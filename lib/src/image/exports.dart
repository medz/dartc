import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';

/// Exported names that start alike, and how they go on.
final class _Node() {
  /// The address of what is called like the path here, if there is that.
  int? address;
  final children = <(String, _Node)>[];

  /// Where this is in the table.
  int offset = 0;

  Uint8List get _terminal {
    final own = address;
    if (own == null) return Uint8List(0);
    final out = ByteWriter(.little);
    _unsigned(out, 0);
    _unsigned(out, own);
    return out.finish();
  }

  Uint8List encode() {
    final out = ByteWriter(.little), terminal = _terminal;
    _unsigned(out, terminal.length);
    out
      ..bytes(terminal)
      ..u8(children.length);
    for (final (text, child) in children) {
      out
        ..bytes(utf8.encode(text))
        ..u8(0);
      _unsigned(out, child.offset);
    }
    return out.finish();
  }
}

void _unsigned(ByteWriter out, int value) {
  var rest = value;
  while (rest >= 0x80) {
    out.u8(rest & 0x7f | 0x80);
    rest >>= 7;
  }
  out.u8(rest);
}

_Node _build(List<(String, int)> names) {
  final node = _Node(), groups = <String, List<(String, int)>>{};
  for (final (name, address) in names) {
    if (name.isEmpty) {
      node.address = address;
    } else {
      (groups[name[0]] ??= []).add((name, address));
    }
  }
  for (final group in groups.values) {
    var text = group.first.$1;
    for (final (name, _) in group) {
      while (!name.startsWith(text)) {
        text = text.substring(0, text.length - 1);
      }
    }
    final rest = [
      for (final (name, address) in group)
        (name.substring(text.length), address),
    ];
    node.children.add((text, _build(rest)));
  }
  return node;
}

/// Tells the loader the addresses of [symbols], from the start of the image.
Uint8List exportTable(Map<String, int> symbols) {
  if (symbols.isEmpty) return Uint8List(0);
  final nodes = [
    _build([for (final entry in symbols.entries) (entry.key, entry.value)]),
  ];
  for (var i = 0; i < nodes.length; i++) {
    nodes.addAll([for (final (_, child) in nodes[i].children) child]);
  }
  // Offsets take more bytes the further nodes are, which are found by then.
  bool changed;
  do {
    changed = false;
    var offset = 0;
    for (final node in nodes) {
      if (node.offset != offset) changed = true;
      node.offset = offset;
      offset += node.encode().length;
    }
  } while (changed);
  final out = ByteWriter(.little);
  for (final node in nodes) {
    out.bytes(node.encode());
  }
  out.align(8);
  return out.finish();
}
