import 'layout.dart' show align16;

/// Where a part of a file is, and where it is loaded.
final class ElfPart(final int offset, final int address, final int bytes) {
  int get end => offset + bytes;
  int get addressEnd => address + bytes;
}

/// Where each part of an ELF image is.
///
/// The first segment has the headers, tables for the loader and constants. The
/// second has code and import stubs, the third import slots and constant
/// objects, and the last writable objects. Each is loaded at pages of its own,
/// and there is nothing between them in the file.
final class ElfLayout({
  /// The unit of memory protection.
  required final int pageBytes,
  required final int stubBytes,
  required final int headerBytes,

  /// The tables for the loader, by their names, in order.
  required final Map<String, int> tables,
  required final int constantBytes,
  required final int codeBytes,
  required final int importCount,
  required final int dynamicBytes,
  required final int constObjectBytes,
  required final int dataBytes,
}) {
  late final parts = _place();

  /// The first and the last part of each segment.
  late final ElfPart headers = ElfPart(0, 0, parts['constants']!.end);
  late final ElfPart code = _segment('text', 'stubs');
  late final ElfPart constant = _segment('dynamic', 'constObjects');
  late final ElfPart data = parts['data']!;

  ElfPart operator [](String name) => parts[name]!;

  ElfPart _segment(String first, String last) {
    final ElfPart(:offset, :address) = parts[first]!;
    return ElfPart(offset, address, parts[last]!.end - offset);
  }

  Map<String, ElfPart> _place() {
    final result = <String, ElfPart>{};
    var offset = headerBytes, segment = 0;
    void part(String name, int bytes) {
      offset = align16(offset);
      result[name] = ElfPart(offset, offset + segment * pageBytes, bytes);
      offset += bytes;
    }

    tables.forEach(part);
    part('constants', constantBytes);
    segment++;
    part('text', codeBytes);
    part('stubs', importCount * stubBytes);
    segment++;
    part('dynamic', dynamicBytes);
    part('slots', importCount * 8);
    part('constObjects', constObjectBytes);
    segment++;
    part('data', dataBytes);
    return result;
  }

  /// Where the memory that only relocations change ends.
  int get constantEnd =>
      (constant.addressEnd + pageBytes - 1) ~/ pageBytes * pageBytes;
}
