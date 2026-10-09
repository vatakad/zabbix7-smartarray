#!/usr/bin/env bash
# Description:  Gathering available information about HP Smart Array devices.
# Description:  Analyze information and send data to Zabbix server.
# Updated for Zabbix 7.0 + ssacli

set -u
set -o pipefail

PATH="/usr/local/bin:/usr/local/sbin:/sbin:/bin:/usr/sbin:/usr/bin"
export PATH

ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"
BIN_DIR="/usr/local/bin/array"

# --- Определяем доступную утилиту: ssacli > hpssacli > hpacucli ---
if command -v ssacli &>/dev/null; then
  hpcli=$(command -v ssacli)
elif command -v hpssacli &>/dev/null; then
  hpcli=$(command -v hpssacli)
elif command -v hpacucli &>/dev/null; then
  hpcli=$(command -v hpacucli)
else
  echo "ssacli, hpssacli or hpacucli not installed" >&2
  exit 1
fi

if ! command -v zabbix_sender &>/dev/null; then
  echo "zabbix_sender not installed" >&2
  exit 1
fi

data_tmp="/tmp/hp-raid-data-harvester.tmp"
data_out="/tmp/hp-raid-data-harvester.out"
all_keys="/tmp/keys"
zbx_data="/tmp/zabbix-sender-hp-raid-data.in"

# ServerActive — правильный источник для zabbix_sender
zbx_servers=$(grep -E '^ServerActive=' "$ZBX_CONF" | cut -d= -f2- | tr ',' ' ')
[ -z "$zbx_servers" ] && zbx_servers=$(grep -E '^Server=' "$ZBX_CONF" | cut -d= -f2- | tr ',' ' ')
zbx_hostname=$(grep -E '^Hostname=' "$ZBX_CONF" | cut -d= -f2- | cut -d, -f1)
[ -z "$zbx_hostname" ] && zbx_hostname=$(hostname)

ctrl_list=$(${hpcli} ctrl all show 2>/dev/null | grep -oE 'Slot [0-9]+' | awk '{print $2}' | xargs echo)

: > "$data_tmp"

# --- Controllers ---
echo "### ctrl section begin ###" >> "$data_tmp"
for slot in $ctrl_list; do
  echo "### ctrl begin $slot ###" >> "$data_tmp"
  $hpcli ctrl slot=$slot show >> "$data_tmp" 2>/dev/null
  echo "### ctrl end $slot ###" >> "$data_tmp"
done
echo "### ctrl section end ###" >> "$data_tmp"

# --- Logical drives ---
echo "### ld section begin ###" >> "$data_tmp"
for slot in $ctrl_list; do
  ld_list=$($hpcli ctrl slot=$slot ld all show 2>/dev/null | grep -iw 'logicaldrive' | awk '{print $2}' | xargs echo)
  for ld in $ld_list; do
    echo "### ld begin $slot $ld ###" >> "$data_tmp"
    $hpcli ctrl slot=$slot ld $ld show >> "$data_tmp" 2>/dev/null
    echo "### ld end $slot $ld ###" >> "$data_tmp"
  done
done
echo "### ld section end ###" >> "$data_tmp"

# --- Physical drives ---
echo "### pd section begin ###" >> "$data_tmp"
for slot in $ctrl_list; do
  pd_list=$($hpcli ctrl slot=$slot pd all show 2>/dev/null | grep -iw 'physicaldrive' | awk '{print $2}' | xargs echo)
  for pd in $pd_list; do
    echo "### pd begin $slot $pd ###" >> "$data_tmp"
    $hpcli ctrl slot=$slot pd $pd show >> "$data_tmp" 2>/dev/null
    echo "### pd end $slot $pd ###" >> "$data_tmp"
  done
done
echo "### pd section end ###" >> "$data_tmp"

mv "$data_tmp" "$data_out"

: > "$all_keys"
: > "$zbx_data"

