#!/usr/bin/env bash
# Description:  Low-level discovery for HP Smart Array logical volumes
# Updated for Zabbix 7.0 + ssacli

data="/tmp/hp-raid-data-harvester.out"

if [ ! -f "$data" ]; then
  echo "$data not found." >&2
  exit 1
fi

# ld begin <slot> <ld> ###  ->  slot:ld
ld_list=$(sed -n '/ld section begin/,/ld section end/p' "$data" \
  | awk '/^### ld begin [0-9]+ [0-9]+/ {print $4":"$5}')

if [[ "${1:-}" == "raw" ]]; then
  for line in $ld_list; do echo "$line"; done
  exit 0
fi

echo -n '{"data":['
first=1
for ld in $ld_list; do
  [ $first -eq 0 ] && echo -n ','
  echo -n "{\"{#LD}\": \"$ld\"}"
  first=0
done
echo -n ']}'