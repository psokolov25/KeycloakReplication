# Keycloak Center–Branch Replication (DEV)

Этот проект разворачивает стенд Keycloak 24 в архитектуре «Центр–Филиал» с:

- двумя PostgreSQL 16 (`pg-center`, `pg-branch`);
- двумя Keycloak 24 (`keycloak-center`, `keycloak-branch`);
- логической репликацией «долгоиграющих» сущностей (realm, users, roles, groups и т.п.) с центра на филиал;
- стартовым Realm `aritmos_platform` с пользователем `admin` и группой `REGION` (атрибут `type=region`);
- службой `repl-init`, которая с учётом миграций Keycloak инициализирует публикацию/подписку.

## 1. Файлы проекта

- `docker-compose.dev.yml` — сценарий «центр+филиал на одном хосте».
- `docker-compose.center.dev.yml` — отдельный стенд центра.
- `docker-compose.branch.dev.yml` — отдельный стенд филиала.
- `repl-init/repl-init.sh` — скрипт инициализации логической репликации (ожидание схемы, публикация, подписка).
- `sql/center-publication-longtime.sql` — динамическая публикация «долгоиграющих» таблиц на центре.
- `sql/branch-subscription-longtime.sql` — безопасная подписка на филиале.
- `realms/aritmos-platform-realm.json` — стартовый Realm `aritmos_platform`.
- `PROMPT.full.md` — полный актуальный промт.

## 2. Запуск DEV-сценария (центр+филиал на одном хосте)

```bash
docker compose -f docker-compose.dev.yml up -d
```

После старта:

- `keycloak-center` доступен на `http://localhost:8080`;
- `keycloak-branch` доступен на `http://localhost:8081`;
- логинизация в master-реалм: `admin` / `admin` (переменные `KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD`);
- в центре автоматически импортируется Realm `aritmos_platform` из `realms/aritmos-platform-realm.json`.

Служба `repl-init`:

- ждёт 400 секунд (`REPL_INIT_INITIAL_SLEEP`) для завершения миграций Keycloak;
- затем проверяет наличие ключевых таблиц (`realm`, `user_entity` и др.) на центре и филиале;
- создаёт публикацию `keycloak_longtime_pub` (без таблиц сессий);
- создаёт подписку `keycloak_longtime_sub` на филиале;
- выводит результат `SELECT * FROM pg_stat_subscription`.

## 3. Проверка репликации

На филиале (через `psql` в контейнер `pg-branch`):

```bash
docker exec -it pg-branch psql -U keycloak -d keycloak
SELECT id, name FROM realm;
SELECT username FROM user_entity;
```

Вы должны увидеть:

- Realm `aritmos_platform`;
- пользователя `admin` из этого realm (после выполнения начального `COPY` подписки).

Если реалм/пользователь в БД есть, но не виден в UI `keycloak-branch` — это ожидаемое поведение: Keycloak филиала кеширует конфигурацию. В простейшем варианте:

```bash
docker restart keycloak-branch
```

после чего при следующем старте кэши будут подняты уже над реплицированными данными.

## 4. Ограничения архитектуры

- Репликация реализована на уровне БД (PostgreSQL logical replication).
- Инвалидация и синхронизация кэшей Keycloak между центром и филиалом в этом проекте **не реализована**.
- Для автоматического подхвата новых реалмов/пользователей на филиале без рестартов нужен дополнительный слой:
  - либо KeycloakProxy с собственным кэшем и логикой refresh;
  - либо агенты, вызывающие Admin REST API для явной инвалидации кэшей или их прогрева.

## 5. Переменные и логирование

Во всех compose-файлах:

- Keycloak запускается с `KC_LOG_LEVEL=DEBUG` для упрощения диагностики;
- порты проброшены:
  - `keycloak-center`:
    - `docker-compose.dev.yml` — `8080:8080`;
    - `docker-compose.center.dev.yml` — `8080:8080`;
  - `keycloak-branch`:
    - `docker-compose.dev.yml` — `8081:8080`;
    - `docker-compose.branch.dev.yml` — `8080:8080`.

Для диагностики проблем с репликацией используйте:

```bash
docker logs repl-init
docker logs pg-center
docker logs pg-branch
```

и на филиале:

```sql
SELECT * FROM pg_stat_subscription;
```

## 6. Диагностика при ошибках

Если `repl-init` падает по тайм-ауту ожидания таблиц:

1. Проверьте логи `keycloak-center` (ошибки миграций, подключения к БД).
2. Проверьте наличие таблиц в `pg-center`:

```sql
SELECT table_name
  FROM information_schema.tables
 WHERE table_schema = 'public'
 ORDER BY table_name;
```

3. Сверьте параметры подключения в compose-файлах:
   - `POSTGRES_*` у `pg-center` / `pg-branch`;
   - `KC_DB_*` у `keycloak-center` / `keycloak-branch`.

# KeycloakReplication
