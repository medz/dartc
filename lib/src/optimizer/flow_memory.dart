import 'dart:ffi' show Uint8;
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/interop.dart';

import 'flow_value.dart';
import 'integer_range.dart';
import 'state_map.dart';

typedef NativeWordProofs = (bool Function(FlowValue), bool Function(FlowValue));

/// Byte intervals a call may have written. Whole-object changes include a
/// new mapping, release, and any access whose destination is unknown.
final class FlowWrites {
  final StateMap<int, int>? _ranges;
  const FlowWrites.all() : _ranges = null;
  const FlowWrites._(this._ranges);
  factory FlowWrites.bytes(int offset, int end) =>
      FlowWrites._(const StateMap<int, int>.empty().withEntry(offset, end));

  FlowWrites join(FlowWrites other) {
    final ranges = _ranges, incoming = other._ranges;
    if (ranges == null || identical(ranges, incoming)) return this;
    if (incoming == null) return other;
    var joined = ranges;
    for (final item in incoming.entries) {
      var start = item.key, end = item.value;
      final exact = joined[start];
      if (exact != null && exact >= end) continue;
      for (final old in joined.entries) {
        if (old.value < start || old.key > end) continue;
        if (old.key < start) start = old.key;
        if (old.value > end) end = old.value;
        joined = joined.withoutKey(old.key);
      }
      joined = joined.withEntry(start, end);
    }
    return joined == ranges ? this : FlowWrites._(joined);
  }

  @override
  bool operator ==(Object other) =>
      other is FlowWrites && _ranges == other._ranges;
  @override
  int get hashCode => _ranges.hashCode;
}

/// Byte facts for one allocation, without materializing its unused zeroes.
final class FlowMemory {
  final int start;
  /// The number of bytes present on every live alternative.
  final int? length;

  /// The largest complete extent. Releasing only [length] may leave a tail.
  final int? maximumLength;
  final List<(int, int)> _zeroes;
  final StateMap<int, _Byte> _bytes;
  final FlowValue _retained;
  // Correlations between bytes of a complete native 64-bit integer store.
  // A join of zero and an address can retain both complete words even when
  // the individual bytes no longer decode to either value.
  final StateMap<int, FlowValue> _words;

  // Members shared a literal-zero row on every predecessor. Their other
  // alternatives may have different address bases or displacements.
  final _WordGroups _groups;
  Map<int, int> get _presence => _groups.members;

  new(this.start, this.length, {int? maximumLength})
    : maximumLength = maximumLength ?? length,
      _zeroes = length == null || length == 0
          ? const []
          : [(start, start + length)],
      _bytes = const .empty(),
      _retained = const .bottom(),
      _words = const .empty(),
      _groups = _WordGroups.empty {
    if (maximumLength != null && (length == null || maximumLength < length!)) {
      throw ArgumentError('A maximum extent must cover its guaranteed prefix.');
    }
  }

  /// Entry bytes supplied by an explicit storage contract; null means unknown.
  factory bytes(List<int?> bytes) {
    final values = <MapEntry<int, _Byte>>[];
    for (final (index, byte) in bytes.indexed) {
      if (byte != null) RangeError.checkValueInInterval(byte, 0, 255, 'byte');
      if (byte != 0) {
        values.add(
          MapEntry(
            index,
            byte == null
                ? _unknown
                : _Byte(FlowValue.constant(Constant.integer(byte)), _uint8, 0),
          ),
        );
      }
    }
    return FlowMemory._(
      0,
      bytes.length,
      bytes.length,
      [(0, bytes.length)],
      StateMap.fromEntries(values),
      const .bottom(),
    );
  }

  new _(
    this.start,
    this.length,
    this.maximumLength,
    this._zeroes,
    this._bytes,
    this._retained, [
    this._words = const StateMap.empty(),
    _WordGroups? groups,
  ]) : _groups = groups ?? _WordGroups.empty;

  StateMap<int, T> _untouched<T extends Object>(
    StateMap<int, T> facts,
    int offset,
    int size,
  ) {
    var keep = facts;
    if (facts.isEmpty || size == 0) return keep;
    final end = offset + size;
    if (size <= 8) {
      for (var key = offset - 7; key < end; key++) {
        keep = keep.withoutKey(key);
      }
    } else {
      for (final key in facts.keys) {
        if (key < end && offset < key + 8) keep = keep.withoutKey(key);
      }
    }
    return keep;
  }

