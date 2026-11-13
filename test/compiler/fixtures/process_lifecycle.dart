import 'dart:async';
import 'dart:io';

void main(List<String> arguments) {
  switch (arguments.single) {
    case 'status':
      print(exitCode);
      for (final value in [
        0,
        47,
        255,
        256,
        -1,
        0x7fffffff,
        0x80000000,
        0x100000001,
      ]) {
        exitCode = value;
        print(exitCode);
      }
      exitCode = 258;
    case 'events':
      exitCode = 1;
      scheduleMicrotask(() {
        exitCode = 2;
        print('microtask');
      });
      Timer.run(() {
        exitCode = 3;
        print('timer');
      });
      Future<void>.delayed(const Duration(milliseconds: 10), () {
        exitCode = 4;
        print('delayed');
      });
    case 'immediate':
      exitCode = 11;
      Timer.run(() => print('unexpected timer'));
      try {
        print('before exit');
        final terminate = exit;
        terminate(263);
      } finally {
        print('unexpected finally');
      }
    case 'override':
      IOOverrides.runZoned(
        () {
          try {
            exit(9);
          } on StateError catch (error) {
            print(error.message);
          } finally {
            print('finally');
          }
        },
        exit: (code) {
          print('override $code');
          throw StateError('intercepted');
        },
      );
      exitCode = 5;
    case 'sleep':
      scheduleMicrotask(() => print('microtask'));
      final wait = sleep;
      final watch = Stopwatch()..start();
      wait(const Duration(milliseconds: 2));
      if (watch.elapsedMicroseconds < 2000) throw StateError('early sleep');
      print('after sleep');
      wait(const Duration(microseconds: -1));
      try {
        wait(const Duration(milliseconds: -1));
        throw StateError('negative sleep accepted');
      } on ArgumentError {
        print('negative');
      }
      final dynamic dynamicWait = wait;
      try {
        dynamicWait(2);
        throw StateError('invalid duration accepted');
      } on TypeError {
        print('type');
      }
    case 'unhandled':
      exitCode = 27;
      scheduleMicrotask(() => throw StateError('uncaught'));
  }
}
