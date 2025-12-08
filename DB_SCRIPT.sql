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
  "ID паспорта" Integer NOT NULL,
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
  "ID пользователя" Integer NOT NULL,
  "Электронная почта" Character varying(40) NOT NULL,
  "Дата регистрации" Character varying(40) NOT NULL,
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
  "ID статуса верификации" Integer NOT NULL,
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
  "ID сотрудника" Integer NOT NULL,
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
  "ID статуса трудоустройства" Integer NOT NULL,
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
  "ID депозитарного счёта" Integer NOT NULL,
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
  "ID баланса депозитарного счёта" Integer NOT NULL,
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
  "ID ценной бумаги" Integer NOT NULL,
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
  "ID операции деп. счёта" Integer NOT NULL,
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
  "ID типа операции деп. счёта" Integer NOT NULL,
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
  "ID брокерского счёта" Integer NOT NULL,
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
  "ID операции бр. счёта" Integer NOT NULL,
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
  "ID типа операции бр. счёта" Integer NOT NULL,
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
  "ID дивидинда" Integer NOT NULL,
  "Дата" Date NOT NULL,
  "Сумма" Numeric(12,2) NOT NULL,
  "ID ценной бумаги" Integer NOT NULL
)
WITH (
  autovacuum_enabled=true)
;

ALTER TABLE "Дивиденды" ADD CONSTRAINT "Unique_Identifier14" PRIMARY KEY ("ID дивидинда","ID ценной бумаги")
;

-- Table Список валют

CREATE TABLE "Список валют"
(
  "ID валюты" Integer NOT NULL,
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
  "ID типа предложения" Integer NOT NULL,
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
  "ID предложения" Integer NOT NULL,
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
  "ID банка" Integer NOT NULL,
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
  "ID зап. ист. цены" Integer NOT NULL,
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
    "Время" TIMESTAMP(6) NOT NULL DEFAULT NOW()
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



CREATE OR REPLACE FUNCTION calc_total_account_value(
    p_user_id INT,
    p_currency_id INT      -- Валюта результата (1 = RUB, 2 = USD)
) RETURNS NUMERIC AS $$
DECLARE
    total NUMERIC := 0;
    depo RECORD;
    cur_rate NUMERIC := get_currency_rate(p_currency_id);  
BEGIN
    ----------------------------------------------------------------
    -- 1. Суммарная стоимость ВСЕХ депозитарных счетов пользователя
    ----------------------------------------------------------------
    FOR depo IN 
        SELECT "ID депозитарного счёта"
        FROM "Депозитарный счёт"
        WHERE "ID пользователя" = p_user_id
    LOOP
        total := total + calc_depo_value(depo."ID депозитарного счёта", p_user_id, p_currency_id);
    END LOOP;


    ----------------------------------------------------------------
    -- 2. Добавляем брокерские счета пользователя
    --    (учитываем валюту каждого счёта)
    ----------------------------------------------------------------
    total := total +
        COALESCE((
            SELECT SUM(
                       bs."Баланс" /
                       CASE 
                           WHEN bs."ID валюты" = p_currency_id THEN 1
                           ELSE get_currency_rate(bs."ID валюты")
                       END
                   )
            FROM "Брокерский счёт" bs
            WHERE bs."ID пользователя" = p_user_id
        ), 0);

    RETURN total;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_currency_rate(p_currency_id INT)
RETURNS NUMERIC AS $$
DECLARE
    rate NUMERIC := 1;
BEGIN
    -- 1 = RUB, 2 = USD (как в вашей таблице)
    IF p_currency_id = 1 THEN
        RETURN 1;
    END IF;

    SELECT cr.rate INTO rate
    FROM currency_rates cr
    WHERE cr.currency_code = 'USD'
    ORDER BY updated DESC
    LIMIT 1;

    RETURN COALESCE(rate, 1);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION calc_offer_value(
    p_offer_id INT,
    p_user_id INT
) RETURNS NUMERIC AS $$
DECLARE
    paper_id INT;
    qty NUMERIC;
    price NUMERIC;
BEGIN
    SELECT "ID ценной бумаги", "Сумма"
    INTO paper_id, qty
    FROM "Предложение"
    WHERE "ID предложения" = p_offer_id
      AND "ID пользователя" = p_user_id;

    SELECT "Цена закрытия"
    INTO price
    FROM "История цены"
    WHERE "ID ценной бумаги" = paper_id
    ORDER BY "Время" DESC
    LIMIT 1;

    RETURN qty * price;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calc_depo_value(
    p_depo_id INT,
    p_user_id INT,
    p_currency_id INT
) RETURNS NUMERIC AS $$
DECLARE
    result NUMERIC := 0;
    currency_rate NUMERIC := 1;
BEGIN
    currency_rate := get_currency_rate(p_currency_id);

    SELECT 
        SUM(b."Сумма" * c."Цена закрытия" / 
               CASE WHEN sb."ID валюты" = p_currency_id 
                    THEN 1 
                    ELSE get_currency_rate(sb."ID валюты") END 
        )
    INTO result
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

    RETURN COALESCE(result, 0);
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION calc_depo_growth(
    p_depo_id INT,
    p_user_id INT,
    p_interval TEXT
) RETURNS NUMERIC AS $$
DECLARE
    current_value NUMERIC;
    past_value NUMERIC := 0;
BEGIN
    -- Текущая стоимость
    SELECT calc_depo_value(p_depo_id, p_user_id, 1)
    INTO current_value;

    -- Стоимость N времени назад
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

    RETURN current_value - COALESCE(past_value, 0);
END;
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION calc_stock_growth(
    p_paper_id INT
) RETURNS NUMERIC AS $$
DECLARE
    today_price NUMERIC;
    yesterday_price NUMERIC;
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

    RETURN today_price - COALESCE(yesterday_price, today_price);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION distribute_dividends(
    p_dividend_id INT
) RETURNS VOID AS $$
DECLARE
    dividend RECORD;
    owner RECORD;
    new_op_id INT;
BEGIN
    SELECT * INTO dividend
    FROM "Дивиденды"
    WHERE "ID дивидинда" = p_dividend_id;

    FOR owner IN
        SELECT b.*
        FROM "Баланс депозитарного счёта" b
        WHERE b."ID ценной бумаги" = dividend."ID ценной бумаги"
    LOOP
        -- Начислить дивиденды
        UPDATE "Баланс депозитарного счёта"
        SET "Сумма" = "Сумма" + dividend."Сумма"
        WHERE "ID баланса депозитарного счёта" = owner."ID баланса депозитарного счёта";

        -- ID операции деп. счёта
        SELECT COALESCE(MAX("ID операции деп. счёта"), 0) + 1
        INTO new_op_id
        FROM "История операций деп. счёта";

        -- Записать в историю
        INSERT INTO "История операций деп. счёта"(
            "ID операции деп. счёта",
            "Сумма операции",
            "Время",
            "ID депозитарного счёта",
            "ID пользователя",
            "ID ценной бумаги",
            "ID сотрудника",
            "ID операции бр. счёта",
            "ID брокерского счёта",
            "ID типа операции деп. счёта"
        )
        VALUES(
            new_op_id,
            dividend."Сумма",
            NOW(),
            owner."ID депозитарного счёта",
            owner."ID пользователя",
            owner."ID ценной бумаги",
            1,   -- сотрудник (можете заменить)
            0,
            0,
            1    -- тип: покупка (или "начисление" если добавите новый тип)
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;


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
