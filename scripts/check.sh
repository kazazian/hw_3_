#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

TEST_DIR=$(mktemp -d)
PROJECT="countercheck-$(basename "$TEST_DIR" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
STAGE="подготовка"
N=3

# Docker сам выбирает свободный порт на компьютере.
export APP_PORT="127.0.0.1:0"

dc() {
    case "$PROJECT" in
        countercheck-?*) ;;
        *)
            printf 'Отказ: имя проекта не является тестовым\n' >&2
            return 1
            ;;
    esac

    case "$PROJECT" in
        *[!a-z0-9-]*)
            printf 'Отказ: недопустимые символы в имени проекта\n' >&2
            return 1
            ;;
    esac

    COMPOSE_PROJECT_NAME="$PROJECT" docker compose \
        --env-file /dev/null \
        -p "$PROJECT" \
        -f compose.yaml "$@"
}

cleanup() {
    result=$?
    trap - EXIT HUP INT TERM

    if [ "$result" -ne 0 ]; then
        printf '\nОШИБКА на этапе: %s\n' "$STAGE" >&2
        dc logs --tail 30 >&2 || true
    fi

    if ! dc down -v --remove-orphans --timeout 10; then
        printf 'Ошибка очистки проекта %s\n' "$PROJECT" >&2
        result=1
    fi

    rm -rf "$TEST_DIR"
    exit "$result"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

stage() {
    STAGE=$1
    printf '\n=== %s ===\n' "$STAGE"
}

set_url() {
    ADDRESS=$(dc port app 8000)
    URL="http://$ADDRESS"
}

wait_ready() {
    attempt=0
    while [ "$attempt" -lt 60 ]; do
        if curl -fsS --connect-timeout 1 --max-time 3 \
            "$URL/readyz" >/dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    printf 'Истекло время ожидания готовности\n' >&2
    return 1
}

check_count() {
    method=$1
    path=$2
    expected=$3

    body=$(curl -fsS --connect-timeout 2 --max-time 5 \
        -X "$method" "$URL$path")

    actual=$(printf '%s' "$body" |
        dc exec -T app python -c \
        'import json,sys; print(json.load(sys.stdin)["count"])')

    if [ "$actual" != "$expected" ]; then
        printf 'Ожидали count=%s, получили %s\n' \
            "$expected" "$actual" >&2
        return 1
    fi

    printf '%s %s: count=%s — OK\n' "$method" "$path" "$actual"
}

check_status() {
    method=$1
    path=$2
    expected=$3

    actual=$(curl -sS --connect-timeout 2 --max-time 5 \
        -o /dev/null -w '%{http_code}' \
        -X "$method" "$URL$path")

    if [ "$actual" != "$expected" ]; then
        printf '%s %s: ожидали HTTP %s, получили %s\n' \
            "$method" "$path" "$expected" "$actual" >&2
        return 1
    fi

    printf '%s %s: HTTP %s — OK\n' "$method" "$path" "$actual"
}

stage "Новый проект с пустым хранилищем"
printf 'Проект: %s\n' "$PROJECT"
dc up -d --build --wait --wait-timeout 90
set_url
wait_ready
check_count GET / 0

stage "Ограничения приложения"
uid=$(dc exec -T app python -c 'import os; print(os.getuid())')
[ "$uid" -ne 0 ]

app_id=$(dc ps -q app)
limits=$(docker inspect "$app_id" --format \
    '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}')
[ "$limits" = "true 268435456 1000000000" ]
printf 'UID=%s; read-only=true; RAM=256 MiB; CPU=1 — OK\n' "$uid"

stage "Увеличение счётчика"
i=1
while [ "$i" -le "$N" ]; do
    check_count POST /increment "$i"
    i=$((i + 1))
done
check_count GET / "$N"

stage "Пересоздание только приложения"
redis_before=$(dc ps -q redis)
app_before=$(dc ps -q app)
dc up -d --no-deps --force-recreate --wait --wait-timeout 90 app
[ "$(dc ps -q redis)" = "$redis_before" ]
[ "$(dc ps -q app)" != "$app_before" ]
set_url
wait_ready
check_count GET / "$N"

stage "Сохранение после down и up"
dc down --timeout 10
dc up -d --wait --wait-timeout 90
set_url
wait_ready
check_count GET / "$N"

stage "Отключение Redis"
app_before=$(dc ps -q app)
started_before=$(docker inspect "$app_before" --format '{{.State.StartedAt}}')
dc stop --timeout 10 redis
check_status GET /healthz 200
check_status GET /readyz 503
check_status POST /increment 503

stage "Восстановление Redis без перезапуска приложения"
dc start redis
wait_ready
[ "$(dc ps -q app)" = "$app_before" ]
[ "$(docker inspect "$app_before" --format '{{.State.StartedAt}}')" = "$started_before" ]
check_count GET / "$N"
check_count POST /increment "$((N + 1))"

stage "Согласованная резервная копия"
mkdir -p backups
dc stop --timeout 30 app
dc stop --timeout 30 redis

redis_id=$(dc ps -a -q redis)
exit_code=$(docker inspect "$redis_id" --format '{{.State.ExitCode}}')
[ "$exit_code" = "0" ]

BACKUP="backups/$PROJECT.tar"
# Архив всего /data остановленного Redis с правами и структурой.
docker cp "$redis_id:/data/." - > "$BACKUP"
[ -s "$BACKUP" ]
printf 'Резервная копия: %s\n' "$BACKUP"

stage "Удаление тестового проекта вместе с volumes"
dc down -v --remove-orphans --timeout 10

printf '\nSUCCESS: все проверки пройдены, тестовые volumes удалены.\n'
