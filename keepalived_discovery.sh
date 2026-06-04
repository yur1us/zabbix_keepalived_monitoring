#!/usr/bin/env bash

set -euo pipefail

## ── Конфигурация ────────────────────────────────────────
DATA_FILE="${KEEPALIVED_DATA_FILE:-/tmp/keepalived.data}"
PID_FILE="${KEEPALIVED_PID:-/run/keepalived.pid}"
WAIT_SEC="${KEEPALIVED_WAIT:-0.5}"

## ── Функция: пустой JSON при ошибке ─────────────────────
empty_json() {
  echo '{"data":[]}'
  exit 0
}

## ── Проверяем, жив ли keepalived ─────────────────────────
if [[ ! -f "$PID_FILE" ]]; then
  echo "keepalived pid not found: $PID_FILE" >&2
  empty_json
fi

KA_PID=$(<"$PID_FILE")
if ! kill -0 "$KA_PID" 2>/dev/null; then
  echo "keepalived pid $KA_PID not alive" >&2
  empty_json
fi

## ── Шлём USR1 → keepalived пишет дамп в DATA_FILE ───────
# Удаляем старый файл, если он остался, чтобы не прочитать устаревшие данные
rm -f "$DATA_FILE"

kill -USR1 "$KA_PID" 2>/dev/null || empty_json
sleep "$WAIT_SEC"

if [[ ! -s "$DATA_FILE" ]]; then
  echo "data file empty or missing: $DATA_FILE" >&2
  empty_json
fi

## ── Парсим дамп ──────────────────────────────────────────
instances=()
ifaces=()
vrids=()
states=()

cur_inst=""
cur_iface="unknown"
cur_vrid="0"
cur_state="UNKNOWN"

flush_instance() {
  if [[ -n "$cur_inst" ]]; then
    instances+=("$cur_inst")
    ifaces+=("$cur_iface")
    vrids+=("$cur_vrid")
    states+=("$cur_state")
  fi
}

while IFS= read -r line; do
  # Удаляем начальные пробелы
  line="${line#"${line%%[![:space:]]*}"}"

  case "$line" in
    "VRRP Instance = "*)
      flush_instance
      cur_inst="${line#VRRP Instance = }"
      cur_iface="unknown"
      cur_vrid="0"
      cur_state="UNKNOWN"
      ;;
    "Interface = "*)
      cur_iface="${line#Interface = }"
      ;;
    "VRRP Id = "*)
      cur_vrid="${line#VRRP Id = }"
      ;;
    "State = "*)
      raw_state="${line#State = }"
      # Маппинг внутренних статусов в понятные MASTER / BACKUP / FAULT
      if [[ "$raw_state" == "UP, RUNNING" ]]; then
        cur_state="MASTER"
      elif [[ "$raw_state" == "not UP, not RUNNING" ]]; then
        cur_state="BACKUP"
      elif [[ "$raw_state" == *"FAULT"* || "$raw_state" == *"ERR"* ]]; then
        cur_state="FAULT"
      else
        cur_state="$raw_state" # На случай других редких статусов (INIT и т.д.)
      fi
      ;;
  esac
done < "$DATA_FILE"

flush_instance

if [[ ${#instances[@]} -eq 0 ]]; then
  echo "no VRRP instances found in $DATA_FILE" >&2
  empty_json
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

out='{"data":['
sep=""

for i in "${!instances[@]}"; do
  inst=$(json_escape "${instances[$i]}")
  iface=$(json_escape "${ifaces[$i]}")
  vrid=$(json_escape "${vrids[$i]}")
  state=$(json_escape "${states[$i]}")

  out+="$sep"
  out+='{'
  out+='"instance":"'"$inst"'",'
  out+='"iface":"'"$iface"'",'
  out+='"vrid":"'"$vrid"'",'
  out+='"state":"'"$state"'"'
  out+='}'
  sep=","
done

out+=']}'
echo "$out"

