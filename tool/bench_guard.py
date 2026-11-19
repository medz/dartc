"""Run a POSIX benchmark command with a process-group wall-clock deadline."""

import argparse
import os
import select
import signal
import subprocess
import sys
import time


def exit_code(code):
    return 128 - code if code < 0 else code


def run_group(command, result):
    os.setpgid(0, 0)
    try:
        status = exit_code(subprocess.run(command).returncode)
    except OSError as error:
        print(error, file=sys.stderr, flush=True)
        status = 127 if isinstance(error, FileNotFoundError) else 126
    os.write(result, bytes([status]))
    # Keep the group ID owned until the guardian has signalled every member.
    while True:
        signal.pause()


def supervise(command, deadline, launcher):
    os.setsid()
    ready, result = os.pipe()
    group = os.fork()
    if group == 0:
        os.close(ready)
        os.close(launcher)
        run_group(command, result)
    os.close(result)
    # Either side of fork can run first. Both establish the group before the
    # command starts or the guardian can receive a cancellation.
    os.setpgid(group, group)
    try:
        readable, _, _ = select.select(
            [launcher, ready], [], [], max(0, deadline - time.monotonic())
        )
        if launcher in readable:
            why = os.read(launcher, 1)
            status = 128 + (why[0] if why else signal.SIGTERM)
        elif ready in readable:
            code = os.read(ready, 1)
            status = code[0] if code else 125
        else:
            print("Benchmark wall-clock deadline expired.", file=sys.stderr, flush=True)
            status = 124
    finally:
        os.killpg(group, signal.SIGKILL)
        os.waitpid(group, 0)
    # Orphaned members may take a moment to be reaped by the host.
    end = time.monotonic() + 2
    while True:
        try:
            os.killpg(group, 0)
        except ProcessLookupError:
            return status
        except PermissionError:
            # Darwin can report EPERM while orphaned children are being reaped.
            pass
        if time.monotonic() >= end:
            print("Benchmark process group still exists.", file=sys.stderr, flush=True)
            return 125
        time.sleep(0.02)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seconds", type=int)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if os.name != "posix" or args.seconds <= 0 or not args.command:
        parser.error("provide a positive wall-clock deadline and command on POSIX")
    deadline = time.monotonic() + args.seconds
    read_end, write_end = os.pipe()

    def cancel(number, _frame):
        try:
            os.write(write_end, bytes([number]))
        except BrokenPipeError:
            pass

    signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
    # Queue cancellation until every handler can forward it through the pipe.
    # The invoking process may have left any of these signals blocked.
    signal.pthread_sigmask(signal.SIG_BLOCK, signals)
    for sig in signals:
        signal.signal(sig, cancel)
    signal.pthread_sigmask(signal.SIG_UNBLOCK, signals)
    guardian = os.fork()
    if guardian == 0:
        for sig in signals:
            signal.signal(sig, signal.SIG_DFL)
        os.close(write_end)
        os._exit(supervise(args.command, deadline, read_end))
    os.close(read_end)
    # The supervisor also sees EOF when SIGKILL prevents this process from
    # forwarding a signal. Only the launcher owns the pipe's write end.
    _, status = os.waitpid(guardian, 0)
    return exit_code(os.waitstatus_to_exitcode(status))


if __name__ == "__main__":
    sys.exit(main())
