#!/usr/bin/env bash
# Description:  Low-level discovery for HP Smart Array physical drives
# Updated for Zabbix 7.0 + ssacli

data="/tmp/hp-raid-data-harvester.out"

if [ ! -f "$data" ]; then
  echo "$data not found." >&2
  exit 1
fi

# pd begin <slot> <pd> ###  ->  slot:pd
# pd может быть "1:1" или "1I:1:1" или "2C:1:2" - берём всё как одно поле
pd_list=$(sed -n '/pd section begin/,/pd section end/p' "$data" \
  | awk '/^### pd begin [0-9]+ / {sub(/ ###.*/, "", $5); print $4":"$5}')

if [[ "${1:-}" == "raw" ]]; then
  for line in $pd_list; do echo "$line"; done
  exit 0
fi

echo -n '{"data":['
first=1
for pd in $pd_list; do
  [ $first -eq 0 ] && echo -n ','
  echo -n "{\"{#PD}\": \"$pd\"}"
  first=0
done
echo -n ']}'