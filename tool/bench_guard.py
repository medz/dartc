"""Run a POSIX benchmark command with a process-group wall-clock deadline."""

import argparse
import os
import resource
import select
import signal
import subprocess
import sys
import time


def exit_code(code):
    return 128 - code if code < 0 else code


def run_group(command, result, cpu_seconds):
    os.setpgid(0, 0)
    if cpu_seconds is not None:
        soft, hard = resource.getrlimit(resource.RLIMIT_CPU)
        limit = min(n for n in (cpu_seconds, soft, hard) if n != resource.RLIM_INFINITY)
        resource.setrlimit(resource.RLIMIT_CPU, (limit, limit))
    try:
        status = exit_code(subprocess.run(command).returncode)
    except OSError as error:
        print(error, file=sys.stderr, flush=True)
        status = 127 if isinstance(error, FileNotFoundError) else 126
    os.write(result, bytes([status]))
    # Keep the group ID owned until the guardian has signalled every member.
    while True:
        signal.pause()


def group_rss_kib(group, timeout):
    output = subprocess.check_output(["ps", "-A", "-o", "pgid=,rss="], text=True, timeout=timeout)
    return sum(int(rss) for pgid, rss in (line.split() for line in output.splitlines())
               if int(pgid) == group)


def supervise(args, deadline, launcher):
    os.setsid()
    ready, result = os.pipe()
    group = os.fork()
    if group == 0:
        os.close(ready)
        os.close(launcher)
        run_group(args.command, result, args.cpu_seconds)
    os.close(result)
    # Either side of fork can run first. Both establish the group before the
    # command starts or the guardian can receive a cancellation.
    os.setpgid(group, group)
    try:
        while True:
            remaining = deadline - time.monotonic()
            interval = remaining if args.rss_mib is None else min(0.25, remaining)
            readable, _, _ = select.select([launcher, ready], [], [], max(0, interval))
            if launcher in readable:
                why = os.read(launcher, 1)
                status = 128 + (why[0] if why else signal.SIGTERM)
                break
            if ready in readable:
                code = os.read(ready, 1)
                status = code[0] if code else 125
                break
            if time.monotonic() >= deadline:
                print("Benchmark wall-clock deadline expired.", file=sys.stderr, flush=True)
                status = 124
                break
            if args.rss_mib is not None:
                try:
                    rss = group_rss_kib(group, min(2, max(0.01, deadline - time.monotonic())))
                except subprocess.TimeoutExpired:
                    if time.monotonic() >= deadline:
                        print("Benchmark wall-clock deadline expired.", file=sys.stderr)
                        status = 124
                    else:
                        print("Benchmark RSS measurement timed out.", file=sys.stderr)
                        status = 125
                    break
                except (ValueError, OSError, subprocess.SubprocessError) as error:
                    print(f"Cannot sample benchmark RSS: {error}", file=sys.stderr)
                    status = 125
                    break
                if rss > args.rss_mib * 1024:
                    print(f"Benchmark process group exceeded {args.rss_mib} MiB RSS.",
                          file=sys.stderr, flush=True)
                    status = 125
                    break
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
    parser.add_argument("--rss-mib", type=int, help="sampled RSS ceiling for the command group")
    parser.add_argument("--cpu-seconds", type=int, help="CPU-time ceiling per process")
    parser.add_argument("seconds", type=int)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if os.name != "posix" or args.seconds <= 0 or not args.command:
        parser.error("provide a positive wall-clock deadline and command on POSIX")
    if any(value is not None and value <= 0 for value in (args.rss_mib, args.cpu_seconds)):
        parser.error("resource ceilings must be positive")
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
        os._exit(supervise(args, deadline, read_end))
    os.close(read_end)
    # The supervisor also sees EOF when SIGKILL prevents this process from
    # forwarding a signal. Only the launcher owns the pipe's write end.
    _, status = os.waitpid(guardian, 0)
    return exit_code(os.waitstatus_to_exitcode(status))


if __name__ == "__main__":
    sys.exit(main())
