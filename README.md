# ДЗ по Docker

Приложение со счётчиком запускается в Docker. Исходники в `app/` не менялись.

Для запуска нужны Docker с Compose и curl.

## Настройки

Скопировать пример настроек:

```sh
cp .env.example .env
```

В `.env` можно изменить:
- `APP_PORT` — порт на компьютере;
- `GREETING` — приветствие;
- `COMPOSE_PROJECT_NAME` — имя проекта.

В командах ниже используется порт 8080.

## Один контейнер

```sh
docker build -t counter-app .
docker run -d --name counter-app -p 8080:8000 -e GREETING='Hello, Arina!' counter-app
```

Проверка счётчика и просмотр логов:

```sh
curl --max-time 5 http://localhost:8080/
curl --max-time 5 -X POST http://localhost:8080/increment
docker logs counter-app
```

Логи проверки сохранены в `logs-level4.txt`.

Перед запуском через Compose нужно освободить порт:

```sh
docker stop counter-app
```

## Compose с SQLite

Для этого этапа используется `compose.sqlite.yaml`:

```sh
docker compose -f compose.sqlite.yaml up -d --build
```

После запуска приложения увеличить счётчик:

```sh
curl --max-time 5 -X POST http://localhost:8080/increment
```

Пересоздать контейнер и проверить значение:

```sh
docker compose -f compose.sqlite.yaml down
docker compose -f compose.sqlite.yaml up -d
```

Когда приложение запустится:

```sh
curl --max-time 5 http://localhost:8080/
```

Счётчик сохраняется в volume `counter-data`.

Перед переходом к Redis:

```sh
docker compose -f compose.sqlite.yaml down
```

## Compose с Redis

Основной `compose.yaml` запускает сервисы `app` и `redis`:

```sh
docker compose up -d --build --wait --wait-timeout 90
```

Для приложения заданы `STORAGE=redis` и `REDIS_URL=redis://redis:6379/0`.
Оба сервиса имеют healthcheck. На компьютере открыт только порт приложения.

Данные Redis хранятся в volume `redis-data`, подключённом к `/data`.
Запись на диск включена через AOF.

Проверка сохранения данных:

```sh
curl --max-time 5 -X POST http://localhost:8080/increment
docker compose down
docker compose up -d --wait --wait-timeout 90
curl --max-time 5 http://localhost:8080/
```

Значение счётчика должно сохраниться. Команда `down -v` удаляет volumes, поэтому в этой проверке она не используется.

### Отключение Redis

```sh
docker compose stop redis
curl --max-time 5 -w '\nHTTP %{http_code}\n' http://localhost:8080/healthz
curl --max-time 5 -w '\nHTTP %{http_code}\n' http://localhost:8080/readyz
curl --max-time 5 -w '\nHTTP %{http_code}\n' -X POST http://localhost:8080/increment
```

Ожидаемые ответы: 200, 503 и 503.

Запуск Redis и повторная проверка:

```sh
docker compose start redis
curl --fail --retry 15 --retry-delay 1 --retry-max-time 60 --max-time 3 http://localhost:8080/readyz
curl --max-time 5 http://localhost:8080/
curl --max-time 5 -X POST http://localhost:8080/increment
```

После восстановления возвращается прежнее значение счётчика, следующий POST увеличивает его на 1. Перезапускать приложение не нужно.

## Ограничения приложения

Процесс работает с UID 10001. Корневая файловая система доступна только для чтения. Лимиты: 256 MiB памяти и одно ядро CPU.

## Скрипт проверки

```sh
./scripts/check.sh
```

Скрипт создаёт отдельный Compose-проект с пустым хранилищем и свободным портом. Проверяет увеличение счётчика, сохранение данных после пересоздания контейнеров, отключение и восстановление Redis, а также ограничения приложения.

У запросов и ожидания готовности есть тайм-ауты. При ошибке скрипт выводит этап и завершается с ненулевым кодом. Для очистки тестовых ресурсов используется `trap`.

Для резервного копирования скрипт останавливает приложение и Redis, затем сохраняет весь каталог `/data` с правами и структурой в `backups/<проект>.tar`. После этого удаляет тестовый проект вместе с volumes. Архив остаётся на компьютере, папка `backups/` исключена из Git.

Вывод двух успешных запусков сохранён в `check-run-1.log` и `check-run-2.log`. Результаты проверок описаны в `REPORT.md`.