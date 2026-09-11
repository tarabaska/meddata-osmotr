#!/bin/bash
# Приём заполненных осмотров из мини-приложения Telegram.
#
# Мини-приложение возвращает заполненный осмотр в чат методом sendData.
# Этот скрипт забирает такие сообщения у бота и раскладывает их файлами
# «Код - Фамилия.json» — теми самыми, что потом читает программа на компьютере.
#
# Использование:
#   ./tg-osmotr-receive.sh              — забрать всё новое
#   ./tg-osmotr-receive.sh --watch      — забирать каждые 20 секунд
#
# Данные никуда не отправляются: только читаются у бота и пишутся на диск.

set -euo pipefail

TOKEN_FILE="$HOME/.burtsev-tg-token"
OFFSET_FILE="$HOME/.osmotr-tg-offset"
OUT_DIR="${OSMOTR_DIR:-$HOME/MedData/osmotry}"

[ -s "$TOKEN_FILE" ] || { echo "Нет токена бота в $TOKEN_FILE" >&2; exit 1; }
TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
API="https://api.telegram.org/bot${TOKEN}"
mkdir -p "$OUT_DIR"

pull() {
  local offset
  offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
  local resp
  resp=$(curl -sS --max-time 40 "${API}/getUpdates?offset=${offset}&timeout=0&allowed_updates=%5B%22message%22%5D") || return 0
  OUT_DIR="$OUT_DIR" OFFSET_FILE="$OFFSET_FILE" python3 - "$resp" <<'PY'
import json, os, re, sys, datetime

resp = json.loads(sys.argv[1])
if not resp.get("ok"):
    print("Telegram вернул ошибку:", resp.get("description")); raise SystemExit(0)

out_dir = os.environ["OUT_DIR"]
offset_file = os.environ["OFFSET_FILE"]
last = None
saved = 0

def safe(name):
    name = re.sub(r'[/\\:*?"<>|]', "", name or "").strip()
    return re.sub(r"\s+", " ", name) or "osmotr"

for upd in resp.get("result", []):
    last = upd["update_id"] + 1
    msg = upd.get("message") or {}
    wad = msg.get("web_app_data")
    if not wad:
        continue
    try:
        payload = json.loads(wad.get("data", ""))
    except Exception:
        print("Пришло сообщение, которое не разбирается как осмотр — пропущено")
        continue
    if payload.get("f") != "osmotr-lodyzhki":
        continue

    name = safe(payload.get("n") or "")
    if not name.endswith(".json"):
        name += ".json"
    path = os.path.join(out_dir, name)
    if os.path.exists(path):
        stamp = datetime.datetime.now().strftime("%H-%M-%S")
        path = os.path.join(out_dir, name[:-5] + " (" + stamp + ").json")

    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    saved += 1
    a = payload.get("a") or {}
    print("сохранён:", os.path.basename(path), "| AOFAS", a.get("total", "—"))

if last is not None:
    with open(offset_file, "w") as f:
        f.write(str(last))

if saved == 0:
    print("новых осмотров нет")
PY
}

if [ "${1:-}" = "--watch" ]; then
  echo "Слежу за новыми осмотрами. Папка: $OUT_DIR. Ctrl+C чтобы остановить."
  while true; do pull; sleep 20; done
else
  pull
  echo "Папка с осмотрами: $OUT_DIR"
fi
