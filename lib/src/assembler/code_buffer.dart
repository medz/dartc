import 'dart:typed_data';

import 'fixup.dart';

/// A code position created and bound by one assembler.
final class Label._(final CodeBuffer _owner) {
  int? _offset;
}

/// Owns an assembler's bytes, local labels and completion state.
final class CodeBuffer() {
  final _bytes = BytesBuilder(copy: false);
  final _labels = <Label>[];
  final _branches = <(Fixup, Label)>[];
  var _finished = false;

  int get length {
    checkOpen();
    return _bytes.length;
  }

  void checkOpen() {
    if (_finished) throw StateError('Assembler is finished.');
  }

  void add(List<int> bytes) {
    checkOpen();
    _bytes.add(bytes);
  }

  void addByte(int byte) {
    checkOpen();
    _bytes.addByte(byte);
  }

  Label label() {
    checkOpen();
    final label = Label._(this);
    _labels.add(label);
    return label;
  }

  void _checkLabel(Label label) {
    checkOpen();
    if (!identical(label._owner, this)) {
      throw ArgumentError('Label belongs to another assembler.');
    }
  }

  void bind(Label label) {
    _checkLabel(label);
    if (label._offset != null) throw StateError('Label is already bound.');
    label._offset = length;
  }

  void branch(Fixup fixup, Label label) {
    _checkLabel(label);
    _branches.add((fixup, label));
  }

  Uint8List finish() {
    checkOpen();
    _finished = true;
    final bytes = _bytes.takeBytes(), data = ByteData.sublistView(bytes);
    if (_labels.any((label) => label._offset == null)) {
      throw StateError('Assembler has an unbound label.');
    }
    for (final (fixup, label) in _branches) {
      fixup.encoding.apply(
        data,
        fixup.offset,
        placeAddress: fixup.offset,
        targetAddress: label._offset!,
      );
    }
    return bytes.asUnmodifiableView();
  }
}
