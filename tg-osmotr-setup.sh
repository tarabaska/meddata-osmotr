#!/bin/bash
# Настройка бота на открытие формы осмотра.
#
# Использование:
#   ./tg-osmotr-setup.sh https://адрес-где-лежит-форма/
#
# Отправляет в ваш чат с ботом кнопку, которая открывает форму как
# мини-приложение. Кнопка нужна именно такого типа: только из неё
# заполненный осмотр возвращается обратно в чат.

set -euo pipefail

URL="${1:?укажите https-адрес формы}"
case "$URL" in
  https://*) ;;
  *) echo "Адрес должен начинаться с https:// — Telegram не откроет другой" >&2; exit 1;;
esac

TOKEN_FILE="$HOME/.burtsev-tg-token"
CHAT_FILE="$HOME/.burtsev-tg-chat"
[ -s "$TOKEN_FILE" ] || { echo "Нет токена бота в $TOKEN_FILE" >&2; exit 1; }
[ -s "$CHAT_FILE" ]  || { echo "Нет chat_id в $CHAT_FILE" >&2; exit 1; }

TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
CHAT=$(tr -d '[:space:]' < "$CHAT_FILE")
API="https://api.telegram.org/bot${TOKEN}"

KB=$(URL="$URL" python3 -c '
import json, os
print(json.dumps({
  "keyboard": [[{"text": "Открыть осмотр", "web_app": {"url": os.environ["URL"]}}]],
  "resize_keyboard": True,
  "is_persistent": True
}, ensure_ascii=False))')

curl -sS --max-time 30 -X POST "${API}/sendMessage" \
  -F "chat_id=${CHAT}" \
  -F "text=Форма осмотра готова. Кнопка «Открыть осмотр» внизу экрана — она останется здесь навсегда." \
  -F "reply_markup=${KB}" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("кнопка отправлена" if d.get("ok") else "ошибка: "+str(d.get("description")))'
