# Keycloak Center–Branch Replication (DEV)

Сценарии:
- `docker-compose.dev.yml` — центр+филиал на одном хосте (center:8080, branch:8081), `keycloak-branch` стартует после успешного `repl-init`.
- `docker-compose.center.dev.yml` — отдельный центр с импортом стартового realm `aritmos_platform`.
- `docker-compose.branch.dev.yml` — отдельный филиал, подключающийся к центру через логическую репликацию.

См. также:
- `PROMPT.full.md` — полный актуальный текст промта.
- `sql/center-publication-longtime.sql` — публикация non-session таблиц.
- `sql/branch-subscription-longtime.sql` — только управление подпиской (без ссылок на таблицы Keycloak).
- `repl-init/repl-init.sh` — инициализация репликации (ожидание таблиц, настройка публикации/подписки).
- `realms/aritmos-platform-realm.json` — стартовый realm и пользователь admin.
