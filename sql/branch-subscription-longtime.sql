-- sql/branch-subscription-longtime.sql
-- Безопасная настройка подписки на публикацию keycloak_longtime_pub.
-- ВАЖНО: здесь НЕТ ссылок на конкретные таблицы схемы Keycloak.
-- Скрипт управляет только подпиской: DISABLE (если есть), DROP, CREATE.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_subscription WHERE subname = 'keycloak_longtime_sub') THEN
    RAISE NOTICE 'Disabling existing subscription keycloak_longtime_sub';
    ALTER SUBSCRIPTION keycloak_longtime_sub DISABLE;
  ELSE
    RAISE NOTICE 'Subscription keycloak_longtime_sub does not exist, nothing to disable';
  END IF;
END;
$$;

DROP SUBSCRIPTION IF EXISTS keycloak_longtime_sub;

CREATE SUBSCRIPTION keycloak_longtime_sub
  CONNECTION 'host=pg-center port=5432 dbname=keycloak user=keycloak password=dev_center_pass'
  PUBLICATION keycloak_longtime_pub
  WITH (
    copy_data = true,
    create_slot = true,
    slot_name = 'keycloak_longtime_slot'
  );
