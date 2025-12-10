-- =========================
-- 1) ТАБЛИЦЫ
-- =========================

DO $$ 
DECLARE
    r RECORD;
BEGIN
    -- Drop all tables
    FOR r IN (SELECT tablename, schemaname FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')) LOOP
        EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.schemaname) || '.' || quote_ident(r.tablename) || ' CASCADE';
    END LOOP;

    -- Drop all sequences (if not owned by tables)
    FOR r IN (SELECT sequencename, schemaname FROM pg_sequences WHERE schemaname NOT IN ('pg_catalog', 'information_schema')) LOOP
        EXECUTE 'DROP SEQUENCE IF EXISTS ' || quote_ident(r.schemaname) || '.' || quote_ident(r.sequencename);
    END LOOP;
END $$;

-- Удаляет ВСЕ функции во всех схемах текущей базы
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT format('%I.%I(%s)',
                      n.nspname,
                      p.proname,
                      pg_get_function_identity_arguments(p.oid)) AS func_sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
          AND n.nspname NOT LIKE 'pg_toast%'
    )
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;

/*
Created: 08.12.2025
Modified: 08.12.2025
Model: PhysicalModel
Database: PostgreSQL 12
*/

-- Create tables section -------------------------------------------------

-- Table Паспорт

CREATE TABLE "Паспорт"
(
  "ID паспорта" Serial NOT NULL,
  "Фамилия" Character varying(40) NOT NULL,
  "Имя" Character varying(40) NOT NULL,
  "Отчество" Character varying(40) NOT NULL,
  "Серия" Character varying(4) NOT NULL,
  "Номер" Character varying(6) NOT NULL,
  "Пол" Character varying(1) NOT NULL,
  "Место прописки" Character varying(30) NOT NULL,
  "Дата рождения" Date NOT NULL,
  "Место рождения" Character varying(30) NOT NULL,
  "Дата выдачи" Date NOT NULL,
  "Кем выдан" Character varying(50) NOT NULL,
  "Актуальность" Boolean NOT NULL,
  "ID пользователя" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Паспорт" ADD CONSTRAINT "Unique_Identifier16" PRIMARY KEY ("ID паспорта","ID пользователя")
;

-- Table Пользователь

CREATE TABLE "Пользователь"
(
  "ID пользователя" Serial NOT NULL,
  "Электронная почта" Character varying(40) NOT NULL,
  "Дата регистрации" Date NOT NULL,
  "Логин" Character varying(30) NOT NULL,
  "Пароль" Character varying(60) NOT NULL,
  "ID статуса верификации" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship4" ON "Пользователь" ("ID статуса верификации")
;

ALTER TABLE "Пользователь" ADD CONSTRAINT "Unique_Identifier9" PRIMARY KEY ("ID пользователя")
;

-- Table Статус верификации

CREATE TABLE "Статус верификации"
(
  "ID статуса верификации" Serial NOT NULL,
  "Статус верификации" Character varying(20) NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Статус верификации" ADD CONSTRAINT "Unique_Identifier4" PRIMARY KEY ("ID статуса верификации")
;

-- Table Персонал

CREATE TABLE "Персонал"
(
  "ID сотрудника" Serial NOT NULL,
  "Номер трудового договора" Character varying(40) NOT NULL,
  "Логин" Character varying(30) NOT NULL,
  "Пароль" Character varying(60) NOT NULL,
  "Уровень прав" Character varying(30) NOT NULL,
  "ID статуса трудоустройства" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship34" ON "Персонал" ("ID статуса трудоустройства")
;

ALTER TABLE "Персонал" ADD CONSTRAINT "Unique_Identifier10" PRIMARY KEY ("ID сотрудника")
;

-- Table Статус трудоустройства

CREATE TABLE "Статус трудоустройства"
(
  "ID статуса трудоустройства" Serial NOT NULL,
  "Статус трудоустройства" Character varying(120) NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Статус трудоустройства" ADD CONSTRAINT "Unique_Identifier7" PRIMARY KEY ("ID статуса трудоустройства")
;

-- Table Депозитарный счёт

CREATE TABLE "Депозитарный счёт"
(
  "ID депозитарного счёта" Serial NOT NULL,
  "Номер депозитарного договора" Character varying(120) NOT NULL,
  "Дата открытия" Date NOT NULL,
  "ID пользователя" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Депозитарный счёт" ADD CONSTRAINT "Unique_Identifier13" PRIMARY KEY ("ID депозитарного счёта","ID пользователя")
;

-- Table Баланс депозитарного счёта

CREATE TABLE "Баланс депозитарного счёта"
(
  "ID баланса депозитарного счёта" Serial NOT NULL,
  "Сумма" Numeric(12,2) NOT NULL,
  "ID депозитарного счёта" Integer NOT NULL,
  "ID пользователя" Integer NOT NULL,
  "ID ценной бумаги" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship17" ON "Баланс депозитарного счёта" ("ID ценной бумаги")
;

ALTER TABLE "Баланс депозитарного счёта" ADD CONSTRAINT "Unique_Identifier19" PRIMARY KEY ("ID баланса депозитарного счёта","ID депозитарного счёта","ID пользователя")
;

-- Table Список ценных бумаг

CREATE TABLE "Список ценных бумаг"
(
  "ID ценной бумаги" Serial NOT NULL,
  "Наименование" Character varying(120) NOT NULL,
  "Размер лота" Numeric(12,2) NOT NULL,
  "ISIN" Character varying(40) NOT NULL,
  "Выплата дивидендов" Boolean NOT NULL,
  "ID валюты" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship51" ON "Список ценных бумаг" ("ID валюты")
;

ALTER TABLE "Список ценных бумаг" ADD CONSTRAINT "Unique_Identifier5" PRIMARY KEY ("ID ценной бумаги")
;

-- Table История операций деп. счёта

CREATE TABLE "История операций деп. счёта"
(
  "ID операции деп. счёта" Serial NOT NULL,
  "Сумма операции" Numeric(12,2) NOT NULL,
  "Время" Timestamp(6) NOT NULL,
  "ID депозитарного счёта" Integer NOT NULL,
  "ID пользователя" Integer NOT NULL,
  "ID ценной бумаги" Integer NOT NULL,
  "ID сотрудника" Integer NOT NULL,
  "ID операции бр. счёта" Integer NOT NULL,
  "ID брокерского счёта" Integer NOT NULL,
  "ID типа операции деп. счёта" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship27" ON "История операций деп. счёта" ("ID ценной бумаги")
;

CREATE INDEX "IX_Relationship28" ON "История операций деп. счёта" ("ID сотрудника")
;

CREATE INDEX "IX_Relationship35" ON "История операций деп. счёта" ("ID типа операции деп. счёта")
;

ALTER TABLE "История операций деп. счёта" ADD CONSTRAINT "Unique_Identifier18" PRIMARY KEY ("ID операции деп. счёта","ID депозитарного счёта","ID пользователя","ID операции бр. счёта","ID брокерского счёта")
;

-- Table Тип операции депозитарного счёта

CREATE TABLE "Тип операции депозитарного счёта"
(
  "ID типа операции деп. счёта" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Тип операции депозитарного счёта" ADD CONSTRAINT "Unique_Identifier1" PRIMARY KEY ("ID типа операции деп. счёта")
;

-- Table Брокерский счёт

CREATE TABLE "Брокерский счёт"
(
  "ID брокерского счёта" Serial NOT NULL,
  "Баланс" Numeric(12,2) NOT NULL,
  "ИНН" Character varying(30) NOT NULL,
  "БИК" Character varying(30) NOT NULL,
  "ID банка" Integer NOT NULL,
  "ID валюты" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship22" ON "Брокерский счёт" ("ID банка")
;

CREATE INDEX "IX_Relationship25" ON "Брокерский счёт" ("ID валюты")
;

ALTER TABLE "Брокерский счёт" ADD CONSTRAINT "Unique_Identifier12" PRIMARY KEY ("ID брокерского счёта")
;

-- Table История операций бр. счёта

CREATE TABLE "История операций бр. счёта"
(
  "ID операции бр. счёта" Serial NOT NULL,
  "Сумма операции" Numeric(12,2) NOT NULL,
  "Время" Timestamp(6) NOT NULL,
  "ID брокерского счёта" Integer NOT NULL,
  "ID сотрудника" Integer NOT NULL,
  "ID типа операции бр. счёта" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship29" ON "История операций бр. счёта" ("ID сотрудника")
;

CREATE INDEX "IX_Relationship33" ON "История операций бр. счёта" ("ID типа операции бр. счёта")
;

ALTER TABLE "История операций бр. счёта" ADD CONSTRAINT "Unique_Identifier17" PRIMARY KEY ("ID операции бр. счёта","ID брокерского счёта")
;

-- Table Тип операции брокерского счёта

CREATE TABLE "Тип операции брокерского счёта"
(
  "ID типа операции бр. счёта" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Тип операции брокерского счёта" ADD CONSTRAINT "Unique_Identifier2" PRIMARY KEY ("ID типа операции бр. счёта")
;

-- Table Дивиденды

CREATE TABLE "Дивиденды"
(
  "ID дивиденда" Serial NOT NULL,
  "Дата" Date NOT NULL,
  "Сумма" Numeric(12,2) NOT NULL,
  "ID ценной бумаги" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Дивиденды" ADD CONSTRAINT "Unique_Identifier14" PRIMARY KEY ("ID дивиденда","ID ценной бумаги")
;

-- Table Список валют

CREATE TABLE "Список валют"
(
  "ID валюты" Serial NOT NULL,
  "Наименование валюты" Character varying(30) NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Список валют" ADD CONSTRAINT "Unique_Identifier6" PRIMARY KEY ("ID валюты")
;

-- Table Тип предложения

CREATE TABLE "Тип предложения"
(
  "ID типа предложения" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Тип предложения" ADD CONSTRAINT "Unique_Identifier3" PRIMARY KEY ("ID типа предложения")
;

-- Table Предложение

CREATE TABLE "Предложение"
(
  "ID предложения" Serial NOT NULL,
  "Сумма" Numeric(12,2) NOT NULL,
  "ID ценной бумаги" Integer NOT NULL,
  "ID пользователя" Integer NOT NULL,
  "ID типа предложения" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship20" ON "Предложение" ("ID ценной бумаги")
;

CREATE INDEX "IX_Relationship36" ON "Предложение" ("ID типа предложения")
;

ALTER TABLE "Предложение" ADD CONSTRAINT "Unique_Identifier11" PRIMARY KEY ("ID предложения","ID пользователя")
;

-- Table Банк

CREATE TABLE "Банк"
(
  "ID банка" Serial NOT NULL,
  "Наименование" Character varying(120) NOT NULL,
  "ИНН" Character varying(40) NOT NULL,
  "ОГРН" Character varying(40) NOT NULL,
  "БИК" Character varying(40) NOT NULL,
  "Срок действия лицензии" Date NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Банк" ADD CONSTRAINT "Unique_Identifier8" PRIMARY KEY ("ID банка")
;

-- Table История цены

CREATE TABLE "История цены"
(
  "ID зап. ист. цены" Serial NOT NULL,
  "Время" Timestamp(6) NOT NULL,
  "Цена открытия" Numeric(12,2) NOT NULL,
  "Цена закрытия" Numeric(12,2) NOT NULL,
  "Цена минимальная" Numeric(12,2) NOT NULL,
  "Цена максимальная" Numeric(12,2) NOT NULL,
  "ID ценной бумаги" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

CREATE INDEX "IX_Relationship50" ON "История цены" ("ID ценной бумаги")
;

ALTER TABLE "История цены" ADD CONSTRAINT "Unique_Identifier15" PRIMARY KEY ("ID зап. ист. цены")
;

CREATE TABLE currency_rates (
    id SERIAL PRIMARY KEY,
    "Код валюты" Character varying(30) NOT NULL,
    "Курс" NUMERIC(12,4) NOT NULL,
    "Время" Timestamp(6) NOT NULL DEFAULT NOW()
);

-- Create foreign keys (relationships) section -------------------------------------------------

ALTER TABLE "Пользователь"
  ADD CONSTRAINT "Relationship4"
    FOREIGN KEY ("ID статуса верификации")
    REFERENCES "Статус верификации" ("ID статуса верификации")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "Депозитарный счёт"
  ADD CONSTRAINT "Relationship13"
    FOREIGN KEY ("ID пользователя")
    REFERENCES "Пользователь" ("ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE
;

ALTER TABLE "Баланс депозитарного счёта"
  ADD CONSTRAINT "Relationship14"
    FOREIGN KEY ("ID депозитарного счёта", "ID пользователя")
    REFERENCES "Депозитарный счёт" ("ID депозитарного счёта", "ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE
;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship15"
    FOREIGN KEY ("ID депозитарного счёта", "ID пользователя")
    REFERENCES "Депозитарный счёт" ("ID депозитарного счёта", "ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE
;

ALTER TABLE "Баланс депозитарного счёта"
  ADD CONSTRAINT "Relationship17"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "Предложение"
  ADD CONSTRAINT "Relationship20"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "Брокерский счёт"
  ADD CONSTRAINT "Relationship22"
    FOREIGN KEY ("ID банка")
    REFERENCES "Банк" ("ID банка")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "История операций бр. счёта"
  ADD CONSTRAINT "Relationship23"
    FOREIGN KEY ("ID брокерского счёта")
    REFERENCES "Брокерский счёт" ("ID брокерского счёта")
      ON DELETE CASCADE
      ON UPDATE CASCADE
;

ALTER TABLE "Брокерский счёт"
  ADD CONSTRAINT "Relationship25"
    FOREIGN KEY ("ID валюты")
    REFERENCES "Список валют" ("ID валюты")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship27"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship28"
    FOREIGN KEY ("ID сотрудника")
    REFERENCES "Персонал" ("ID сотрудника")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "История операций бр. счёта"
  ADD CONSTRAINT "Relationship29"
    FOREIGN KEY ("ID сотрудника")
    REFERENCES "Персонал" ("ID сотрудника")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "Предложение"
  ADD CONSTRAINT "Relationship30"
    FOREIGN KEY ("ID пользователя")
    REFERENCES "Пользователь" ("ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE
;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship31"
    FOREIGN KEY ("ID операции бр. счёта", "ID брокерского счёта")
    REFERENCES "История операций бр. счёта" ("ID операции бр. счёта", "ID брокерского счёта")
      ON DELETE CASCADE
      ON UPDATE CASCADE
;

ALTER TABLE "История операций бр. счёта"
  ADD CONSTRAINT "Relationship33"
    FOREIGN KEY ("ID типа операции бр. счёта")
    REFERENCES "Тип операции брокерского счёта" ("ID типа операции бр. счёта")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "Персонал"
  ADD CONSTRAINT "Relationship34"
    FOREIGN KEY ("ID статуса трудоустройства")
    REFERENCES "Статус трудоустройства" ("ID статуса трудоустройства")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship35"
    FOREIGN KEY ("ID типа операции деп. счёта")
    REFERENCES "Тип операции депозитарного счёта" ("ID типа операции деп. счёта")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "Предложение"
  ADD CONSTRAINT "Relationship36"
    FOREIGN KEY ("ID типа предложения")
    REFERENCES "Тип предложения" ("ID типа предложения")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "Дивиденды"
  ADD CONSTRAINT "Relationship48"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE CASCADE
      ON UPDATE CASCADE
;

ALTER TABLE "Паспорт"
  ADD CONSTRAINT "Relationship49"
    FOREIGN KEY ("ID пользователя")
    REFERENCES "Пользователь" ("ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE
;

ALTER TABLE "История цены"
  ADD CONSTRAINT "Relationship50"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;

ALTER TABLE "Список ценных бумаг"
  ADD CONSTRAINT "Relationship51"
    FOREIGN KEY ("ID валюты")
    REFERENCES "Список валют" ("ID валюты")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT
;


INSERT INTO "Статус верификации"("ID статуса верификации", "Статус верификации")
VALUES
(1, 'Не подтверждён'),
(2, 'Подтверждён');

INSERT INTO "Статус трудоустройства"("ID статуса трудоустройства", "Статус трудоустройства")
VALUES
(1, 'Активен'),
(2, 'Уволен');

INSERT INTO "Список валют"("ID валюты", "Наименование валюты")
VALUES
(1, 'RUB'),
(2, 'USD');

-- 5. Банки
INSERT INTO "Банк"("ID банка", "Наименование", "ИНН", "ОГРН", "БИК", "Срок действия лицензии")
VALUES
(1, 'Сбербанк', '1234567890', '102030405060', '044525225', '2030-12-31');

-- 6. Ценные бумаги
INSERT INTO "Список ценных бумаг"("ID ценной бумаги", "Наименование", "Размер лота", "ISIN", "Выплата дивидендов", "ID валюты")
VALUES
(1, 'Газпром', 10, 'RU0007661625', TRUE, 1),
(2, 'Сбербанк', 5, 'RU0009029540', TRUE, 1);

-- 7. Типы операций депозитарного счёта
INSERT INTO "Тип операции депозитарного счёта"("ID типа операции деп. счёта", "Тип")
VALUES
(1, 'Покупка'),
(2, 'Продажа');

-- 8. Типы операций брокерского счёта
INSERT INTO "Тип операции брокерского счёта"("ID типа операции бр. счёта", "Тип")
VALUES
(1, 'Снятие'),
(2, 'Пополнение');

-- 9. Типы предложений
INSERT INTO "Тип предложения"("ID типа предложения", "Тип")
VALUES
(1, 'Покупка'),
(2, 'Продажа');

ALTER TABLE "Брокерский счёт"
    ADD COLUMN IF NOT EXISTS "ID пользователя" Integer;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        WHERE c.conname = 'Relationship22_user' AND t.relname = 'Брокерский счёт'
    ) THEN
        IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'Пользователь') THEN
            ALTER TABLE "Брокерский счёт"
            ADD CONSTRAINT "Relationship22_user"
            FOREIGN KEY ("ID пользователя")
            REFERENCES "Пользователь"("ID пользователя")
            ON DELETE CASCADE
            ON UPDATE CASCADE;
        END IF;
    END IF;
END$$;




-- =========================
-- 2) ФУНКЦИИ
-- =========================

-- 2.1 get_currency_rate: вернёт КУРС по ID валюты (курс в рублях за единицу валюты).
CREATE OR REPLACE FUNCTION get_currency_rate(p_currency_id INT)
RETURNS NUMERIC AS $$
DECLARE
    cur_name TEXT;
    rate NUMERIC := 1;
BEGIN
    -- (RUB) id = 1 -> rate = 1
    IF p_currency_id IS NULL THEN
        RETURN 1;
    END IF;
    SELECT "Наименование валюты" INTO cur_name FROM "Список валют" WHERE "ID валюты" = p_currency_id;
    IF cur_name IS NULL THEN
        RETURN 1;
    END IF;

    SELECT cr."Курс" INTO rate
    FROM currency_rates cr
    WHERE cr."Код валюты" = cur_name
    ORDER BY cr."Время" DESC
    LIMIT 1;

    RETURN COALESCE(rate, 1);
END;
$$ LANGUAGE plpgsql;


-- 2.2 convert_amount: конвертирует сумму из currency_from -> currency_to
CREATE OR REPLACE FUNCTION convert_amount(p_amount NUMERIC, p_from_currency INT, p_to_currency INT)
RETURNS NUMERIC AS $$
DECLARE
    rate_from NUMERIC;
    rate_to NUMERIC;
BEGIN
    IF p_amount IS NULL THEN
        RETURN 0;
    END IF;

    rate_from := get_currency_rate(p_from_currency);
    rate_to   := get_currency_rate(p_to_currency);   

    -- Если обе валюты имеют rate = 0 либо NULL:
    IF COALESCE(rate_from,0) = 0 OR COALESCE(rate_to,0) = 0 THEN
        RETURN 0;
    END IF;

    -- Сначала переводим сумму в RUB, затем в целевую валюту:
    RETURN (p_amount * rate_from) / rate_to;
END;
$$ LANGUAGE plpgsql;


-- 2.3 calc_depo_value: сумма по всем бумагам на депозитарном счёте, в валюте p_currency_id
CREATE OR REPLACE FUNCTION calc_depo_value(
    p_depo_id INT,
    p_user_id INT,
    p_currency_id INT
) RETURNS NUMERIC AS $$
DECLARE
    result NUMERIC := 0;
BEGIN
    SELECT SUM(
        b."Сумма" * 
        ( -- берём последнюю цену в валюте бумаги
            COALESCE(c."Цена закрытия",0)
        )
    ) INTO result
    FROM "Баланс депозитарного счёта" b
    JOIN "Список ценных бумаг" sb ON sb."ID ценной бумаги" = b."ID ценной бумаги"
    JOIN LATERAL (
         SELECT "Цена закрытия"
         FROM "История цены"
         WHERE "ID ценной бумаги" = b."ID ценной бумаги"
         ORDER BY "Время" DESC LIMIT 1
    ) c ON TRUE
    WHERE b."ID депозитарного счёта" = p_depo_id
      AND b."ID пользователя" = p_user_id;

    -- Если result NULL -> 0
    result := COALESCE(result,0);

    -- Цена в единицах валюты бумаги * количество лотов/шт. Переведём в целевую валюту:
    -- У валюты бумаги берем ID: sb."ID валюты"
    SELECT SUM(
        b."Сумма" * c."Цена закрытия" * get_currency_rate(sb."ID валюты") / get_currency_rate(p_currency_id)
    ) INTO result
    FROM "Баланс депозитарного счёта" b
    JOIN "Список ценных бумаг" sb ON sb."ID ценной бумаги" = b."ID ценной бумаги"
    JOIN LATERAL (
         SELECT "Цена закрытия"
         FROM "История цены"
         WHERE "ID ценной бумаги" = b."ID ценной бумаги"
         ORDER BY "Время" DESC LIMIT 1
    ) c ON TRUE
    WHERE b."ID депозитарного счёта" = p_depo_id
      AND b."ID пользователя" = p_user_id;

    RETURN COALESCE(result,0);
END;
$$ LANGUAGE plpgsql;


-- 2.4 calc_total_account_value: суммарное значение всех депозитарных + брокерских счетов в валюте p_currency_id
CREATE OR REPLACE FUNCTION calc_total_account_value(
    p_user_id INT,
    p_currency_id INT      -- Валюта результата
) RETURNS NUMERIC AS $$
DECLARE
    total NUMERIC := 0;
    depo RECORD;
    bs_sum NUMERIC := 0;
BEGIN
    -- Сумма по всем депозитарным счетам
    FOR depo IN 
        SELECT "ID депозитарного счёта" AS id
        FROM "Депозитарный счёт"
        WHERE "ID пользователя" = p_user_id
    LOOP
        total := total + calc_depo_value(depo.id, p_user_id, p_currency_id);
    END LOOP;

    -- Добавляем брокерские счета: суммируем балансы и конвертируем в p_currency_id
    SELECT COALESCE(SUM(convert_amount(bs."Баланс", bs."ID валюты", p_currency_id)),0)
    INTO bs_sum
    FROM "Брокерский счёт" bs
    WHERE bs."ID пользователя" = p_user_id;

    total := total + COALESCE(bs_sum,0);

    RETURN COALESCE(total,0);
END;
$$ LANGUAGE plpgsql;


-- 2.5 calc_offer_value: (если нет цены — 0)
CREATE OR REPLACE FUNCTION calc_offer_value(
    p_offer_id INT,
    p_user_id INT
) RETURNS NUMERIC AS $$
DECLARE
    paper_id INT;
    qty NUMERIC := 0;
    price NUMERIC := 0;
BEGIN
    SELECT "ID ценной бумаги", "Сумма"
    INTO paper_id, qty
    FROM "Предложение"
    WHERE "ID предложения" = p_offer_id
      AND "ID пользователя" = p_user_id;

    IF paper_id IS NULL THEN
        RETURN 0;
    END IF;

    SELECT "Цена закрытия"
    INTO price
    FROM "История цены"
    WHERE "ID ценной бумаги" = paper_id
    ORDER BY "Время" DESC
    LIMIT 1;

    RETURN COALESCE(qty,0) * COALESCE(price,0);
END;
$$ LANGUAGE plpgsql;


-- 2.6 calc_depo_growth: разница текущей стоимости и стоимости N времени назад (p_interval Postgre interval text '7 days')
CREATE OR REPLACE FUNCTION calc_depo_growth(
    p_depo_id INT,
    p_user_id INT,
    p_interval TEXT
) RETURNS NUMERIC AS $$
DECLARE
    current_value NUMERIC := 0;
    past_value NUMERIC := 0;
BEGIN
    current_value := calc_depo_value(p_depo_id, p_user_id, 1); -- результат в RUB (1 = RUB)
    SELECT 
        SUM(b."Сумма" * c."Цена закрытия")
    INTO past_value
    FROM "Баланс депозитарного счёта" b
    JOIN LATERAL (
        SELECT "Цена закрытия"
        FROM "История цены"
        WHERE "ID ценной бумаги" = b."ID ценной бумаги"
          AND "Время" <= NOW() - p_interval::interval
        ORDER BY "Время" DESC
        LIMIT 1
    ) c ON TRUE
    WHERE b."ID депозитарного счёта" = p_depo_id
      AND b."ID пользователя" = p_user_id;

    RETURN COALESCE(current_value,0) - COALESCE(past_value,0);
END;
$$ LANGUAGE plpgsql;


-- 2.7 calc_stock_growth: рост цены акции за день
CREATE OR REPLACE FUNCTION calc_stock_growth(
    p_paper_id INT
) RETURNS NUMERIC AS $$
DECLARE
    today_price NUMERIC := 0;
    yesterday_price NUMERIC := 0;
BEGIN
    SELECT "Цена закрытия"
    INTO today_price
    FROM "История цены"
    WHERE "ID ценной бумаги" = p_paper_id
    ORDER BY "Время" DESC
    LIMIT 1;

    SELECT "Цена закрытия"
    INTO yesterday_price
    FROM "История цены"
    WHERE "ID ценной бумаги" = p_paper_id
      AND "Время" < NOW() - INTERVAL '1 day'
    ORDER BY "Время" DESC LIMIT 1;

    RETURN COALESCE(today_price,0) - COALESCE(yesterday_price,0);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION distribute_dividends(div_id INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    dividend RECORD;
    owner RECORD;
    br_op_id INT;
BEGIN
    -- Получаем информацию о дивиденде
    SELECT *
    INTO dividend
    FROM "Дивиденды"
    WHERE "ID дивиденда" = div_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Дивиденд с ID % не найден', div_id;
        RETURN;
    END IF;

    -- Для всех владельцев ценной бумаги начисляем дивиденды
    FOR owner IN
        SELECT 
            bds."ID баланса депозитарного счёта",
            bds."ID депозитарного счёта",
            bds."ID пользователя",
            bds."ID ценной бумаги",
            bds."Сумма" AS amount,
            dep."ID брокерского счёта"
        FROM "Баланс депозитарного счёта" bds
        JOIN "Депозитарный счёт" dep 
             ON dep."ID депозитарного счёта" = bds."ID депозитарного счёта"
        WHERE bds."ID ценной бумаги" = dividend."ID ценной бумаги"
    LOOP
        -- Создаём запись в История операций бр. счёта
        INSERT INTO "История операций бр. счёта"(
            "Сумма операции",
            "Время",
            "ID брокерского счёта",
            "ID сотрудника",
            "ID типа операции бр. счёта"
        ) VALUES (
            owner.amount * dividend."Сумма",  -- начисление дивиденда
            NOW(),
            owner."ID брокерского счёта",
            1,  -- сотрудник (пример)
            2   -- 2 = Пополнение
        )
        RETURNING "ID операции бр. счёта" INTO br_op_id;

        -- Создаём запись в История операций деп. счёта
        INSERT INTO "История операций деп. счёта"(
            "Сумма операции",
            "Время",
            "ID депозитарного счёта",
            "ID пользователя",
            "ID ценной бумаги",
            "ID сотрудника",
            "ID операции бр. счёта",
            "ID брокерского счёта",
            "ID типа операции деп. счёта"
        ) VALUES (
            owner.amount * dividend."Сумма",
            NOW(),
            owner."ID депозитарного счёта",
            owner."ID пользователя",
            owner."ID ценной бумаги",
            1,          -- сотрудник
            br_op_id,   -- связь с брокерской операцией
            owner."ID брокерского счёта",
            1           -- 1 = Покупка/Начисление
        );
    END LOOP;
END;
$$;



-- =========================
-- 3) ТЕСТОВЫЕ ДАННЫЕ
-- =========================

DO $$
DECLARE
    uid INT;
    depo_id INT;
    broker_id INT;
    bal_id INT;
    offer_id INT;
    div_id INT;
    broker_op_id INT;
BEGIN
    --------------------------------------------------------
    -- 1. СОЗДАЕМ ПОЛЬЗОВАТЕЛЯ
    --------------------------------------------------------
    INSERT INTO "Пользователь"
    ("Электронная почта","Дата регистрации","Логин","Пароль","ID статуса верификации")
    VALUES ('u1@test.com', NOW(), 'user1','pass', 1)
    RETURNING "ID пользователя" INTO uid;

    --------------------------------------------------------
    -- 2. СОЗДАЕМ ДЕПОЗИТАРНЫЙ СЧЁТ
    --------------------------------------------------------
    INSERT INTO "Депозитарный счёт"
    ("Номер депозитарного договора","Дата открытия","ID пользователя")
    VALUES ('D100', NOW(), uid)
    RETURNING "ID депозитарного счёта" INTO depo_id;

    --------------------------------------------------------
    -- 3. КУРСЫ ВАЛЮТ
    --------------------------------------------------------
    INSERT INTO currency_rates("Код валюты", "Курс") VALUES ('RUB', 1);
    INSERT INTO currency_rates("Код валюты", "Курс") VALUES ('USD', 90.50);

    --------------------------------------------------------
    -- 4. ЦЕНЫ НА ЦЕННУЮ БУМАГУ
    --------------------------------------------------------
    INSERT INTO "История цены"
    ("Время","Цена открытия","Цена закрытия","Цена минимальная","Цена максимальная","ID ценной бумаги")
    VALUES
    (NOW() - INTERVAL '1 day', 180, 185, 170, 190, 1),
    (NOW(),                    200, 210, 195, 220, 1);


INSERT INTO "История цены"
    ("Время","Цена открытия","Цена закрытия","Цена минимальная","Цена максимальная","ID ценной бумаги")
    VALUES
    (NOW() - INTERVAL '1 day', 180, 185, 170, 190, 2),
    (NOW(),                    200, 400, 195, 220, 2);
    --------------------------------------------------------
    -- 5. БАЛАНС ДЕПОЗИТАРНОГО СЧЁТА
    --------------------------------------------------------
    INSERT INTO "Баланс депозитарного счёта"
    ("Сумма","ID депозитарного счёта","ID пользователя","ID ценной бумаги")
    VALUES (10, depo_id, uid, 1)
    RETURNING "ID баланса депозитарного счёта" INTO bal_id;
INSERT INTO "Баланс депозитарного счёта"
    ("Сумма","ID депозитарного счёта","ID пользователя","ID ценной бумаги")
    VALUES (15, depo_id, uid, 2)
    RETURNING "ID баланса депозитарного счёта" INTO bal_id;
    --------------------------------------------------------
    -- 6. СОЗДАЁМ БРОКЕРСКИЙ СЧЁТ
    --------------------------------------------------------
    INSERT INTO "Брокерский счёт"
    ("Баланс","ИНН","БИК","ID банка","ID валюты")
    VALUES (10000, '111','222', 1, 1)
    RETURNING "ID брокерского счёта" INTO broker_id;

    --------------------------------------------------------
    -- 7. СОЗДАЕМ ПРЕДЛОЖЕНИЕ
    --------------------------------------------------------
    INSERT INTO "Предложение"
    ("Сумма","ID ценной бумаги","ID пользователя","ID типа предложения")
    VALUES (5, 1, uid, 1)
    RETURNING "ID предложения" INTO offer_id;


END $$;

------------------------------------------------------------
-- 4. ВЫВОД РЕЗУЛЬТАТОВ ТЕСТОВ
------------------------------------------------------------

SELECT 'get_currency_rate_RUB', get_currency_rate(1);
SELECT 'get_currency_rate_USD', get_currency_rate(2);
SELECT 'calc_depo_value',        calc_depo_value(1, 1, 2);
select * from "Баланс депозитарного счёта";
SELECT 'calc_total_account_value', calc_total_account_value(1, 1);
--SELECT 'calc_offer_value',       calc_offer_value(1, 1);
--SELECT 'calc_depo_growth',       calc_depo_growth(1, 1, '1 day');
--SELECT 'calc_stock_growth',      calc_stock_growth(1);