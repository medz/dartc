#!/bin/sh
set -eu

input=$1
output=
while [ "$#" -gt 0 ]; do
  if [ "$1" = '-o' ]; then
    output=$2
    shift 2
  else
    shift
  fi
done

printf 'invoked\n' > compiler-ran
case "${BENCH_TEST_MUTATE:-}" in
  compiler) printf '\n# changed\n' >> "$0" ;;
  workload) printf '\n// changed\n' >> "$input" ;;
esac
case "${BENCH_TEST_COMPILE_MODE:-ok}" in
  hang) printf 'before timeout\n' >&2; exec sleep 60 ;;
  fail) printf 'compile failure\n' >&2; exit 23 ;;
  no-output) exit 0 ;;
  bad-output) printf '#!/missing-interpreter\n' > "$output"; chmod +x "$output"; exit 0 ;;
esac
if [ "${BENCH_TEST_LOGS:-}" = long ]; then
  head -c 100000 /dev/zero | tr '\000' o
  printf '\nstdout-final-marker\n'
  head -c 100000 /dev/zero | tr '\000' e >&2
  printf '\nstderr-final-marker\n' >&2
fi
sleep "${BENCH_TEST_DELAY:-0}"
cat > "$output" <<'PROGRAM'
#!/bin/sh
printf 'invoked\n' >> output-ran
case "${BENCH_TEST_RUN_MODE:-ok}" in
  hang) printf 'before timeout\n' >&2; exec sleep 60 ;;
  child-hang) sleep 60 & printf '%s\n' "$!" > output-child; wait ;;
  fail) printf 'hello\n'; printf 'run failure\n' >&2; exit 17 ;;
  wrong) printf 'wrong\n'; exit 0 ;;
esac
printf 'hello\n'
PROGRAM
printf '\n#%s\n' "${BENCH_TEST_PADDING:-}" >> "$output"
chmod +x "$output"
