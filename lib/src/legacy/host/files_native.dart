import '../diagnostic.dart';
import '../runtime.dart';

void prepareOutput(String path) {
  final target = nativeTarget();
  for (var i = 1; i < path.length; i++) {
    if (path.codeUnitAt(i) != 47 || path.codeUnitAt(i - 1) == 47) continue;
    final directory = path.substring(0, i);
    final encoded = rtStringEncodeUtf8(nativeValueBits(directory));
    // Darwin mkdir; Linux mkdirat relative to AT_FDCWD.
    final status = target == 0 || target == 3
        ? nativeSyscall(136, encoded + 8, 511, 0, 0, 0, 0)
        : nativeSyscall(
            target == 2 ? 258 : 34,
            -100,
            encoded + 8,
            511,
            0,
            0,
            0,
          );
    rtUtf8Release();
    if (status < 0 && status != -17)
      throw Diagnostic('Cannot create output directory: ' + path, exitCode: 74);
  }
}

@pragma('dartc:no-gc')
int _stat(String path, int buffer) {
  final encoded = rtStringEncodeUtf8(nativeValueBits(path));
  final target = nativeTarget();
  // Darwin stat64; Linux newfstatat with flags 0 follows symbolic links.
  final status = target == 0 || target == 3
      ? nativeSyscall(338, encoded + 8, buffer, 0, 0, 0, 0)
      : nativeSyscall(
          target == 2 ? 262 : 79,
          -100,
          encoded + 8,
          buffer,
          0,
          0,
          0,
        );
  rtUtf8Release();
  return status;
}

bool identicalFiles(String first, String second) {
  // Darwin stat64 and Linux x64 stat use 144 bytes; Linux ARM64 uses 128.
  // The inode is at byte 8. Darwin's device field is only 32 bits wide.
  final target = nativeTarget();
  final size = target == 1 ? 128 : 144;
  final mask = target == 0 || target == 3 ? 0xffffffff : -1;
  final buffer = rtMap(size);
  var path = first;
  var status = _stat(first, buffer);
  var same = false;
  if (status == 0) {
    final device = nativeLoad64(buffer) & mask;
    final inode = nativeLoad64(buffer + 8);
    path = second;
    status = _stat(second, buffer);
    same =
        status == 0 &&
        device == (nativeLoad64(buffer) & mask) &&
        inode == nativeLoad64(buffer + 8);
  }
  rtUnmap(buffer, size);
  if (status < 0 && status != -2 && status != -20)
    throw Diagnostic('Cannot inspect file: ' + path, exitCode: 74);
  return same;
}