  // Only members still bound to this read may transfer a later test to their
  // siblings. A semantic write always drops the affected membership.
  FlowMemory rememberWord(int offset, FlowSource source) {
    if (_groups.links[offset] == null) return this;
    final word = _words[offset]!;
    final next = _words.withEntry(
      offset,
      word.withSource(source.value, source.activation),
    );
    return identical(next, _words)
        ? this
        : FlowMemory._(
            start,
            length,
            maximumLength,
            _zeroes,
            _bytes,
            _retained,
            next,
            _groups,
          );
  }

  FlowMemory refineWords(
    Map<FlowSource, FlowIntegerRange> ranges,
    void Function(FlowSource, FlowValue) bind,
  ) {
    if (_groups.links.isEmpty) return this;
    final selected = <int, bool>{};
    for (final entry in _presence.entries) {
      final value = _words[entry.key]!;
      for (final source in value.sources) {
        if (source.value is! LoadNative) continue;
        final range = ranges[source];
        if (range == null) continue;
        if (!range.contains(0)) {
          selected[entry.value] = true;
        } else if (range.constant == 0) {
          selected[entry.value] = false;
        }
      }
    }
    if (selected.isEmpty) return this;
    var next = _words;
    for (final entry in _presence.entries) {
      final present = selected[entry.value];
      if (present == null) continue;
      final old = _words[entry.key]!;
      final word = present
          ? old.restrictIntegers(_nonzero)
          : _zero.value.withSources(old.sources).withReferences([
              old.references,
            ]);
      for (final source in old.sources) {
        bind(source, word);
      }
      next = next.withEntry(entry.key, word);
    }
    return identical(_words, next)
        ? this
        : FlowMemory._(
            start,
            length,
            maximumLength,
            _zeroes,
            _bytes,
            _retained,
            next,
            _groups,
          );
  }

  Object? _presenceOf(int offset, bool Function(FlowValue)? mapped) {
    final word = _words[offset] ?? _zeroWord(offset);
    if (word == null) return null;
    if (word.constant case ScalarConstant(value: 0)) return false;
    if (word.integers case final range? when !range.contains(0)) return true;
    // Only a byte inside a live mapping proves that an address cannot wrap
    // to zero. This is an observation about the stored bits at the join.
    if (word.addresses.isNotEmpty && mapped?.call(word) == true) return true;
    return _presence[offset];
  }

  _WordGroups _joinPresence(
    FlowMemory other,
    StateMap<int, FlowValue> words,
    NativeWordProofs? proofs,
  ) {
    final bins = <(Object, Object), List<int>>{};
    for (final offset in {
      ..._presence.keys,
      ...other._presence.keys,
      for (final difference in _words.differences(other._words)) difference.key,
    }) {
      if (words[offset] == null) continue;
      final a = _presenceOf(offset, proofs?.$1), b = other._presenceOf(offset, proofs?.$2);
      if (a == null || b == null || a is bool && b is bool && a == b) continue;
      (bins[(a, b)] ??= []).add(offset);
    }
    return _WordGroups.from(bins.values);
  }

  FlowValue? _zeroWord(int offset) {
    if (!contains(offset, 8)) return null;
    for (var i = 0; i < 8; i++) {
      if (_at(offset + i) != _zero) return null;
    }
    return _zero.value;
  }

  bool contains(int offset, int size) =>
      size >= 0 &&
      offset >= start &&
      length != null &&
      offset - start <= length! &&
      size <= length! - (offset - start);

  bool containsRange(FlowIntegerRange offsets, int size) =>
      contains(offsets.lower, size) && contains(offsets.upper, size);

