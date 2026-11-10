import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/target.dart';

import '../object_module.dart';
import '../reader.dart';
import '../relocation.dart';
import '../section.dart';
import '../symbol.dart';

/// Decodes Mach-O object sections and external symbol-index relocations.
final class MachOReader(final Target target, Uint8List bytes) {
  final ObjectReader input = .new(bytes);

  ObjectModule read() {
    final data = input.data;
    input.view(0, 32);
    input.check(
      data.getUint32(0, .little) == 0xfeedfacf,
      'Invalid Mach-O 64-bit magic.',
    );
    if (data.getUint32(4, .little) !=
            (target.architecture == .arm64 ? 0x100000c : 0x1000007) ||
        data.getUint32(8, .little) != (target.architecture == .arm64 ? 0 : 3) ||
        data.getUint32(12, .little) != 1 ||
        data.getUint32(24, .little) & ~0x2000 != 0) {
      throw UnsupportedError(
        'Expected a Mach-O object for $target without extra header flags.',
      );
    }
    input.check(
      data.getUint32(28, .little) == 0,
      'Invalid Mach-O reserved header.',
    );
    final commands = data.getUint32(16, .little),
        end = 32 + data.getUint32(20, .little);
    input.region(0, end);
    input.check(commands <= (end - 32) ~/ 8, 'Invalid Mach-O command count.');
    final headers = <_SectionHeader>[];
    int? segment, symtab, dysymtab;
    var cursor = 32, hasBuild = false;
    for (var i = 0; i < commands; i++) {
      input.check(cursor <= end - 8, 'Truncated Mach-O command.');
      final command = data.getUint32(cursor, .little),
          size = data.getUint32(cursor + 4, .little);
      input.check(
        size >= 8 && size % 8 == 0 && size <= end - cursor,
        'Invalid Mach-O command size.',
      );
      switch (command) {
        case 0x19:
          input.check(
            segment == null && size >= 72,
            'Invalid Mach-O object segment.',
          );
          segment = cursor;
          final count = data.getUint32(cursor + 64, .little);
          input.check(
            count <= (size - 72) ~/ 80 && size == 72 + count * 80,
            'Invalid Mach-O section count.',
          );
          if (count > 255) {
            throw UnsupportedError('Mach-O section index exceeds eight bits.');
          }
          if (input.string(cursor + 8, cursor + 24, fixed: true).isNotEmpty ||
              data.getUint32(cursor + 56, .little) != 7 ||
              data.getUint32(cursor + 60, .little) != 7 ||
              data.getUint32(cursor + 68, .little) != 0) {
            throw UnsupportedError('Mach-O object segment attributes.');
          }
          for (var j = 0; j < count; j++) {
            headers.add(_SectionHeader(input, cursor + 72 + j * 80));
          }
        case 2:
          input.check(
            symtab == null && size == 24,
            'Invalid Mach-O symbol command.',
          );
          symtab = cursor;
        case 0xb:
          input.check(
            dysymtab == null && size == 80,
            'Invalid Mach-O dynamic symbol command.',
          );
          dysymtab = cursor;
          if (input.view(cursor + 32, 48).any((byte) => byte != 0)) {
            throw UnsupportedError(
              'Mach-O indirect symbols or dynamic relocations.',
            );
          }
        case 0x32:
          input.check(!hasBuild && size >= 24, 'Invalid Mach-O build version.');
          hasBuild = true;
          final tools = data.getUint32(cursor + 20, .little);
          input.check(
            tools <= (size - 24) ~/ 8 && size == 24 + tools * 8,
            'Invalid Mach-O build tools.',
          );
          if (data.getUint32(cursor + 8, .little) != 1 ||
              data.getUint32(cursor + 12, .little) > 0xb0000) {
            throw UnsupportedError('Mach-O platform or deployment version.');
          }
        default:
          throw UnsupportedError('Mach-O load command $command.');
      }
      cursor += size;
    }
    input.check(
      cursor == end && segment != null && symtab != null,
      'Missing or inconsistent Mach-O commands.',
    );
    final base = segment!, table = symtab!;
    final address = input.u64(base + 24), memorySize = input.u64(base + 32);
    final fileOffset = input.u64(base + 40), fileSize = input.u64(base + 48);
    input.view(fileOffset, fileSize);
    input.check(
      fileSize <= memorySize && memorySize <= 0x7fffffffffffffff - address,
      'Invalid Mach-O segment size.',
    );
    final sections = <Section>[];
    for (final h in headers) {
      if (h.shift > 62) {
        throw UnsupportedError('Mach-O section alignment exceeds 2^62.');
      }
      final alignment = 1 << h.shift;
      input.alignment(alignment, h.address);
      input.check(
        h.address >= address &&
            h.address - address <= memorySize &&
            h.size <= memorySize - (h.address - address),
        'Mach-O section exceeds its segment.',
      );
      if (h.reserved) {
        throw UnsupportedError('Mach-O reserved section attributes.');
      }
      final kind = switch ((h.name, h.segment, h.flags)) {
        ('__text', '__TEXT', 0x80000400) => SectionKind.code,
        ('__const', '__CONST', 0) => SectionKind.readOnlyData,
        ('__data', '__DATA', 0) => SectionKind.data,
        ('__bss', '__DATA', 1) => SectionKind.zeroFill,
        ('__mod_term_func', '__DATA', 0xa) => SectionKind.finalizers,
        _ => throw UnsupportedError(
          'Mach-O section ${h.segment},${h.name} (${h.flags}).',
        ),
      };
      if (kind == .finalizers) {
        input.check(
          alignment == 8 && h.size % 8 == 0,
          'Invalid Mach-O finalizer array.',
        );
      }
      if (kind == .zeroFill) {
        input.check(
          h.offset == 0,
          'Mach-O zero-fill section has file contents.',
        );
        sections.add(.zeroFill(h.size, alignment: alignment));
      } else {
        input.alignment(alignment, h.offset);
        input.check(
          h.offset >= fileOffset &&
              h.offset - fileOffset <= fileSize &&
              h.size <= fileSize - (h.offset - fileOffset) &&
              h.offset - fileOffset == h.address - address,
          'Invalid Mach-O section placement.',
        );
        input.region(h.offset, h.size);
        final content = input.view(h.offset, h.size);
        sections.add(switch (kind) {
          .code => .code(content, alignment: alignment),
          .finalizers => .finalizers(content),
          .readOnlyData => .readOnlyData(content, alignment: alignment),
          _ => .data(content, alignment: alignment),
        });
      }
      input.alignment(4, h.relocations);
      input.table(h.relocations, h.relocationCount, 8);
    }
    var sectionEnd = address;
    final ordered = headers.toList()
      ..sort((a, b) => a.address.compareTo(b.address));
    for (final h in ordered) {
      if (h.size == 0) continue;
      input.check(
        h.address >= sectionEnd,
        'Overlapping Mach-O section addresses.',
      );
      sectionEnd = h.address + h.size;
    }
    final symbolOffset = data.getUint32(table + 8, .little),
        count = data.getUint32(table + 12, .little);
    final strings = data.getUint32(table + 16, .little),
        stringSize = data.getUint32(table + 20, .little);
    input.table(symbolOffset, count, 16);
    input.region(strings, stringSize);
    input.check(
      stringSize > 0 &&
          input.bytes[strings] == 0 &&
          input.bytes[strings + stringSize - 1] == 0,
      'Invalid Mach-O string table.',
    );
    final indices = List.filled(count, 0),
        symbols = <Symbol>[],
        imports = <String>[];
    var localCount = 0;
    for (var i = 0; i < count; i++) {
      final at = symbolOffset + i * 16, name = data.getUint32(at, .little);
      final type = data.getUint8(at + 4), section = data.getUint8(at + 5);
      final value = input.u64(at + 8);
      input.check(name < stringSize, 'Invalid Mach-O symbol name.');
      final text = input.string(strings + name, strings + stringSize);
      if (data.getUint16(at + 6, .little) != 0) {
        throw UnsupportedError('Mach-O symbol descriptor.');
      }
      if (type == 1) {
        if (section != 0 || value != 0) {
          throw UnsupportedError('Mach-O common symbol.');
        }
        indices[i] = -imports.length - 1;
        imports.add(text);
      } else if (type == 0xe || type == 0xf || type == 0x1f) {
        input.check(
          section > 0 && section <= headers.length,
          'Invalid Mach-O symbol section.',
        );
        indices[i] = symbols.length;
        if (type == 0xe) localCount++;
        symbols.add(
          Symbol(
            text,
            section - 1,
            value - headers[section - 1].address,
            null,
            kind: .unknown,
            binding: type == 0xe ? .local : .global,
            exported: type == 0xf,
          ),
        );
      } else {
        throw UnsupportedError('Mach-O symbol type $type.');
      }
      if (dysymtab case final at?) {
        final locals = data.getUint32(at + 12, .little),
            defined = data.getUint32(at + 24, .little);
        input.check(
          (i < locals) == (type == 0xe) && (i >= defined) == (type == 1),
          'Invalid Mach-O symbol ordering.',
        );
      }
    }
    if (dysymtab case final at?) {
      final expected = [
        0,
        localCount,
        localCount,
        symbols.length - localCount,
        symbols.length,
        imports.length,
      ];
      for (final (i, value) in expected.indexed) {
        input.check(
          data.getUint32(at + 8 + i * 4, .little) == value,
          'Invalid Mach-O symbol table partition.',
        );
      }
    }
    final references = <Relocation>[];
    for (final (section, h) in headers.indexed) {
      for (var i = 0; i < h.relocationCount; i++) {
        final at = h.relocations + i * 8, offset = data.getUint32(at, .little);
        final info = data.getUint32(at + 4, .little), symbol = info & 0xffffff;
        if (offset & 0x80000000 != 0) {
          throw UnsupportedError('Mach-O scattered relocation.');
        }
        input.check(symbol < count, 'Invalid Mach-O relocation symbol.');
        final code = sections[section].bytes;
        final index = indices[symbol];
        final destination = index < 0 ? symbols.length - index - 1 : index;
        if (info >> 24 == 0x0e) {
          input.check(
            offset <= code.length - 8,
            'Invalid Mach-O address relocation offset.',
          );
          if (ByteData.sublistView(code).getUint64(offset, .little) != 0) {
            throw UnsupportedError('Mach-O address addends.');
          }
          references.add(.address(section, offset, destination));
          continue;
        }
        input.check(
          offset <= code.length - 4,
          'Invalid Mach-O relocation offset.',
        );
        final encoding = switch ((target.architecture, info >> 24)) {
          (.arm64, 0x2d) => FixupEncoding.arm64Call26,
          (.arm64, 0x3d || 0x5d) => FixupEncoding.arm64Page21,
          (.arm64, 0x4c) =>
            ByteData.sublistView(code).getUint32(offset, .little) &
                        0xffc00000 ==
                    0xf9400000
                ? FixupEncoding.arm64LoadPageOffset12
                : FixupEncoding.arm64PageOffset12,
          (.arm64, 0x6c) => FixupEncoding.arm64LoadPageOffset12,
          (.x64, 0x2d) => FixupEncoding.x64Call32,
          (.x64, 0x1d) =>
            offset >= 3 && code[offset - 2] == 0x8b
                ? FixupEncoding.x64LoadAddress32
                : FixupEncoding.x64Address32,
          (.x64, 0x3d) => FixupEncoding.x64LoadAddress32,
          _ => throw UnsupportedError('Mach-O relocation flags ${info >> 24}.'),
        };
        references.add(
          Relocation.instruction(
            section,
            offset,
            encoding,
            destination,
            indirect: target.architecture == .arm64
                ? info >> 24 == 0x5d || info >> 24 == 0x6c
                : info >> 24 == 0x3d,
          ),
        );
      }
    }
    return input.finish(target, sections, symbols, imports, references);
  }
}

final class _SectionHeader(ObjectReader input, int at) {
  final String name = input.string(at, at + 16, fixed: true);
  final String segment = input.string(at + 16, at + 32, fixed: true);
  final int address = input.u64(at + 32);
  final int size = input.u64(at + 40);
  final int offset = input.data.getUint32(at + 48, .little);
  final int shift = input.data.getUint32(at + 52, .little);
  final int relocations = input.data.getUint32(at + 56, .little);
  final int relocationCount = input.data.getUint32(at + 60, .little);
  final int flags = input.data.getUint32(at + 64, .little);
  final bool reserved = input.view(at + 68, 12).any((byte) => byte != 0);
}
