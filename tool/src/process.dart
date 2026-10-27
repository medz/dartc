import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ProcessOutcome {
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
  final Duration timeout;
  final int outputLimit;
  final int? pid;
  final int? exitCode;
  final bool timedOut;
  final bool outputLimited;
  final String? startError;
  final String? captureError;
  final List<int> stdoutBytes;
  final List<int> stderrBytes;
  final Duration elapsed;

  ProcessOutcome({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.includeParentEnvironment,
    required this.timeout,
    required this.outputLimit,
    required this.pid,
    required this.exitCode,
    required this.timedOut,
    required this.outputLimited,
    required this.startError,
    required this.captureError,
    required this.stdoutBytes,
    required this.stderrBytes,
    required this.elapsed,
  });

  String get stdout => utf8.decode(stdoutBytes, allowMalformed: true);
  String get stderr => utf8.decode(stderrBytes, allowMalformed: true);

  Map<String, Object?> toJson() => {
    'executable': executable,
    'arguments': arguments,
    'workingDirectory': workingDirectory,
    'environment': environment,
    'includeParentEnvironment': includeParentEnvironment,
    'timeoutMilliseconds': timeout.inMilliseconds,
    'outputLimit': outputLimit,
    'pid': pid,
    'exitCode': exitCode,
    'timedOut': timedOut,
    'outputLimited': outputLimited,
    'startError': startError,
    'captureError': captureError,
    'stdoutBase64': base64Encode(stdoutBytes),
    'stderrBase64': base64Encode(stderrBytes),
    'elapsedMicroseconds': elapsed.inMicroseconds,
  };
}

Future<ProcessOutcome> captureProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  Duration timeout = const Duration(seconds: 30),
  int outputLimit = 1048576,
}) async {
  if (timeout.isNegative) throw ArgumentError.value(timeout, 'timeout');
  if (outputLimit < 0) throw ArgumentError.value(outputLimit, 'outputLimit');
  final commandArguments = List<String>.of(arguments);
  final directory = Directory(workingDirectory ?? Directory.current.path)
      .absolute
      .path;
  final explicitEnvironment = environment == null
      ? null
      : Map<String, String>.of(environment);
  final clock = Stopwatch()..start();
  final output = BytesBuilder(copy: false);
  final errorOutput = BytesBuilder(copy: false);
  int? pid;
  int? exitCode;
  var timedOut = false;
  var outputLimited = false;
  String? startError;
  String? captureError;

  ProcessOutcome outcome() => ProcessOutcome(
    executable: executable,
    arguments: commandArguments,
    workingDirectory: directory,
    environment: explicitEnvironment,
    includeParentEnvironment: includeParentEnvironment,
    timeout: timeout,
    outputLimit: outputLimit,
    pid: pid,
    exitCode: exitCode,
    timedOut: timedOut,
    outputLimited: outputLimited,
    startError: startError,
    captureError: captureError,
    stdoutBytes: output.takeBytes(),
    stderrBytes: errorOutput.takeBytes(),
    elapsed: clock.elapsed,
  );

  Process process;
  try {
    process = await Process.start(
      executable,
      commandArguments,
      workingDirectory: directory,
      environment: explicitEnvironment,
      includeParentEnvironment: includeParentEnvironment,
    );
    pid = process.pid;
  } catch (error) {
    startError = error.toString();
    return outcome();
  }

  final stopped = Completer<void>();
  void stop() {
    if (stopped.isCompleted) return;
    stopped.complete();
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (error) {
      captureError ??= error.toString();
    }
  }

  void failed(Object error) {
    captureError ??= error.toString();
    stop();
  }

  var captured = 0;
  void append(BytesBuilder target, List<int> bytes) {
    final remaining = outputLimit - captured;
    if (bytes.length <= remaining) {
      target.add(bytes);
      captured += bytes.length;
    } else {
      if (remaining > 0) target.add(bytes.sublist(0, remaining));
      captured = outputLimit;
      outputLimited = true;
      stop();
    }
  }

  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final stdoutSubscription = process.stdout.listen(
    (bytes) => append(output, bytes),
    onError: failed,
    onDone: stdoutDone.complete,
  );
  final stderrSubscription = process.stderr.listen(
    (bytes) => append(errorOutput, bytes),
    onError: failed,
    onDone: stderrDone.complete,
  );
  final exited = process.exitCode.then<void>(
    (code) => exitCode = code,
    onError: failed,
  );
  final stdinClosed = process.stdin.close().then<void>((_) {}, onError: failed);
  final pipesDone = Future.wait([stdoutDone.future, stderrDone.future]);
  final finished = Future.wait([exited, stdinClosed, pipesDone]);
  final timer = Timer(timeout, () {
    timedOut = true;
    stop();
  });
  await Future.any([finished, stopped.future]);
  timer.cancel();
  if (stopped.isCompleted) {
    const cleanupTimeout = Duration(seconds: 2);
    try {
      await exited.timeout(cleanupTimeout);
    } on TimeoutException {
      captureError ??= 'child did not exit after SIGKILL';
    }
    try {
      await pipesDone.timeout(cleanupTimeout);
    } on TimeoutException {
      captureError ??= 'child output pipes did not close';
    }
    try {
      await Future.wait([
        stdoutSubscription.cancel(),
        stderrSubscription.cancel(),
      ]).timeout(cleanupTimeout);
    } catch (error) {
      captureError ??= 'child output cancellation failed: $error';
    }
  }
  return outcome();
}
