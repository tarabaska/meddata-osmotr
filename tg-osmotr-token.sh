#!/bin/bash
# Подключение отдельного бота для формы осмотра.
#
# Токен вводится скрыто, сохраняется только на этом компьютере правами 600
# и нигде больше не показывается.
#
#   ./tg-osmotr-token.sh

set -euo pipefail

TOKEN_FILE="${OSMOTR_TOKEN_FILE:-$HOME/.osmotr-tg-token}"

echo "Подключение бота для формы осмотра."
echo
echo "Если бота ещё нет:"
echo "  1. В Telegram напишите @BotFather"
echo "  2. Команда /newbot"
echo "  3. Придумайте отображаемое имя, например: Осмотр лодыжек"
echo "  4. Придумайте адрес, он должен заканчиваться на bot,"
echo "     например: osmotr_lodyzhki_bot"
echo "  5. BotFather пришлёт строку вида 1234567890:AA..."
echo

read -r -s -p "Вставьте токен: " TOKEN
echo

TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]')
[ -n "$TOKEN" ] || { echo "Токен пустой" >&2; exit 1; }

case "$TOKEN" in
  *:*) ;;
  *) echo "Это не похоже на токен: в нём должно быть двоеточие" >&2; exit 1;;
esac

INFO=$(curl -sS --max-time 30 "https://api.telegram.org/bot${TOKEN}/getMe") || {
  echo "Не удалось связаться с Telegram" >&2; exit 1; }

NAME=$(printf '%s' "$INFO" | python3 -c '
import sys, json
d = json.load(sys.stdin)
if not d.get("ok"):
    print("")
else:
    r = d["result"]
    print("@" + r.get("username", "") + "|" + r.get("first_name", ""))
')

[ -n "$NAME" ] || { echo "Telegram не принял этот токен. Проверьте, что скопировали целиком." >&2; exit 1; }

printf '%s' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

USERNAME=${NAME%%|*}
TITLE=${NAME#*|}
echo
echo "Готово. Бот подключён: $USERNAME ($TITLE)"
echo "Токен лежит в $TOKEN_FILE и виден только вам."
echo
echo "Дальше:"
echo "  1. Откройте https://t.me/${USERNAME#@} и нажмите «Запустить»"
echo "  2. Запустите приём:  $(dirname "$0")/tg-osmotr-receive.sh --watch"
echo "  3. Ту же ссылку отправьте врачу — кнопка появится и у него"
