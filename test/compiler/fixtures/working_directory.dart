import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

class Cell(final int value);

class DirectoryAlias(@override final String path) implements Directory {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void check(bool value) {
  if (!value) throw StateError('working directory contract');
}

void main(List<String> args) {
  final original = Directory.current;
  switch (args.single) {
    case 'roundtrip':
      Directory.current = '中文🙂 #?%';
      final snapshot = Directory.current;
      check(snapshot.path.endsWith('/中文🙂 #?%'));
      Directory.current = Directory('nested');
      check(Directory.current.path == '${snapshot.path}/nested');
      Directory.current = DirectoryAlias('..');
      check(Directory.current.path == snapshot.path);
      for (var i = 0; i < 40000; i++) {
        Cell(i);
      }
      check(original.path != snapshot.path);
      Directory.current = original;
      check(Directory.current.path == original.path);
      final setters = <String>[];
      IOOverrides.runZoned(
        () {
          check(Directory.current.path == 'virtual');
          Directory.current = 'first';
          Directory.current = Directory('second');
        },
        getCurrentDirectory: () => Directory('virtual'),
        setCurrentDirectory: setters.add,
      );
      check(setters.join(':') == 'first:second');
      check(Directory.current.path == original.path);
      print('roundtrip:ok');
    case 'failures':
      for (final Object? path in ['', 'missing', 'ordinary-file', null, 3]) {
        try {
          Directory.current = path;
          throw StateError('unexpected success');
        } on FileSystemException catch (error) {
          check(Directory.current.path == original.path);
          print(
            jsonEncode([
              error is PathNotFoundException,
              error.path,
              error.osError!.errorCode,
              error.osError!.message.isNotEmpty,
            ]),
          );
        } on ArgumentError {
          print('argument');
        }
      }
      for (final suffix in ['\u0000', '\u0000/ignored']) {
        Directory.current = '${original.path}/中文🙂 #?%$suffix';
        check(Directory.current.path.endsWith('/中文🙂 #?%'));
      }
      Directory.current = original;
      print('failures:ok');
    case 'deleted':
      Directory.current = 'deleted';
      final path = utf8.encode('${Directory.current.path}\u0000');
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
      final rmdir = process
          .lookupFunction<
            ffi.Int Function(ffi.Pointer<ffi.Uint8>),
            int Function(ffi.Pointer<ffi.Uint8>)
          >('rmdir');
      final storage = malloc(path.length);
      if (storage == ffi.nullptr) throw StateError('malloc failed');
      try {
        storage.asTypedList(path.length).setAll(0, path);
        check(rmdir(storage) == 0);
      } finally {
        free(storage);
      }
      var rejected = false;
      try {
        Directory.current;
      } on FileSystemException catch (error) {
        rejected =
            error is PathNotFoundException && error.osError!.errorCode == 2;
      } finally {
        Directory.current = original;
      }
      check(rejected && Directory.current.path == original.path);
      print('deleted:ok');
    case 'raw':
      final raw = Uint8List.fromList([
        ...utf8.encode('${original.path}/'),
        0xff,
        120,
      ]);
      Directory.current = Directory.fromRawPath(raw);
      check(Directory.current.path.endsWith('/\ufffdx'));
      Directory.current = original;
      print('raw:ok');
    default:
      throw ArgumentError(args);
  }
}