# --- Keys ---
for c in $("${BIN_DIR}/hp-raid-ctrl-discovery.sh" raw); do
  echo "hpraid.ctrl.status[$c]"
  echo "hpraid.cache.status[$c]"
  if grep -Fq 'Battery/Capacitor Status' "$data_out"; then
    echo "hpraid.bbu.status[$c]"
  fi
done >> "$all_keys"

for l in $("${BIN_DIR}/hp-raid-ld-discovery.sh" raw); do
  echo "hpraid.ld.status[$l]"
done >> "$all_keys"

for p in $("${BIN_DIR}/hp-raid-pd-discovery.sh" raw); do
  echo "hpraid.pd.status[$p]"
  if grep -Fq 'Current Temperature' "$data_out"; then
    echo "hpraid.pd.temperature[$p]"
  fi
done >> "$all_keys"

# --- Values ---
while read -r key; do
  case "$key" in
    *hpraid.ctrl.status*)
      slot=$(echo "$key" | grep -o '\[.*\]' | tr -d '[]' | cut -d, -f1)
      value=$(sed -n "/ctrl begin $slot /,/ctrl end $slot /p" "$data_out" \
        | grep -wE '[ ]+Controller Status:' | awk '{print $3}')
      echo "$zbx_hostname $key $value" >> "$zbx_data"
      ;;
    *hpraid.cache.status*)
      slot=$(echo "$key" | grep -o '\[.*\]' | tr -d '[]' | cut -d, -f1)
      value=$(sed -n "/ctrl begin $slot /,/ctrl end $slot /p" "$data_out" \
        | grep -wE '[ ]+Cache Status:' | awk '{print $3}')
      echo "$zbx_hostname $key $value" >> "$zbx_data"
      ;;
    *hpraid.bbu.status*)
      slot=$(echo "$key" | grep -o '\[.*\]' | tr -d '[]' | cut -d, -f1)
      value=$(sed -n "/ctrl begin $slot /,/ctrl end $slot /p" "$data_out" \
        | grep -wE '[ ]+Battery/Capacitor Status:' | awk '{print $3}')
      echo "$zbx_hostname $key $value" >> "$zbx_data"
      ;;
    *hpraid.ld.status*)
      slot=$(echo "$key" | grep -o '\[.*\]' | tr -d '[]' | cut -d: -f1)
      ld=$(echo "$key"   | grep -o '\[.*\]' | tr -d '[]' | cut -d: -f2)
      value=$(sed -n "/ld begin $slot $ld /,/ld end $slot $ld /p" "$data_out" \
        | grep -wE '[ ]+Status:' | awk '{print $2}')
      echo "$zbx_hostname $key $value" >> "$zbx_data"
      ;;
    *hpraid.pd.temperature*)
      slot=$(echo "$key" | grep -o '\[.*\]' | tr -d '[]' | cut -d: -f1)
      pd=$(echo "$key"   | grep -o '\[.*\]' | tr -d '[]' | cut -d: -f2-)
      value=$(sed -n "/pd begin $slot $pd /,/pd end $slot $pd /p" "$data_out" \
        | grep -wE '[ ]+Current Temperature \(C\):' | awk '{print $4}')
      echo "$zbx_hostname $key $value" >> "$zbx_data"
      ;;
    *hpraid.pd.status*)
      slot=$(echo "$key" | grep -o '\[.*\]' | tr -d '[]' | cut -d: -f1)
      pd=$(echo "$key"   | grep -o '\[.*\]' | tr -d '[]' | cut -d: -f2-)
      value=$(sed -n "/pd begin $slot $pd /,/pd end $slot $pd /p" "$data_out" \
        | grep -wE '[ ]+Status:' | awk '{print $2}')
      echo "$zbx_hostname $key $value" >> "$zbx_data"
      ;;
  esac
done < "$all_keys"

# --- Send ---
for zbx_server in $zbx_servers; do
  zabbix_sender -z "$zbx_server" -i "$zbx_data" >/dev/null 2>&1
done