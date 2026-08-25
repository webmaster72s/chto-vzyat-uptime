#!/usr/bin/env bash
set -u

BASE_URL="${BASE_URL:-https://chto-vzyat.ru}"
ATTEMPTS="${ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-15}"
REPORT_FILE="${REPORT_FILE:-uptime-report.md}"
USER_AGENT="ChtoVzyat-Uptime/1.0"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

check_once() {
  local attempt="$1"
  local home_result catalog_result www_result index_result
  local home_code home_time catalog_code www_code www_location index_code index_location
  local ok=1

  home_result="$(curl --silent --show-error --connect-timeout 10 --max-time 25 \
    --user-agent "$USER_AGENT" --output "$tmp_dir/home.html" \
    --write-out '%{http_code}|%{time_total}' "$BASE_URL/" 2>"$tmp_dir/home.err")" || ok=0
  IFS='|' read -r home_code home_time <<<"$home_result"

  catalog_result="$(curl --silent --show-error --connect-timeout 10 --max-time 25 \
    --user-agent "$USER_AGENT" --output "$tmp_dir/catalog.js" \
    --write-out '%{http_code}' "$BASE_URL/catalog-data.js" 2>"$tmp_dir/catalog.err")" || ok=0
  catalog_code="$catalog_result"

  www_result="$(curl --silent --show-error --connect-timeout 10 --max-time 25 \
    --user-agent "$USER_AGENT" --output /dev/null \
    --write-out '%{http_code}|%{redirect_url}' \
    'https://www.chto-vzyat.ru/monitor-check?source=github' 2>"$tmp_dir/www.err")" || ok=0
  IFS='|' read -r www_code www_location <<<"$www_result"

  index_result="$(curl --silent --show-error --connect-timeout 10 --max-time 25 \
    --user-agent "$USER_AGENT" --output /dev/null \
    --write-out '%{http_code}|%{redirect_url}' \
    "$BASE_URL/index.html?source=github" 2>"$tmp_dir/index.err")" || ok=0
  IFS='|' read -r index_code index_location <<<"$index_result"

  [[ "$home_code" == "200" ]] || ok=0
  grep -q 'Подходящие модели без рекламного шума' "$tmp_dir/home.html" 2>/dev/null || ok=0
  [[ "$catalog_code" == "200" ]] || ok=0
  grep -q 'window.CV_CATALOG' "$tmp_dir/catalog.js" 2>/dev/null || ok=0
  [[ "$www_code" == "301" && "$www_location" == "$BASE_URL/monitor-check?source=github" ]] || ok=0
  [[ "$index_code" == "301" && "$index_location" == "$BASE_URL/?source=github" ]] || ok=0

  {
    echo "### Попытка $attempt из $ATTEMPTS"
    echo
    echo "- Время UTC: $(date -u '+%Y-%m-%d %H:%M:%S')"
    echo "- Главная: HTTP ${home_code:-ошибка}, ${home_time:-n/a} с"
    echo "- Каталог: HTTP ${catalog_code:-ошибка}"
    echo "- www: HTTP ${www_code:-ошибка} -> ${www_location:-нет ответа}"
    echo "- /index.html: HTTP ${index_code:-ошибка} -> ${index_location:-нет ответа}"
    for name in home catalog www index; do
      if [[ -s "$tmp_dir/$name.err" ]]; then
        echo "- curl $name: $(tr '\n' ' ' <"$tmp_dir/$name.err")"
      fi
    done
    echo
  } >>"$REPORT_FILE"

  [[ "$ok" == "1" ]]
}

{
  echo "## Внешняя проверка chto-vzyat.ru"
  echo
} >"$REPORT_FILE"

for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
  if check_once "$attempt"; then
    echo "Сайт доступен (попытка $attempt)."
    exit 0
  fi
  if ((attempt < ATTEMPTS)); then
    sleep "$RETRY_DELAY"
  fi
done

echo "Сайт не прошёл $ATTEMPTS внешние проверки подряд." >&2
exit 1