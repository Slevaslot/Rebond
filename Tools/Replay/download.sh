#!/bin/sh
# Downloads UI-PRMD Kinect segmented movements (correct and incorrect) into <destination>.
# usage: download.sh <destination> <movement number>... e.g. download.sh ~/uiprmd 4 8
# Movements: 1 deep squat, 2 hurdle step, 3 inline lunge, 4 side lunge, 5 sit to stand,
# 6 standing active straight leg raise, 7 standing shoulder abduction, 8 standing shoulder extension,
# 9 standing shoulder internal-external rotation, 10 standing shoulder scaption.
set -e
DEST="$1"; shift
BASE="https://raw.githubusercontent.com/jkaethee/UI-PRMD_Exercise_Model/HEAD"
CONFIG="$(mktemp)"
for m in "$@"; do
  M=$(printf "m%02d" "$m")
  for s in 01 02 03 04 05 06 07 08 09 10; do for e in 01 02 03 04 05 06 07 08 09 10; do
    for kind in Positions:positions Angles:angles; do
      DIR=${kind%%:*}; NAME=${kind##*:}
      echo "url = \"$BASE/Segmented%20Movements/Kinect/$DIR/${M}_s${s}_e${e}_${NAME}.txt\"" >> "$CONFIG"
      echo "output = \"$DEST/correct/Kinect/$DIR/${M}_s${s}_e${e}_${NAME}.txt\"" >> "$CONFIG"
      echo "url = \"$BASE/Incorrect%20Segmented%20Movements/Kinect/$DIR/${M}_s${s}_e${e}_${NAME}_inc.txt\"" >> "$CONFIG"
      echo "output = \"$DEST/incorrect/Kinect/$DIR/${M}_s${s}_e${e}_${NAME}_inc.txt\"" >> "$CONFIG"
    done
  done; done
done
curl --create-dirs --parallel --parallel-max 16 --silent --fail --config "$CONFIG" || true
rm "$CONFIG"
echo "Downloaded to $DEST"
