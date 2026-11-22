#!/bin/sh
# Generate, assemble and lock-step test N random programs.
# usage: run_fuzz.sh first_seed count [instructions]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SIM=$HERE/../sim/lsobj/Vls_top
OUT=$HERE/build/fuzz
mkdir -p "$OUT"
S=${1:-1}; N=${2:-10}; I=${3:-300000}
fail=0
i=0
while [ $i -lt "$N" ]; do
  seed=$((S + i))
  python3 "$HERE/gen_fuzz.py" $seed > "$OUT/f$seed.S"
  avr-gcc -mmcu=atmega644 -nostartfiles -nostdlib -x assembler-with-cpp \
      "$OUT/f$seed.S" -o "$OUT/f$seed.elf"
  avr-objcopy -O ihex "$OUT/f$seed.elf" "$OUT/f$seed.hex"
  if ! "$SIM" "$OUT/f$seed.hex" -n "$I" -m 997 -q; then fail=$((fail + 1)); fi
  i=$((i + 1))
done
echo "fuzz: $N programs, $fail failed"
[ $fail -eq 0 ]
