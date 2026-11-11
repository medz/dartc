import 'dart:io';
import 'dart:typed_data';

import 'mach_o/code_signature.dart';

/// Reads or appends resources in a Dart SDK AOT executable.
///
/// Supports thin 64-bit macOS and Linux executables. Embedding returns a new
/// image, preserves the SDK snapshot, and replaces an ad-hoc Mach-O signature.
/// Unsupported layouts and signatures throw [FormatException].
final class ExecutableResources(final File executable) {
  static const _magic = 0x3153524354524144; // DARTCRS1.
  static const _recordSize = 32;

  /// Reads the embedded payload without reading the executable's code.
  Uint8List read() {
    final input = executable.openSync();
    try {
      final image = _Image(input);
      final (offset, length) =
          _location(image) ??
          (throw const FormatException('Executable has no source resources.'));
      return image.read(offset, length);
    } finally {
      input.closeSync();
    }
  }

  /// Appends [resources] to an unbundled executable, leaving its file untouched.
  Uint8List embed(Uint8List resources) {
    if (resources.isEmpty || resources.length > 32 << 20) {
      throw ArgumentError('Resources must contain between 1 byte and 32 MiB.');
    }
    final input = executable.openSync();
    try {
      final image = _Image(input);
      if (_location(image) != null) {
        throw const FormatException('Executable already contains resources.');
      }
      final end = (image.end + resources.length + 15) & ~15;
      final codeLimit = end + _recordSize;
      final signature = image.signature == null
          ? null
          : CodeSignature('dartc', codeLimit, image.textSize, executable: true);
      final output = Uint8List(codeLimit + (signature?.size ?? 16));
      output.setAll(0, image.read(0, image.end));
      output.setAll(image.end, resources);
      final data = ByteData.sublistView(output);
      data.setUint64(end, _magic, .little);
      data.setUint64(end + 8, image.end, .little);
      data.setUint64(end + 16, resources.length, .little);
      data.setUint32(end + 24, 1, .little);
      if (signature == null) {
        output.setAll(codeLimit, image.read(image.end, 16));
      } else {
        final command = image.signature!;
        final segment = image.linkEdit!;
        final fileOffset = data.getUint64(segment + 40, .little);
        final size = output.length - fileOffset;
        data.setUint64(segment + 32, (size + 16383) & ~16383, .little);
        data.setUint64(segment + 48, size, .little);
        data.setUint32(command + 8, codeLimit, .little);
        data.setUint32(command + 12, signature.size, .little);
        signature.write(output);
      }
      return output;
    } finally {
      input.closeSync();
    }
  }

  (int, int)? _location(_Image image) {
    if (image.end < _recordSize) return null;
    final data = ByteData.sublistView(
      image.read(image.end - _recordSize, _recordSize),
    );
    if (data.getUint64(0, .little) != _magic) return null;
    final offset = data.getUint64(8, .little);
    final length = data.getUint64(16, .little);
    if (data.getUint32(24, .little) != 1 ||
        data.getUint32(28, .little) != 0 ||
        offset < image.minimum ||
        length <= 0 ||
        length > 32 << 20 ||
        offset > image.end - _recordSize ||
        length > image.end - _recordSize - offset ||
        image.end - _recordSize - offset - length >= 16) {
      throw const FormatException('Invalid executable resource range.');
    }
    return (offset, length);
  }
}

final class _Image(final RandomAccessFile input) {
  final int length = input.lengthSync();
  late final int end;
  int minimum = 0, textSize = 0;
  int? signature, linkEdit;

  this {
    final header = ByteData.sublistView(read(0, 64));
    switch (header.getUint32(0, .little)) {
      case 0x464c457f:
        if (header.getUint8(4) != 2 ||
            header.getUint8(5) != 1 ||
            !{2, 3}.contains(header.getUint16(16, .little)) ||
            !{62, 183}.contains(header.getUint16(18, .little))) {
          throw const FormatException('Expected a 64-bit Linux executable.');
        }
        end = length - 16;
        final footer = ByteData.sublistView(read(end, 16));
        minimum = footer.getUint64(0, .little);
        if (footer.getUint64(8, .little) != 0xf6f6dcdc ||
            minimum < 64 ||
            minimum % 65536 != 0 ||
            minimum >= end ||
            ByteData.sublistView(read(minimum, 4)).getUint32(0, .little) !=
                0x464c457f) {
          throw const FormatException('Invalid SDK snapshot footer.');
        }
      case 0xfeedfacf:
        _machO(header);
      default:
        throw const FormatException('Unsupported executable format.');
    }
  }

  Uint8List read(int offset, int size) {
    if (offset < 0 || offset > length || size < 0 || size > length - offset) {
      throw const FormatException('Executable range exceeds file bounds.');
    }
    input.setPositionSync(offset);
    final bytes = input.readSync(size);
    if (bytes.length != size) {
      throw const FormatException('Truncated executable.');
    }
    return bytes;
  }

