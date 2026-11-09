import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/target.dart';

import '../object_module.dart';
import '../reader.dart';
import '../relocation.dart';
import '../section.dart';
import '../symbol.dart';

/// Decodes the supported ELF64 relocatable sections and symbol references.
final class ElfReader(final Target target, Uint8List bytes) {
  final ObjectReader input = .new(bytes);

  ObjectModule read() {
    final data = input.data;
    input.region(0, 64);
    input.check(data.getUint32(0, .big) == 0x7f454c46, 'Invalid ELF magic.');
    if (data.getUint8(4) != 2 ||
        data.getUint8(5) != 1 ||
        data.getUint8(6) != 1 ||
        data.getUint8(7) != 0 ||
        data.getUint8(8) != 0 ||
        data.getUint16(16, .little) != 1 ||
        data.getUint16(18, .little) !=
            (target.architecture == .arm64 ? 183 : 62)) {
      throw UnsupportedError(
        'Expected a little-endian ELF64 object for $target.',
      );
    }
    input.check(
      data.getUint32(20, .little) == 1 &&
          input.view(9, 7).every((byte) => byte == 0),
      'Invalid ELF header version or padding.',
    );
    if (input.u64(24) != 0 ||
        input.u64(32) != 0 ||
        data.getUint32(48, .little) != 0 ||
        data.getUint16(54, .little) != 0 ||
        data.getUint16(56, .little) != 0) {
      throw UnsupportedError(
        'ELF object entry, program headers or processor flags.',
      );
    }
    input.check(
      data.getUint16(52, .little) == 64 && data.getUint16(58, .little) == 64,
      'Invalid ELF header sizes.',
    );
    final sectionOffset = input.u64(40), count = data.getUint16(60, .little);
    final nameIndex = data.getUint16(62, .little);
    if (count == 0 || count >= 0xff00 || nameIndex >= 0xff00) {
      throw UnsupportedError('ELF extended section indices.');
    }
    input.alignment(8, sectionOffset);
    input.table(sectionOffset, count, 64);
    input.check(
      nameIndex > 0 && nameIndex < count,
      'Invalid ELF section-name index.',
    );
    input.check(
      input.view(sectionOffset, 64).every((b) => b == 0),
      'Invalid ELF null section.',
    );
    final headers = [
      for (var i = 0; i < count; i++)
        _SectionHeader(input, sectionOffset + i * 64),
    ];
    final names = headers[nameIndex];
    input.check(
      names.type == 3 && names.size > 0,
      'Missing ELF section-name table.',
    );
    input.view(names.offset, names.size);
    final sections = <Section>[], sectionMap = List.filled(count, -1);
    var symbolIndex = -1;
    for (var i = 1; i < count; i++) {
      final h = headers[i];
      input.check(h.name < names.size, 'Invalid ELF section name.');
      h.text = input.string(names.offset + h.name, names.offset + names.size);
      input.alignment(h.alignment == 0 ? 1 : h.alignment, h.offset);
      if (h.type != 8) input.region(h.offset, h.size);
      if (h.address != 0) {
        throw UnsupportedError('ELF object section addresses.');
      }
      final kind = switch ((h.type, h.flags, h.text)) {
        (1, 6, '.text') => SectionKind.code,
        (1, 2, '.rodata') => SectionKind.readOnlyData,
        (1, 3, '.data') => SectionKind.data,
        (8, 3, '.bss') => SectionKind.zeroFill,
        _ => null,
      };
      if (kind != null) {
        if (h.link != 0 || h.info != 0 || h.entrySize != 0) {
          throw UnsupportedError('ELF storage section attributes.');
        }
        final alignment = h.alignment == 0 ? 1 : h.alignment;
        sectionMap[i] = sections.length;
        sections.add(switch (kind) {
          .code => .code(input.view(h.offset, h.size), alignment: alignment),
          .readOnlyData => .readOnlyData(
            input.view(h.offset, h.size),
            alignment: alignment,
          ),
          .data => .data(input.view(h.offset, h.size), alignment: alignment),
          .zeroFill => .zeroFill(h.size, alignment: alignment),
        });
      } else if (h.flags == 0 && h.type == 2) {
        input.check(symbolIndex == -1, 'Multiple ELF symbol tables.');
        symbolIndex = i;
      } else if (h.flags == 0 && (h.type == 3 || h.type == 4)) {
        // Their links are checked after all section identities are known.
      } else if (h.type != 1 ||
          h.flags != 0 ||
          h.text != '.note.GNU-stack' ||
          h.size != 0 ||
          h.link != 0 ||
          h.info != 0 ||
          h.entrySize != 0) {
        throw UnsupportedError(
          'ELF section ${h.text} (type ${h.type}, flags ${h.flags}).',
        );
      }
    }
    input.check(symbolIndex > 0, 'Missing ELF symbol table.');
    final table = headers[symbolIndex];
    input.check(
      table.entrySize == 24 &&
          table.size >= 24 &&
          table.size % 24 == 0 &&
          table.link > 0 &&
          table.link < count,
      'Invalid ELF symbol table.',
    );
    final strings = headers[table.link];
    input.check(
      strings.type == 3 && strings.size > 0,
      'Invalid ELF symbol strings.',
    );
    for (var i = 1; i < count; i++) {
      final h = headers[i];
      if (h.type == 3) {
        if (i != nameIndex && i != table.link) {
          throw UnsupportedError('Extra ELF string table.');
        }
        input.check(
          h.link == 0 &&
              h.info == 0 &&
              h.entrySize == 0 &&
              input.bytes[h.offset] == 0 &&
              input.bytes[h.offset + h.size - 1] == 0,
          'Invalid ELF string table.',
        );
      }
    }
    final symbolCount = table.size ~/ 24,
        indices = List.filled(table.size ~/ 24, 0);
    input.check(
      table.info > 0 && table.info <= symbolCount,
      'Invalid ELF local symbol boundary.',
    );
    input.check(
      input.view(table.offset, 24).every((b) => b == 0),
      'Invalid ELF null symbol.',
    );
    final symbols = <Symbol>[], imports = <String>[];
    for (var i = 1; i < symbolCount; i++) {
      final at = table.offset + i * 24, name = data.getUint32(at, .little);
      final info = data.getUint8(at + 4), visibility = data.getUint8(at + 5);
      final section = data.getUint16(at + 6, .little),
          value = input.u64(at + 8);
      final size = input.u64(at + 16), binding = info >> 4, type = info & 15;
      input.check(name < strings.size, 'Invalid ELF symbol name.');
      final text = input.string(
        strings.offset + name,
        strings.offset + strings.size,
      );
      if (binding > 1 || type > 2 || (visibility != 0 && visibility != 2)) {
        throw UnsupportedError('ELF symbol binding, type or visibility.');
      }
      input.check(
        (i < table.info) == (binding == 0),
        'Invalid ELF symbol ordering.',
      );
      if (section == 0) {
        if (binding != 1 ||
            type != 0 ||
            visibility != 0 ||
            value != 0 ||
            size != 0) {
          throw UnsupportedError('ELF typed, weak or common import.');
        }
        indices[i] = -imports.length - 1;
        imports.add(text);
      } else {
        if (section >= 0xff00) {
          throw UnsupportedError('ELF special symbol section.');
        }
        input.check(
          section < count && sectionMap[section] >= 0,
          'Invalid ELF symbol section.',
        );
        if (binding == 0 && visibility != 0) {
          throw UnsupportedError('ELF local visibility.');
        }
        indices[i] = symbols.length;
        symbols.add(
          Symbol(
            text,
            sectionMap[section],
            value,
            size == 0 ? null : size,
            kind: switch (type) {
              1 => .data,
              2 => .function,
              _ => .unknown,
            },
            binding: binding == 0 ? .local : .global,
            exported: binding == 1 && visibility == 0,
          ),
        );
      }
    }
    final references = <Relocation>[];
    for (final h in headers.skip(1)) {
      if (h.type != 4) continue;
      input.check(
        h.link == symbolIndex &&
            h.info > 0 &&
            h.info < count &&
            sectionMap[h.info] >= 0 &&
            h.entrySize == 24 &&
            h.size % 24 == 0,
        'Invalid ELF relocation section.',
      );
      if (h.text != '.rela${headers[h.info].text}') {
        throw UnsupportedError('ELF relocation section name.');
      }
      final section = sectionMap[h.info];
      for (var at = h.offset; at < h.offset + h.size; at += 24) {
        final offset = input.u64(at), info = data.getUint64(at + 8, .little);
        final symbol = info >>> 32, type = info & 0xffffffff;
        input.check(
          symbol > 0 && symbol < symbolCount,
          'Invalid ELF relocation symbol.',
        );
        final FixupEncoding encoding;
        if (target.architecture == .arm64) {
          encoding = switch (type) {
            283 => .arm64Call26,
            275 => .arm64Page21,
            277 => .arm64PageOffset12,
            _ => throw UnsupportedError('AArch64 ELF relocation $type.'),
          };
        } else if (type == 4) {
          encoding = .x64Call32;
        } else if (type == 2) {
          final bytes = sections[section].bytes;
          input.check(
            offset > 0 && offset <= bytes.length - 4,
            'Invalid ELF relocation offset.',
          );
          encoding = bytes[offset - 1] == 0xe8 ? .x64Call32 : .x64Address32;
        } else {
          throw UnsupportedError('x86-64 ELF relocation $type.');
        }
        if (data.getInt64(at + 16, .little) !=
            (target.architecture == .arm64 ? 0 : -4)) {
          throw UnsupportedError('ELF symbol addends.');
        }
        final index = indices[symbol];
        references.add(
          Relocation(
            section,
            offset,
            encoding,
            index < 0 ? symbols.length - index - 1 : index,
          ),
        );
      }
    }
    return input.finish(target, sections, symbols, imports, references);
  }
}

final class _SectionHeader(ObjectReader input, int at) {
  final int name = input.data.getUint32(at, .little);
  final int type = input.data.getUint32(at + 4, .little);
  final int flags = input.u64(at + 8);
  final int address = input.u64(at + 16);
  final int offset = input.u64(at + 24);
  final int size = input.u64(at + 32);
  final int link = input.data.getUint32(at + 40, .little);
  final int info = input.data.getUint32(at + 44, .little);
  final int alignment = input.u64(at + 48);
  final int entrySize = input.u64(at + 56);
  String text = '';
}
