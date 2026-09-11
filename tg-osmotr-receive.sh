#!/bin/bash
# Приём заполненных осмотров из мини-приложения Telegram.
#
# Мини-приложение возвращает осмотр боту служебным сообщением, которого
# в чате не видно. Этот скрипт его забирает, кладёт файл «Фамилия - Код.json»
# на диск, собирает из него PDF на один лист и присылает в чат оба:
# PDF — читать и подшивать, JSON — для программы.
#
# Использование:
#   ./tg-osmotr-receive.sh              — забрать всё новое
#   ./tg-osmotr-receive.sh --watch      — забирать каждые 15 секунд
#
# Данные никуда не уходят: читаются у бота, пишутся на диск и возвращаются
# в тот же чат, откуда пришли.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN_FILE="$HOME/.burtsev-tg-token"
OFFSET_FILE="$HOME/.osmotr-tg-offset"
OUT_DIR="${OSMOTR_DIR:-$HOME/MedData/osmotry}"

[ -s "$TOKEN_FILE" ] || { echo "Нет токена бота в $TOKEN_FILE" >&2; exit 1; }
TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
API="https://api.telegram.org/bot${TOKEN}"
mkdir -p "$OUT_DIR"

pull() {
  local offset resp
  offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
  resp=$(curl -sS --max-time 40 "${API}/getUpdates?offset=${offset}&timeout=0&allowed_updates=%5B%22message%22%5D") || return 0
  OUT_DIR="$OUT_DIR" OFFSET_FILE="$OFFSET_FILE" API="$API" HERE="$SCRIPT_DIR" \
    python3 - "$resp" <<'PYEOF'
import json, os, re, sys, datetime, subprocess

resp = json.loads(sys.argv[1])
if not resp.get("ok"):
    print("Telegram вернул ошибку:", resp.get("description"))
    raise SystemExit(0)

out_dir = os.environ["OUT_DIR"]
offset_file = os.environ["OFFSET_FILE"]
api = os.environ["API"]
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

    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
    saved += 1
    a = payload.get("a") or {}
    print("сохранён:", os.path.basename(path), "| AOFAS", a.get("total", "—"))

    pdf_path = None
    try:
        sys.path.insert(0, os.environ.get("HERE", "."))
        import osmotr_pdf
        pdf_path = osmotr_pdf.build(path)
        print("   PDF собран:", os.path.basename(pdf_path))
    except Exception as exc:
        print("   PDF собрать не удалось:", exc)

    chat = (msg.get("chat") or {}).get("id")
    if chat:
        def send(fpath, cap):
            r = subprocess.run([
                "curl", "-sS", "--max-time", "90", "-X", "POST",
                api + "/sendDocument",
                "-F", "chat_id=" + str(chat),
                "-F", "document=@" + fpath,
                "-F", "caption=" + cap[:1000],
            ], capture_output=True, text=True)
            try:
                return json.loads(r.stdout).get("ok", False)
            except Exception:
                return False

        if pdf_path:
            ok = send(pdf_path, payload.get("txt") or "Осмотр после перелома лодыжек")
            print("   PDF отправлен в чат" if ok else "   PDF в чат отправить не удалось")
        ok = send(path, "Тот же осмотр для программы")
        print("   JSON отправлен в чат" if ok else "   JSON в чат отправить не удалось")

if last is not None:
    with open(offset_file, "w") as fh:
        fh.write(str(last))

if saved == 0:
    print("новых осмотров нет")
PYEOF
}

if [ "${1:-}" = "--watch" ]; then
  echo "Слежу за новыми осмотрами. Папка: $OUT_DIR"
  echo "Ctrl+C чтобы остановить."
  while true; do pull; sleep 15; done
else
  pull
  echo "Папка с осмотрами: $OUT_DIR"
fi