  void _machO(ByteData header) {
    if (!{0x1000007, 0x100000c}.contains(header.getUint32(4, .little)) ||
        header.getUint32(12, .little) != 2) {
      throw const FormatException('Expected a thin 64-bit macOS executable.');
    }
    final size = header.getUint32(20, .little);
    final count = header.getUint32(16, .little);
    if (size > 65536 || count > size ~/ 8) {
      throw const FormatException('Invalid Mach-O command table.');
    }
    final data = ByteData.sublistView(read(0, 32 + size));
    var at = 32, snapshot = false, lastVmEnd = 0;
    for (var i = 0; i < count; i++) {
      if (at > data.lengthInBytes - 8) {
        throw const FormatException('Truncated load command.');
      }
      final command = data.getUint32(at, .little);
      final size = data.getUint32(at + 4, .little);
      if (size < 8 || size % 8 != 0 || size > data.lengthInBytes - at) {
        throw const FormatException('Invalid load command size.');
      }
      if (command == 0x19) {
        if (size < 72) throw const FormatException('Truncated segment.');
        final name = String.fromCharCodes(
          read(at + 8, 16).takeWhile((c) => c != 0),
        );
        final offset = data.getUint64(at + 40, .little);
        final bytes = data.getUint64(at + 48, .little);
        final address = data.getUint64(at + 24, .little);
        final vmSize = data.getUint64(at + 32, .little);
        if (offset < 0 ||
            bytes < 0 ||
            offset > length ||
            bytes > length - offset ||
            address < lastVmEnd ||
            vmSize < bytes ||
            address + vmSize < address) {
          throw const FormatException('Invalid Mach-O segment range.');
        }
        lastVmEnd = address + vmSize;
        if (linkEdit != null) {
          throw const FormatException('__LINKEDIT must be the last segment.');
        }
        if (name == '__TEXT') {
          if (offset != 0) {
            throw const FormatException('Unsupported __TEXT offset.');
          }
          textSize = bytes;
        }
        if (name == '__LINKEDIT') {
          if (offset + bytes != length) {
            throw const FormatException('Unsupported __LINKEDIT range.');
          }
          linkEdit = at;
          minimum = offset;
        }
      } else if (command == 0x31) {
        if (size != 40) throw const FormatException('Invalid Mach-O note.');
        if (String.fromCharCodes(read(at + 8, 16).takeWhile((c) => c != 0)) ==
            '__dart_app_snap') {
          final offset = data.getUint64(at + 24, .little);
          final bytes = data.getUint64(at + 32, .little);
          if (snapshot ||
              offset < data.lengthInBytes ||
              bytes <= 0 ||
              offset > length ||
              bytes > length - offset) {
            throw const FormatException('Invalid SDK snapshot note.');
          }
          snapshot = true;
        }
      } else if (command == 0x1d) {
        if (size != 16 || signature != null) {
          throw const FormatException('Invalid signature command.');
        }
        signature = at;
        end = data.getUint32(at + 8, .little);
        if (data.getUint32(at + 12, .little) != length - end) {
          throw const FormatException(
            'Signature must end at the file boundary.',
          );
        }
      }
      at += size;
    }
    if (at != data.lengthInBytes ||
        !snapshot ||
        signature == null ||
        linkEdit == null ||
        textSize == 0 ||
        end < minimum) {
      throw const FormatException('Unsupported SDK executable layout.');
    }
    _signature();
  }

  void _signature() {
    final data = ByteData.sublistView(read(end, length - end));
    if (data.lengthInBytes < 12 || data.getUint32(0) != 0xfade0cc0) {
      throw const FormatException('Invalid code signature.');
    }
    final size = data.getUint32(4), count = data.getUint32(8);
    if (size > data.lengthInBytes || count > (size - 12) ~/ 8) {
      throw const FormatException('Invalid signature table.');
    }
    var directory = false;
    for (var i = 0; i < count; i++) {
      final slot = data.getUint32(12 + i * 8),
          offset = data.getUint32(16 + i * 8);
      if (offset < 12 + count * 8 || offset > size - 8) {
        throw const FormatException('Invalid signature blob.');
      }
      final magic = data.getUint32(offset), bytes = data.getUint32(offset + 4);
      if (bytes < 8 || bytes > size - offset) {
        throw const FormatException('Invalid signature blob size.');
      }
      if (slot == 0 && magic == 0xfade0c02 && bytes >= 88) {
        final flags = data.getUint32(offset + 12);
        if (directory ||
            flags & 2 == 0 ||
            flags & ~0x20002 != 0 ||
            data.getUint32(offset + 32) != end) {
          throw const FormatException(
            'Only ad-hoc signatures can be replaced.',
          );
        }
        directory = true;
      } else if (!(slot == 2 &&
              magic == 0xfade0c01 &&
              bytes == 12 &&
              data.getUint32(offset + 8) == 0) &&
          !(slot == 0x10000 && magic == 0xfade0b01 && bytes == 8)) {
        throw const FormatException(
          'Cannot discard signature requirements or entitlements.',
        );
      }
    }
    if (!directory) throw const FormatException('Missing code directory.');
  }
}
