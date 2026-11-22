#!/bin/sh
# Place, autoroute with Freerouting (retrying until DRC finds no unconnected
# items), pour GND and run DRC. Needs KiCad 7 (pcbnew Python), Java,
# Freerouting 1.9 (FREEROUTING=path/to/freerouting.jar) and xvfb-run.

cd "$(dirname "$0")/.."
FR=${FREEROUTING:-$HOME/tools/freerouting/freerouting.jar}
for try in 1 2 3 4 5 6; do
  python3 gen/make_pcb.py place
  rm -f gen/UzeTang-Board.ses
  (cd gen && xvfb-run -a java -jar "$FR" -de UzeTang-Board.dsn -do UzeTang-Board.ses -mp 300 > fr.log 2>&1)
  python3 gen/make_pcb.py finish
  out=$(python3 gen/drc.py UzeTang-Board.kicad_pcb)
  echo "try $try: $(echo "$out" | tail -1)"
  echo "$out" | grep -q "unconnected" || break
done
python3 gen/make_sch.py
