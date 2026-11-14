import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

class DirectoryProxy(@override final String path) implements Directory {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main(List<String> args) {
  switch (args.single) {
    case 'system':
      print(jsonEncode(Directory.systemTemp.path));
      IOOverrides.runZoned(
        () => print(Directory.systemTemp.path),
        getSystemTempDirectory: () => DirectoryProxy('override'),
      );
    case 'create':
      final umask = ffi.DynamicLibrary.process()
          .lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>(
            'umask',
          );
      final previous = umask(0);
      final created = <List<Object?>>[];
      try {
        for (var repeat = 0; repeat < 2; repeat++) {
          for (final prefix in <String?>[
            null,
            '',
            'dartc-',
            '中文-',
            'nested/dir-',
            'cut\u0000ignored',
          ]) {
            final directory = Directory('.').createTempSync(prefix);
            created.add([prefix, directory.path]);
          }
        }
        final parent = Directory('.');
        var overridden = '';
        final result = IOOverrides.runZoned(
          () => parent.createTempSync('hook-'),
          createDirectory: (path) {
            overridden = path;
            return DirectoryProxy(path);
          },
        );
        if (result is! DirectoryProxy || result.path != overridden) {
          throw StateError('directory override');
        }
        created.add(['hook-', result.path]);
      } finally {
        umask(previous);
      }
      print(jsonEncode(created));
    case 'failures':
      for (final parent in ['', 'missing', 'ordinary-file']) {
        try {
          Directory(parent).createTempSync('p-');
          throw StateError('unexpected creation');
        } on ArgumentError {
          print('argument');
        } on FileSystemException catch (error) {
          print(
            jsonEncode([
              error is PathNotFoundException,
              error.path,
              error.osError!.errorCode,
            ]),
          );
        }
      }
      try {
        Directory('.').createTempSync('x' * 300);
        throw StateError('unexpected long name');
      } on FileSystemException catch (error) {
        print(
          error.osError!.errorCode > 0 && error.osError!.message.isNotEmpty,
        );
      }
    case 'mutation':
      final snapshot = Platform.environment;
      final before = Directory.systemTemp.path;
      final process = ffi.DynamicLibrary.process();
      final malloc = process
          .lookupFunction<
            ffi.Pointer<ffi.Uint8> Function(ffi.Size),
            ffi.Pointer<ffi.Uint8> Function(int)
          >('malloc');
      final free = process
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Uint8>),
            void Function(ffi.Pointer<ffi.Uint8>)
          >('free');
      final setenv = process
          .lookupFunction<
            ffi.Int Function(
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Int,
            ),
            int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int)
          >('setenv');
      const name = 'TMPDIR';
      final bytes = utf8.encode('$name\u0000after/\u0000');
      final storage = malloc(bytes.length);
      if (storage == ffi.nullptr) throw StateError('malloc failed');
      try {
        storage.asTypedList(bytes.length).setAll(0, bytes);
        if (setenv(storage, storage + name.length + 1, 1) != 0) {
          throw StateError('setenv failed');
        }
      } finally {
        free(storage);
      }
      print('$before|${Directory.systemTemp.path}|${snapshot[name]}');
    default:
      throw ArgumentError(args);
  }
}
