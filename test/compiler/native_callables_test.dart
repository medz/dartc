@Tags(['assets', 'native'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/native_callbacks.dart';
import 'fixtures/native_callables_ffi.dart';

void main() {
  final assets = NativeAssets(Target.host());
  late NativeCallables native;
  setUpAll(() {
    native = NativeCallables();
    addTearDown(native.close);
  });

  test('closures survive GC until close and translate escaped exceptions', () {
    final first = native.create(17).asFunction<int Function(int)>();
    final second = native.create(29).asFunction<int Function(int)>();
    expect(first(5), 22);
    expect(second(5), 34);
    expect(first(-1), -41);
    expect(second(3), 32);
    expect(native.releaseLast(), isTrue);
    expect(first(7), 24);
  });

  test(
    'captured state survives mixed native registers and stack arguments',
    () {
      final call = native
          .mixed(10.5)
          .asFunction<
            double Function(
              int,
              double,
              bool,
              double,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
            )
          >();
      expect(call(-7, 1.25, true, 2.5, 1, 2, 3, 4, 5, 6, 7, 8, 9), 52.25);
      expect(call(0, 0, false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0), -1.25);
    },
  );

  test(
    'closure entries preserve compound arguments, results and failure zeroing',
    () {
      final value = Struct.create<CallbackState>()
        ..count = 5
        ..value = 1.25;
      value.entries[0] = 7;
      value.entries[1] = 9;
      final call = native
          .compound(13)
          .asFunction<CallbackState Function(CallbackState, bool)>();
      final result = call(value, false);
      expect((result.count, result.value, result.entries[1]), (18, 2.5, 16));
      expect((value.count, value.value, value.entries[1]), (5, 1.25, 9));
      final failed = call(value, true);
      expect(
        (failed.count, failed.value, failed.entries[0], failed.entries[1]),
        (0, 0.0, 0, 0),
      );
    },
  );

  test(
    'closure entries reject foreign threads before reading managed state',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/native_callbacks_thread.dart',
        'closure',
      ]);
      expect(result.exitCode, 70, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test(
    'multiple pages, defaults, reentry, close and timer shutdown compose',
    () async {
      final result = await Process.run(
        assets.file('compiler/entry_native_callables').path,
        [],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, 'native_callables:ok\n');
    },
  );

  test('keepIsolateAlive holds an idle process and can be disabled', () async {
    final process = await Process.start(
      assets.file('compiler/entry_native_callables_alive').path,
      [],
    );
    final errors = process.stderr.transform(utf8.decoder).join();
    addTearDown(() async {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await errors;
    });
    expect(
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first,
      'ready',
    );
    expect(
      await Future.any<Object>([
        process.exitCode,
        Future<String>.delayed(
          const Duration(milliseconds: 100),
          () => 'alive',
        ),
      ]),
      'alive',
    );
    final idle = await Process.run(
      assets.file('compiler/entry_native_callables_idle').path,
      [],
    );
    expect(idle.exitCode, 0, reason: '${idle.stdout}\n${idle.stderr}');
    expect(idle.stdout, 'idle\n');
  });
}