  /// Whether every possible byte comes from an explicit value or zeroing.
  ///
  /// An unknown scalar stored by the program is still a complete byte fact.
  /// Forgotten bytes are different: their capabilities require a snapshot of
  /// the surrounding storage at the read, before later writes replace it.
  bool hasCompleteRead(FlowIntegerRange offsets, int size) {
    if (!containsRange(offsets, size)) return false;
    if (size == 0) return true;
    if (offsets.constant case final offset? when size <= 8) {
      for (var i = 0; i < size; i++) {
        if (!_at(offset + i).known) return false;
      }
      return true;
    }
    // Copies and ranged loads can span huge zeroed allocations. Prove the
    // covering interval from sparse facts instead of enumerating its bytes.
    final lower = offsets.lower, upper = offsets.upper + size;
    final ranges = <(int, int)>[..._zeroes];
    for (final entry in _bytes.entries) {
      if (entry.key < lower || entry.key >= upper) continue;
      if (!entry.value.known) return false;
      ranges.add((entry.key, entry.key + 1));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    var covered = lower;
    for (final (start, end) in ranges) {
      if (end <= covered) continue;
      if (start > covered) return false;
      covered = end;
      if (covered >= upper) return true;
    }
    return false;
  }

  /// Joins possible reads in work proportional to sparse facts, not allocation size.
  FlowValue readRange(
    FlowIntegerRange offsets,
    NativeTypeRef storage,
    NativeLayout layout,
  ) {
    if (offsets.constant case final offset?) {
      return read(offset, storage, layout);
    }
    final size = layout.of(storage).size;
    if (!containsRange(offsets, size)) {
      return FlowValue.unknown(FfiTypes.valueType(storage))
          .withReferences([references.carrierReferences]);
    }
    var result = const FlowValue.bottom();
    for (final offset in _readStarts(offsets, size)) {
      result = result.join(read(offset, storage, layout));
    }
    return result;
  }

  Set<int> _readStarts(FlowIntegerRange offsets, int size) {
    final starts = {offsets.lower, offsets.upper};
    for (final boundary in {
      for (final (begin, end) in _zeroes) ...[begin, end],
      for (final byte in _bytes.keys) ...[byte, byte + 1],
    }) {
      // A read window changes only when it crosses a byte-fact boundary.
      for (var index = 0; index < size; index++) {
        final start = boundary - index;
        if (start <= offsets.upper) {
          final next = offsets.intersect(
            FlowIntegerRange(start, offsets.upper),
          );
          if (next != null) starts.add(next.lower);
        }
      }
    }
    return starts;
  }

  // Byte facts are immutable. Every write, join and rename constructs another
  // memory version, whose capability summary is derived from its own bytes.
  late final FlowValue references = FlowValue.joined([
    _retained,
    for (final byte in _bytes.values) byte.references,
  ]);

  /// Capabilities in the bytes copied by an ABI aggregate argument.
  FlowValue referencesIn(FlowIntegerRange offsets, int size) =>
      containsRange(offsets, size)
      ? FlowValue.joined([
          if (!hasCompleteRead(offsets, size)) _retained,
          for (final entry in _bytes.entries)
            if (entry.key >= offsets.lower && entry.key < offsets.upper + size)
              entry.value.references,
        ])
      : references;

  _Byte _defaultAt(int offset) =>
      _zeroes.any((r) => r.$1 <= offset && offset < r.$2) ? _zero : _unknown;

  _Byte _at(int offset) => _bytes[offset] ?? _defaultAt(offset);

  (NativeScalarType, NativeLayout, FlowValue)? _scalarPayload;

  /// Each immutable memory version owns the bits used to resolve a boxed
  /// scalar. Reading it through another storage type or layout decodes afresh.
  FlowValue readScalarPayload(NativeScalarType storage, NativeLayout layout) {
    final cached = _scalarPayload;
    if (cached != null && cached.$1 == storage && identical(cached.$2, layout)) {
      return cached.$3;
    }
    final value = read(ObjectHeader.fieldsOffset, storage, layout);
    _scalarPayload = (storage, layout, value);
    return value;
  }

  FlowValue read(int offset, NativeTypeRef storage, NativeLayout layout) {
    final type = storage.resolveAbi(layout.target.abi);
    final size = layout.of(type).size;
    if (!contains(offset, size)) {
      return FlowValue.unknown(FfiTypes.valueType(type))
          .withReferences([references.carrierReferences]);
    }
    if (_words[offset] case final word? when type.integerLayout?.bytes == 8) {
      return word;
    }
    final bytes = [for (var i = 0; i < size; i++) _at(offset + i)];
    final data = ByteData(size);
    var constant = true;
    for (var i = 0; i < size; i++) {
      if (bytes[i].value.constant case ScalarConstant(value: final int value)
          when bytes[i].type == _uint8) {
        data.setUint8(i, value);
      } else {
        constant = false;
        break;
      }
    }
    if (constant) {
      final endian = layout.target.byteOrder;
      if (type.isFloating) {
        return .constant(
          Constant.floating(
            type.isSinglePrecision
                ? data.getFloat32(0, endian)
                : data.getFloat64(0, endian),
          ),
        );
      }
      if (type.isBoolean) {
        return .constant(Constant.boolean(data.getUint8(0) != 0));
      }
      final integer = type.integerLayout!;
      final bits = switch (size) {
        1 => data.getUint8(0),
        2 => data.getUint16(0, endian),
        4 => data.getUint32(0, endian),
        _ => data.getInt64(0, endian),
      };
      return .constant(
        Constant.integer(integer.signed ? bits.toSigned(size * 8) : bits),
      );
    }
    final first = bytes.first;
    if (first.type == type &&
        (size == 8 || type.isBoolean) &&
        bytes.indexed.every(
          (e) =>
              e.$2.type == type &&
              e.$2.index == e.$1 &&
              e.$2.value == first.value,
        )) {
      return first.value;
    }
    return FlowValue.unknown(FfiTypes.valueType(type)).withReferences([
      _retained.carrierReferences,
      for (final byte in bytes)
        byte.type == null ? byte.value.carrierReferences : byte.value,
    ]);
  }

  /// Reads a complete traced slot; partial bytes never become a Dart value.
  FlowValue? readReference(int offset) {
    if (offset % ObjectHeader.alignment != 0 ||
        !contains(offset, ObjectHeader.alignment)) {
      return null;
    }
    final bytes = [
      for (var i = 0; i < ObjectHeader.alignment; i++) _at(offset + i),
    ];
    if (bytes.every((byte) => byte == _zero)) return _null;
    final first = bytes.first;
    return first.type == null &&
            bytes.indexed.every(
              (entry) =>
                  entry.$2.type == null &&
                  entry.$2.index == entry.$1 &&
                  entry.$2.value == first.value,
            )
        ? first.value
        : null;
  }

  /// Joins complete traced slots only after bounds and alignment are proven.
  FlowValue? readReferenceRange(FlowIntegerRange offsets) {
    if (offsets.zeroBits < ObjectHeader.alignment.bitLength - 1 ||
        !containsRange(offsets, ObjectHeader.alignment)) {
      return null;
    }
    if (offsets.constant case final offset?) return readReference(offset);
    var result = const FlowValue.bottom();
    for (final offset in _readStarts(offsets, ObjectHeader.alignment)) {
      final value = readReference(offset);
      if (value == null) return null;
      result = result.join(value);
    }
    return result;
  }

  /// Stores the language value, including boxed scalars, in one traced slot.
  FlowMemory writeReference(int offset, FlowValue value) {
    if (offset % ObjectHeader.alignment != 0 ||
        !contains(offset, ObjectHeader.alignment)) {
      return invalidate();
    }
    var bytes = _bytes;
    for (var i = 0; i < ObjectHeader.alignment; i++) {
      bytes = bytes.withEntry(offset + i, _Byte(value, null, i));
    }
    return FlowMemory._(
      start,
      length,
      maximumLength,
      _zeroes,
      bytes,
      _retained,
      _untouched(_words, offset, ObjectHeader.alignment),
      _groups.remove(offset, ObjectHeader.alignment),
    );
  }

  FlowMemory write(
    int offset,
    NativeTypeRef storage,
    FlowValue value,
    NativeLayout layout,
  ) {
    value = value.nativeScalar;
    final type = storage.resolveAbi(layout.target.abi);
    final size = layout.of(type).size;
    if (!contains(offset, size)) return invalidate();
    final data = ByteData(size);
    final constant = value.constant;
    if (constant case ScalarConstant(value: final double number)) {
      if (type.isSinglePrecision) {
        data.setFloat32(0, number, layout.target.byteOrder);
      } else {
        data.setFloat64(0, number, layout.target.byteOrder);
      }
    } else if (constant case ScalarConstant(value: final bool boolean)) {
      data.setUint8(0, boolean ? 1 : 0);
    } else if (constant case ScalarConstant(value: final int integer)) {
      for (var i = 0; i < size; i++) {
        final shift = layout.target.byteOrder == Endian.little
            ? i
            : size - 1 - i;
        data.setUint8(i, (integer >>> (shift * 8)) & 0xff);
      }
    }
    var bytes = _bytes;
    for (var i = 0; i < size; i++) {
      final byte = constant is ScalarConstant
          ? _Byte(.constant(Constant.integer(data.getUint8(i))), _uint8, 0)
          : _Byte(value, type, i);
      bytes = byte == _defaultAt(offset + i)
          ? bytes.withoutKey(offset + i)
          : bytes.withEntry(offset + i, byte);
    }
    var words = _untouched(_words, offset, size);
    if (type.integerLayout?.bytes == 8) {
      // Concrete bytes carry the integer bits alone. A source that once
      // produced the integer is not an address stored in those bytes.
      final bits = constant == null ? value : FlowValue.constant(constant);
      if (bits != _zero.value) words = words.withEntry(offset, bits);
    }
    return FlowMemory._(
      start,
      length,
      maximumLength,
      _zeroes,
      bytes,
      _retained,
      words,
      _groups.remove(offset, size),
    );
  }

  /// Forgets only the overwritten range and preserves disjoint storage.
  FlowMemory forget(
    int offset,
    int size, {
    FlowValue retained = const .bottom(),
    bool extentProven = false,
  }) {
    // An independently proven dynamic extent may extend beyond this version's
    // guaranteed prefix. Only sparse facts intersecting the store can change.
    if (!extentProven && !contains(offset, size)) return invalidate();
    final end = offset + size;
    final zeroes = <(int, int)>[];
    for (final (low, high) in _zeroes) {
      if (high <= offset || low >= end) {
        zeroes.add((low, high));
      } else {
        if (low < offset) zeroes.add((low, offset));
        if (high > end) zeroes.add((end, high));
      }
    }
    var bytes = _bytes;
    for (final key in _bytes.keys) {
      if (offset <= key && key < end) bytes = bytes.withoutKey(key);
    }
    return FlowMemory._(
      start,
      length,
      maximumLength,
      zeroes,
      bytes,
      _retained.join(retained),
      _untouched(_words, offset, size),
      _groups.remove(offset, size),
    );
  }

  /// Copies the source snapshot, including overlap, in work proportional to facts.
  FlowMemory copyFrom(int offset, FlowMemory source, int from, int size) {
    final cleared = forget(offset, size, retained: source._retained);
    if (!contains(offset, size) || !source.contains(from, size)) return cleared;
    final shift = offset - from;
    final zeroes = [...cleared._zeroes];
    for (final (low, high) in source._zeroes) {
      final begin = low > from ? low : from;
      final finish = high < from + size ? high : from + size;
      if (begin < finish) zeroes.add((begin + shift, finish + shift));
    }
    zeroes.sort((a, b) => a.$1.compareTo(b.$1));
    var bytes = cleared._bytes;
    for (final entry in source._bytes.entries) {
      if (from <= entry.key && entry.key < from + size) {
        bytes = bytes.withEntry(entry.key + shift, entry.value);
      }
    }
    var words = cleared._words;
    for (final entry in source._words.entries) {
      if (from <= entry.key && entry.key + 8 <= from + size) {
        words = words.withEntry(entry.key + shift, entry.value);
      }
    }
    return FlowMemory._(
      start,
      length,
      maximumLength,
      _coalesce(zeroes),
      bytes,
      cleared._retained,
      words,
      cleared._groups,
    );
  }

  /// Merges the callee's effects into a still-live caller allocation. A
  /// current byte range outside the summary input may contain later writes.
  /// A mapping or unbounded effect uses the full conservative join.
  FlowMemory applyWrites(FlowMemory entry, FlowMemory exit, FlowWrites writes, {bool currentInput = false}) {
    final ranges = writes._ranges;
    if (ranges == null || start != entry.start || start != exit.start ||
        length == null || length != entry.length || length != exit.length) {
      return join(exit);
    }
    // A range can agree with the entry while contradicting a different
    // range's branch condition or a relation between two words. Check the
    // whole allocation before reusing the exit as a strong update.
    final covered = currentInput && (this == entry || join(entry) == entry);
    final source = covered ? exit : join(exit);
    var result = this;
    for (final span in ranges.entries) {
      final from = span.key, size = span.value - from;
      if (!contains(from, size)) return join(exit);
      result = result.copyFrom(from, source, from, size);
    }
    if (!covered || exit._groups.links.isEmpty) return result;
    final copied = <int, List<int>>{};
    for (final member in exit._presence.entries) {
      if (ranges.entries.any((span) => span.key <= member.key && member.key + 8 <= span.value)) {
        (copied[member.value] ??= []).add(member.key);
      }
    }
    if (!copied.values.any((group) => group.length > 1)) return result;
    final kept = <int, List<int>>{};
    for (final member in result._presence.entries) {
      (kept[member.value] ??= []).add(member.key);
    }
    return FlowMemory._(start, length, maximumLength, result._zeroes, result._bytes,
        result._retained, result._words,
        _WordGroups.from([...kept.values, ...copied.values]));
  }

  FlowMemory invalidate({bool release = false}) => FlowMemory._(
    start,
    release ? null : length,
    release ? null : maximumLength,
    const [],
    const .empty(),
    references,
  );

  /// Keeps read-time capabilities when copied bytes have no complete encoding.
  FlowMemory retainReferences(FlowValue value) {
    final retained = _retained.join(value);
    return retained == _retained
        ? this
        : FlowMemory._(
            start,
            length,
            maximumLength,
            _zeroes,
            _bytes,
            retained,
            _words,
            _groups,
          );
  }

  FlowMemory map(FlowValue Function(FlowValue) transform) {
    final bytes = _bytes.mapValues(
      (_, byte) => _Byte(
        transform(byte.value),
        byte.type,
        byte.index,
        known: byte.known,
      ),
    );
    final retained = transform(_retained);
    final words = _words.mapValues((_, word) => transform(word));
    return identical(bytes, _bytes) &&
            identical(words, _words) &&
            retained == _retained
        ? this
        : FlowMemory._(
            start,
            length,
            maximumLength,
            _zeroes,
            bytes,
            retained,
            words,
            _groups,
          );
  }

  FlowMemory join(
    FlowMemory other, {
    bool widen = false,
    NativeWordProofs? nativeWords,
  }) {
    if (this == other) return this;
    if (start != other.start) {
      throw StateError('One allocation has incompatible native storage.');
    }
    final zeroes = <(int, int)>[];
    var left = 0, right = 0;
    while (left < _zeroes.length && right < other._zeroes.length) {
      final a = _zeroes[left], b = other._zeroes[right];
      final low = a.$1 > b.$1 ? a.$1 : b.$1;
      final high = a.$2 < b.$2 ? a.$2 : b.$2;
      if (low < high) zeroes.add((low, high));
      if (a.$2 < b.$2) {
        left++;
      } else {
        right++;
      }
    }
    final merged = FlowMemory._(
      start,
      length == null || other.length == null
          ? null
          : length! < other.length!
          ? length
          : other.length,
      maximumLength == null || other.maximumLength == null
          ? null
          : maximumLength! > other.maximumLength!
          ? maximumLength
          : other.maximumLength,
      _coalesce(zeroes),
      const .empty(),
      _retained.join(other._retained, widen: widen),
    );
    final bytes = _bytes.merge(other._bytes, (key, a, b) {
      final byte = (a ?? _at(key)).join(b ?? other._at(key), widen: widen);
      return byte == merged._at(key) ? null : byte;
    });
    final words = _words.merge(other._words, (offset, left, right) {
      if (!merged.contains(offset, 8)) return null;
      left ??= _zeroWord(offset);
      right ??= other._zeroWord(offset);
      if (left == null || right == null) return null;
      return left.join(right, widen: widen);
    });
    return FlowMemory._(
      start,
      merged.length,
      merged.maximumLength,
      merged._zeroes,
      bytes,
      merged._retained,
      words,
      nativeWords != null || !_groups.links.isEmpty || !other._groups.links.isEmpty
          ? _joinPresence(other, words, nativeWords)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowMemory &&
          start == other.start &&
          length == other.length &&
          maximumLength == other.maximumLength &&
          _bytes == other._bytes &&
          _words == other._words &&
          _groups.links == other._groups.links &&
          _retained == other._retained &&
          _zeroes.length == other._zeroes.length &&
          _zeroes.indexed.every((e) => e.$2 == other._zeroes[e.$1]);

  @override
  late final int hashCode = Object.hash(
    start,
    length,
    maximumLength,
    Object.hashAll(_zeroes),
    _bytes,
    _words,
    _groups.links,
    _retained,
  );
}

final class _Byte(
  final FlowValue value,
  // A null native type denotes a traced reference fragment.
  final NativeTypeRef? type,
  final int index, {
  final bool known = true,
}) {
  FlowValue get references => type == null ? value : value.references;

  _Byte join(_Byte other, {bool widen = false}) {
    if (identical(this, other)) return this;
    if (type == other.type && index == other.index) {
      return _Byte(
        value.join(other.value, widen: widen),
        type,
        index,
        known: known && other.known,
      );
    }
    if (type == null && other == _zero) {
      return _Byte(
        value.join(_null, widen: widen),
        null,
        index,
        known: known && other.known,
      );
    }
    if (this == _zero && other.type == null) {
      return _Byte(
        _null.join(other.value, widen: widen),
        null,
        other.index,
        known: known && other.known,
      );
    }
    return _Byte(
      FlowValue.unknown(.integer).withReferences([
        references.carrierReferences.join(
          other.references.carrierReferences,
          widen: widen,
        ),
      ]),
      _uint8,
      0,
      known: known && other.known,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Byte &&
          type == other.type &&
          index == other.index &&
          known == other.known &&
          value == other.value;

  @override
  int get hashCode => Object.hash(value, type, index, known);
}

// Circular links in increasing offset order give equivalent partitions the
// same state key. Removing a member changes only its two neighbors.
final class _WordGroups(final StateMap<int, (int, int)> links) {
  static final empty = _WordGroups(const .empty());

  factory from(Iterable<List<int>> groups) {
    var links = const StateMap<int, (int, int)>.empty();
    for (final group in groups) {
      if (group.length < 2) continue;
      group.sort();
      for (final (i, offset) in group.indexed) {
        links = links.withEntry(offset, (
          group[(i - 1) % group.length],
          group[(i + 1) % group.length],
        ));
      }
    }
    return links.isEmpty ? empty : _WordGroups(links);
  }

  // Labels are local to this snapshot and never enter equality or hashing.
  late final Map<int, int> members = _label();
  Map<int, int> _label() {
    final groups = <int, int>{};
    for (final start in links.keys) {
      var offset = start;
      while (!groups.containsKey(offset)) {
        groups[offset] = start;
        offset = links[offset]!.$2;
      }
    }
    return groups;
  }

  _WordGroups remove(int offset, int size) {
    if (links.isEmpty || size == 0) return this;
    var next = links;
    void unlink(int key) {
      final link = next[key];
      if (link == null) return;
      final (before, after) = link;
      next = next.withoutKey(key);
      if (before == after) {
        next = next.withoutKey(before);
      } else {
        next = next.withEntry(before, (next[before]!.$1, after));
        next = next.withEntry(after, (before, next[after]!.$2));
      }
    }
    final end = offset + size;
    if (size <= 8) {
      for (var key = offset - 7; key < end; key++) {
        unlink(key);
      }
    } else {
      for (final key in links.keys) {
        if (key < end && offset < key + 8) unlink(key);
      }
    }
    if (identical(next, links)) return this;
    return next.isEmpty ? empty : _WordGroups(next);
  }
}

final _nonzero = FlowIntegerRange(
  FlowIntegerRange.minimum,
  FlowIntegerRange.maximum,
  excludesZero: true,
);
final _null = FlowValue.constant(const Constant.nullValue());
final _uint8 = NativeScalarType(Uint8);
final _zero = _Byte(.constant(const Constant.integer(0)), _uint8, 0);
final _unknown = _Byte(.unknown(.integer), _uint8, 0, known: false);

List<(int, int)> _coalesce(List<(int, int)> ranges) {
  final result = <(int, int)>[];
  for (final range in ranges) {
    if (result.isNotEmpty && range.$1 <= result.last.$2) {
      if (range.$2 > result.last.$2) {
        result[result.length - 1] = (result.last.$1, range.$2);
      }
    } else {
      result.add(range);
    }
  }
  return List.unmodifiable(result);
}
