import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/object.dart';

/// Encodes dyld's compressed symbol trie with image-relative function addresses.
final class ExportTrie(final List<Symbol> symbols, final int codeOffset) {
  /// Encodes the declared exports into one compressed trie.
  Uint8List encode() {
    final entries =
        [
          for (final symbol in symbols)
            (utf8.encode(symbol.name), codeOffset + symbol.offset),
        ]..sort((a, b) {
          for (var i = 0; i < a.$1.length && i < b.$1.length; i++) {
            final order = a.$1[i].compareTo(b.$1[i]);
            if (order != 0) return order;
          }
          return a.$1.length.compareTo(b.$1.length);
        });
    final nodes = <_Node>[];
    _Node build(int start, int end, int depth, List<int> edge) {
      final node = _Node(edge);
      nodes.add(node);
      if (start < end && entries[start].$1.length == depth) {
        node.address = entries[start++].$2;
      }
      while (start < end) {
        final first = entries[start].$1;
        var next = start + 1;
        while (next < end && entries[next].$1[depth] == first[depth]) {
          next++;
        }
        final last = entries[next - 1].$1;
        var common = depth + 1;
        while (common < first.length &&
            common < last.length &&
            first[common] == last[common]) {
          common++;
        }
        node.children.add(
          build(start, next, common, first.sublist(depth, common)),
        );
        start = next;
      }
      return node;
    }

    build(0, entries.length, 0, const []);
    void uleb(BytesBuilder bytes, int value) {
      do {
        final byte = value & 127;
        value >>= 7;
        bytes.addByte(byte | (value == 0 ? 0 : 128));
      } while (value != 0);
    }

    var changed = true;
    var result = Uint8List(0);
    // Child offsets can grow the ULEB fields; settle their widths before returning.
    while (changed) {
      changed = false;
      final bytes = BytesBuilder(copy: false);
      for (final node in nodes) {
        if (node.offset != bytes.length) {
          node.offset = bytes.length;
          changed = true;
        }
        final terminal = BytesBuilder(copy: false);
        if (node.address case final address?) {
          terminal.addByte(0);
          uleb(terminal, address);
        }
        uleb(bytes, terminal.length);
        bytes.add(terminal.takeBytes());
        bytes.addByte(node.children.length);
        for (final child in node.children) {
          bytes.add(child.edge);
          bytes.addByte(0);
          uleb(bytes, child.offset);
        }
      }
      result = bytes.takeBytes();
    }
    return result;
  }
}

final class _Node(final List<int> edge) {
  int? address;
  int offset = 0;
  final List<_Node> children = [];
}
