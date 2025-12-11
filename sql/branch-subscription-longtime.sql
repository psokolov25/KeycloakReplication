-- branch-subscription-longtime.sql
-- Безопасная настройка подписки на публикацию keycloak_longtime_pub.
-- ВАЖНО: DROP SUBSCRIPTION нельзя выполнять внутри транзакционного блока (DO/FUNCTION),
-- поэтому здесь используется комбинация DO для ALTER (с проверкой существования)
-- и отдельного DROP SUBSCRIPTION IF EXISTS.

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
