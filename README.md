# Docker: приложение со счётчиком

Код в app/ не изменён. Требуются Docker с Compose, curl и shell.

## Настройки

```sh
cp .env.example .env
```

В .env: APP_PORT — внешний порт, GREETING — приветствие,
COMPOSE_PROJECT_NAME — имя проекта. В примерах порт 8080.

## Уровень 4: один контейнер

```sh
docker build -t counter-app .
docker run -d --name counter-app -p 8080:8000 -e GREETING='Hello, Arina!' counter-app
curl --max-time 5 http://localhost:8080/
curl --max-time 5 -X POST http://localhost:8080/increment
docker logs counter-app
docker stop counter-app
```

Логи: logs-level4.txt.

## Уровень 6: Compose и SQLite

```sh
docker compose -f compose.sqlite.yaml up -d --build
```

После запуска выполните несколько POST /increment и запомните count:

```sh
curl --max-time 5 -X POST http://localhost:8080/increment
docker compose -f compose.sqlite.yaml down
docker compose -f compose.sqlite.yaml up -d
curl --max-time 5 http://localhost:8080/
```

Дождитесь запуска приложения перед запросами.
Volume counter-data сохраняет счётчик.
Перед запуском варианта с Redis:

```sh
docker compose -f compose.sqlite.yaml down
```

## Уровни 8–10: Redis

```sh
docker compose up -d --build --wait --wait-timeout 90
curl --max-time 5 http://localhost:8080/
curl --max-time 5 -X POST http://localhost:8080/increment
```

app использует STORAGE=redis и REDIS_URL=redis://redis:6379/0.
Оба сервиса имеют healthcheck. Опубликован только порт app.
Redis сохраняет AOF в volume redis-data, подключённый к /data.

```sh
docker compose down
docker compose up -d --wait --wait-timeout 90
```

Счётчик сохраняется. Не используйте down -v для сохранения данных.

Проверка отключения Redis:

```sh
docker compose stop redis
curl --max-time 5 -w '\nHTTP %{http_code}\n' http://localhost:8080/healthz
curl --max-time 5 -w '\nHTTP %{http_code}\n' http://localhost:8080/readyz
curl --max-time 5 -w '\nHTTP %{http_code}\n' -X POST http://localhost:8080/increment
docker compose start redis
curl --fail --retry 15 --retry-delay 1 --retry-max-time 60 --max-time 3 http://localhost:8080/readyz
curl --max-time 5 http://localhost:8080/
curl --max-time 5 -X POST http://localhost:8080/increment
```

При отключении ожидаются HTTP 200/503/503.
После восстановления — прежний count и затем count+1,
без перезапуска app.

Ограничения app: UID 10001, read-only, RAM 256 MiB, CPU 1.

## Автоматическая проверка

```sh
./scripts/check.sh
```

Скрипт создаёт отдельный проект с пустым volume и свободным портом.
Проверяет счётчик, ограничения, пересоздание app, down/up и сбой Redis.
У запросов и ожидания готовности есть тайм-ауты.
При ошибке сообщает этап и возвращает ненулевой код.
Trap удаляет только собственные тестовые ресурсы.

После остановки app и Redis весь /data архивируется с правами
и структурой в backups/<проект>.tar, затем выполняется down -v.
Архив остаётся на компьютере; backups/ исключён из Git.

Два успешных запуска: check-run-1.log и check-run-2.log.
Результаты: REPORT.md.
