import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'bytes.dart';

const _pageBits = 12, _hashBytes = 32;
const _superBlobBytes = 20, _directoryBytes = 88;

int _pages(int length) => (length + (1 << _pageBits) - 1) >> _pageBits;

int _identifierBytes(String identifier) => utf8.encode(identifier).length + 1;

/// The size of the signature of [length] file bytes.
int codeSignatureSize(int length, String identifier) =>
    _superBlobBytes +
    _directoryBytes +
    _identifierBytes(identifier) +
    _pages(length) * _hashBytes;

/// An ad-hoc signature, which macOS requires of every ARM64 program.
///
/// [file] is everything before the signature; its first [textBytes] bytes are
/// the executable segment.
Uint8List codeSignature(
  Uint8List file, {
  required String identifier,
  required int textBytes,
  required bool isMain,
}) {
  final size = codeSignatureSize(file.length, identifier);
  final hashes = _directoryBytes + _identifierBytes(identifier);
  final out = ByteWriter(.big)
    // A container with one entry, the code directory.
    ..u32(0xfade0cc0)
    ..u32(size)
    ..u32(1)
    ..u32(0)
    ..u32(_superBlobBytes)
    // The code directory.
    ..u32(0xfade0c02)
    ..u32(size - _superBlobBytes)
    ..u32(0x20400) // Version.
    ..u32(0x20002) // Ad-hoc, made by a linker.
    ..u32(hashes)
    ..u32(_directoryBytes) // Identifier offset.
    ..u32(0) // Special slots.
    ..u32(_pages(file.length))
    ..u32(file.length)
    ..u8(_hashBytes)
    ..u8(2) // SHA-256.
    ..u8(0) // Platform.
    ..u8(_pageBits)
    ..zeros(4 + 4 + 4 + 4) // Spare, scatter, team and spare.
    ..u64(0) // 64-bit code limit, unused.
    ..u64(0) // Executable segment start.
    ..u64(textBytes)
    ..u64(isMain ? 1 : 0)
    ..text(identifier, _identifierBytes(identifier));
  for (var at = 0; at < file.length; at += 1 << _pageBits) {
    final end = at + (1 << _pageBits);
    final page = Uint8List.sublistView(
      file,
      at,
      end < file.length ? end : file.length,
    );
    out.bytes(sha256.convert(page).bytes);
  }
  return out.finish();
}
