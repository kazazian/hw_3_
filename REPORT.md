# Результаты проверок

## 4 балла
Образ собран, порт 8080 опубликован, GREETING передан.
Счётчик: 0 → 1 → 2 → 3. Запросы вернули HTTP 200.
Логи: logs-level4.txt.

## 6 баллов
После docker compose down и up -d счётчик остался 2.
Контейнер сменился: a2dd9d8f60a9 → 2e505a32af4a.
Данные сохранены в именованном volume.

## 8 баллов
После down/up с Redis значение N=3 сохранилось.
После stop redis: /healthz — 200, /readyz — 503,
POST /increment — 503.
После start redis без перезапуска app:
GET / — 3, следующий POST — 4.
Команды приведены в README, вывод — в check-run-1.log.

## 10 баллов
UID=10001, read-only=true, RAM=256 MiB, CPU=1.
Два последовательных запуска завершились SUCCESS:
- check-run-1.log — countercheck-tmpb8e3c2eyjf;
- check-run-2.log — countercheck-tmpuyr2gbh0qe.

Проверены: начальный 0, увеличение до 3, пересоздание app,
сохранение после down/up, отключение и восстановление Redis.
После остановки сервисов созданы tar-копии /data в backups/.
Тестовые проекты удалены вместе с volumes.



