-- center-publication-longtime.sql
-- Динамическая публикация для «долгоиграющих» сущностей Keycloak
-- (исключаем таблицы сессий и подобные).

DO $$
DECLARE
  tbls              text;
  r                 record;
  total_tables      integer;
  candidate_tables  integer;
BEGIN
  SELECT count(*)
    INTO total_tables
    FROM information_schema.tables
   WHERE table_schema = 'public';

  SELECT count(*)
    INTO candidate_tables
    FROM information_schema.tables
   WHERE table_schema = 'public'
     AND table_name NOT LIKE 'user_session%%'
     AND table_name NOT LIKE 'client_session%%'
     AND table_name NOT LIKE 'offline_%%session%%'
     AND table_name NOT LIKE 'broker_%%session%%'
     AND table_name NOT LIKE 'session_%%';

  RAISE NOTICE 'Schema public: total tables = %, candidate tables for publication = %', total_tables, candidate_tables;

  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'keycloak_longtime_pub') THEN
    RAISE NOTICE 'Dropping existing publication keycloak_longtime_pub';
    DROP PUBLICATION keycloak_longtime_pub;
  END IF;

  SELECT string_agg(format('%I.%I', table_schema, table_name), ', ')
    INTO tbls
    FROM information_schema.tables
   WHERE table_schema = 'public'
     AND table_name NOT LIKE 'user_session%%'
     AND table_name NOT LIKE 'client_session%%'
     AND table_name NOT LIKE 'offline_%%session%%'
     AND table_name NOT LIKE 'broker_%%session%%'
     AND table_name NOT LIKE 'session_%%';

  IF tbls IS NULL THEN
    RAISE EXCEPTION 'No tables found to add to publication keycloak_longtime_pub. Check that Keycloak schema is created in schema public. (total_tables=%, candidate_tables=%)', total_tables, candidate_tables;
  END IF;

  RAISE NOTICE 'Configuring REPLICA IDENTITY FULL for publication tables...';

  FOR r IN
    SELECT table_schema, table_name
      FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name NOT LIKE 'user_session%%'
       AND table_name NOT LIKE 'client_session%%'
       AND table_name NOT LIKE 'offline_%%session%%'
       AND table_name NOT LIKE 'broker_%%session%%'
       AND table_name NOT LIKE 'session_%%'
  LOOP
    EXECUTE format('ALTER TABLE %I.%I REPLICA IDENTITY FULL;', r.table_schema, r.table_name);
  END LOOP;

  RAISE NOTICE 'Creating publication keycloak_longtime_pub...';
  EXECUTE format('CREATE PUBLICATION keycloak_longtime_pub FOR TABLE %s;', tbls);
END;
$$;
