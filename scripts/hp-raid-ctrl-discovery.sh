#!/usr/bin/env bash
# Description:  Low-level discovery for HP Smart Array controllers
# Updated for Zabbix 7.0 + ssacli

data="/tmp/hp-raid-data-harvester.out"

if [ ! -f "$data" ]; then
  echo "$data not found." >&2
  exit 1
fi

# Устойчиво к любому количеству пробелов: берём поле после "begin"
ctrl_list=$(sed -n '/ctrl section begin/,/ctrl section end/p' "$data" \
  | awk '/^### ctrl begin [0-9]+/ {print $4}')

if [[ "${1:-}" == "raw" ]]; then
  for line in $ctrl_list; do echo "$line"; done
  exit 0
fi

echo -n '{"data":['
first=1
for ctrl in $ctrl_list; do
  [ $first -eq 0 ] && echo -n ','
  echo -n "{\"{#CTRL_SLOT}\": \"$ctrl\"}"
  first=0
done
echo -n ']}'