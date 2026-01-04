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

DO $$
DECLARE
    r RECORD;
BEGIN
    -- Удаляем все функции и процедуры во всех пользовательских схемах
    FOR r IN (
        SELECT format(
                   '%I.%I(%s)',
                   n.nspname,
                   p.proname,
                   pg_get_function_identity_arguments(p.oid)
               ) AS routine_sig,
               CASE WHEN p.prokind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END AS routine_type
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
          AND n.nspname NOT LIKE 'pg_toast%'
    )
    LOOP
        IF r.routine_type = 'PROCEDURE' THEN
            EXECUTE 'DROP PROCEDURE IF EXISTS ' || r.routine_sig || ' CASCADE';
        ELSE
            EXECUTE 'DROP FUNCTION IF EXISTS ' || r.routine_sig || ' CASCADE';
        END IF;
    END LOOP;
END $$;

/*
Created: 08.12.2025
Modified: 08.12.2025
Model: PhysicalModel
Database: PostgreSQL 12
*/

CREATE OR REPLACE FUNCTION prevent_negative_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    amount_value NUMERIC(12,2);
    account_id   TEXT := 'неизвестно';
BEGIN
    -- Определяем значение суммы (может называться "Баланс" или "Сумма")
    IF TG_TABLE_NAME = 'Брокерский счёт' THEN
        amount_value := NEW."Баланс";
        account_id   := COALESCE(NEW."ID брокерского счёта"::text, 'новый');
    ELSIF TG_TABLE_NAME = 'Баланс депозитарного счёта' THEN
        amount_value := NEW."Сумма";
        account_id   := COALESCE(NEW."ID баланса депозитарного счёта"::text, 'новый');
    ELSE
        RAISE EXCEPTION 'Триггер вызван на неподдерживаемой таблице %', TG_TABLE_NAME;
    END IF;

    IF amount_value < 0 THEN
        RAISE EXCEPTION 'Сумма не может быть отрицательной! Попытка установить значение % (таблица: %, ID: %)'
            , amount_value
            , TG_TABLE_NAME
            , account_id;
    END IF;

    RETURN NEW;
END;
$$;

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
  "Электронная почта" Character varying(40) NOT NULL UNIQUE,
  "Дата регистрации" Date NOT NULL,
  "Логин" Character varying(30) NOT NULL UNIQUE,
  "Пароль" Character varying(60) NOT NULL,
  "ID статуса верификации" Integer NOT NULL,
  "ID статуса блокировки" Integer NOT NULL
)
WITH (autovacuum_enabled=true);

CREATE INDEX "IX_Relationship4" ON "Пользователь" ("ID статуса верификации");
ALTER TABLE "Пользователь" ADD CONSTRAINT "Unique_Identifier9" PRIMARY KEY ("ID пользователя");

-- Table Статус верификации

CREATE TABLE "Статус верификации"
(
  "ID статуса верификации" Serial NOT NULL,
  "Статус верификации" Character varying(20) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Статус верификации" ADD CONSTRAINT "Unique_Identifier4" PRIMARY KEY ("ID статуса верификации");

CREATE TABLE "Персонал"
(
  "ID сотрудника" Serial NOT NULL,
  "Номер трудового договора" Character varying(40) NOT NULL UNIQUE,
  "Логин" Character varying(30) NOT NULL UNIQUE,
  "Пароль" Character varying(60) NOT NULL,
  "ID статуса трудоустройства" Integer NOT NULL,
  "ID уровня прав" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship34" ON "Персонал" ("ID статуса трудоустройства");
ALTER TABLE "Персонал" ADD CONSTRAINT "Unique_Identifier10" PRIMARY KEY ("ID сотрудника");


CREATE TABLE "Статус трудоустройства"
(
  "ID статуса трудоустройства" Serial NOT NULL,
  "Статус трудоустройства" Character varying(120) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Статус трудоустройства" ADD CONSTRAINT "Unique_Identifier7" PRIMARY KEY ("ID статуса трудоустройства");

-- Table Депозитарный счёт

CREATE TABLE "Депозитарный счёт"
(
  "ID депозитарного счёта" Serial NOT NULL,
  "Номер депозитарного договора" Character varying(120) NOT NULL,
  "Дата открытия" Date NOT NULL,
  "ID пользователя" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Депозитарный счёт" ADD CONSTRAINT "Unique_Identifier13" PRIMARY KEY ("ID депозитарного счёта","ID пользователя");
ALTER TABLE "Депозитарный счёт" ADD CONSTRAINT unique_user_deposit_account UNIQUE ("ID пользователя");


CREATE TABLE "Баланс депозитарного счёта"
(
  "ID баланса депозитарного счёта" Serial NOT NULL,
  "Сумма" Numeric(12,2) NOT NULL,
  "ID депозитарного счёта" Integer NOT NULL,
  "ID пользователя" Integer NOT NULL,
  "ID ценной бумаги" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship17" ON "Баланс депозитарного счёта" ("ID ценной бумаги");
ALTER TABLE "Баланс депозитарного счёта" ADD CONSTRAINT "Unique_Identifier19" PRIMARY KEY ("ID баланса депозитарного счёта","ID депозитарного счёта","ID пользователя");


CREATE TRIGGER trg_prevent_negative_depo_balance
    BEFORE INSERT OR UPDATE OF "Сумма"
    ON public."Баланс депозитарного счёта"
    FOR EACH ROW
    EXECUTE FUNCTION prevent_negative_balance();

-- Table Список ценных бумаг

CREATE TABLE "Список ценных бумаг"
(
  "ID ценной бумаги" Serial NOT NULL,
  "Наименование" Character varying(120) NOT NULL UNIQUE,
  "Размер лота" Numeric(12,2) NOT NULL,
  "ISIN" Character varying(40) NOT NULL UNIQUE,
  "Выплата дивидендов" Boolean NOT NULL,
  "ID валюты" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship51" ON "Список ценных бумаг" ("ID валюты");
ALTER TABLE "Список ценных бумаг" ADD CONSTRAINT "Unique_Identifier5" PRIMARY KEY ("ID ценной бумаги");

CREATE OR REPLACE FUNCTION public.trg_validate_security_before_insert()
RETURNS TRIGGER AS
$BODY$
BEGIN
    -- Проверка: размер лота > 0
    IF NEW."Размер лота" <= 0 THEN
        RAISE EXCEPTION 'Размер лота должен быть строго больше нуля (получено: %)', NEW."Размер лота";
    END IF;

    -- Проверка: валюта существует
    PERFORM 1 FROM public."Список валют" WHERE "ID валюты" = NEW."ID валюты";
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Валюта с ID % не найдена', NEW."ID валюты";
    END IF;

    -- Проверка уникальности ISIN
    PERFORM 1 FROM public."Список ценных бумаг" WHERE "ISIN" = NEW."ISIN" AND "ID ценной бумаги" IS DISTINCT FROM NEW."ID ценной бумаги";
    IF FOUND THEN
        RAISE EXCEPTION 'Ценная бумага с ISIN % уже существует', NEW."ISIN";
    END IF;

    -- Проверка уникальности тикера (Наименование)
    PERFORM 1 FROM public."Список ценных бумаг" WHERE "Наименование" = NEW."Наименование" AND "ID ценной бумаги" IS DISTINCT FROM NEW."ID ценной бумаги";
    IF FOUND THEN
        RAISE EXCEPTION 'Ценная бумага с тикером % уже существует', NEW."Наименование";
    END IF;

    RETURN NEW;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;

CREATE TRIGGER trg_validate_security_before_insert_or_update
    BEFORE INSERT OR UPDATE ON public."Список ценных бумаг"
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_validate_security_before_insert();

-- Table История операций деп. счёта

CREATE TABLE "История операций деп. счёта" (
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
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship27" ON "История операций деп. счёта" ("ID ценной бумаги");
CREATE INDEX "IX_Relationship28" ON "История операций деп. счёта" ("ID сотрудника");
CREATE INDEX "IX_Relationship35" ON "История операций деп. счёта" ("ID типа операции деп. счёта");
ALTER TABLE "История операций деп. счёта" ADD CONSTRAINT "Unique_Identifier18" PRIMARY KEY ("ID операции деп. счёта","ID депозитарного счёта","ID пользователя","ID операции бр. счёта","ID брокерского счёта");

CREATE TABLE "Тип операции депозитарного счёта" (
  "ID типа операции деп. счёта" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Тип операции депозитарного счёта" ADD CONSTRAINT "Unique_Identifier1" PRIMARY KEY ("ID типа операции деп. счёта");

CREATE TABLE "Брокерский счёт"
(
  "ID брокерского счёта" Serial NOT NULL,
  "Баланс" Numeric(12,2) NOT NULL,
  "ИНН" Character varying(30) NOT NULL,
  "БИК" Character varying(30) NOT NULL,
  "ID банка" Integer NOT NULL,
  "ID пользователя" Integer NOT NULL,
  "ID валюты" Integer NOT NULL,
  "Статус архивации" Boolean NOT NULL -- todo: delete this column
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship22" ON "Брокерский счёт" ("ID банка");
CREATE INDEX "IX_Relationship25" ON "Брокерский счёт" ("ID валюты");
CREATE INDEX "IX_Relationship52" ON "Брокерский счёт" ("ID пользователя");
ALTER TABLE "Брокерский счёт" ADD CONSTRAINT "Unique_Identifier12" PRIMARY KEY ("ID брокерского счёта");

CREATE TRIGGER trg_prevent_negative_balance
    BEFORE INSERT OR UPDATE OF "Баланс"
    ON public."Брокерский счёт"
    FOR EACH ROW
    EXECUTE FUNCTION prevent_negative_balance();


CREATE OR REPLACE FUNCTION public.trg_validate_archive_brokerage_account()
RETURNS TRIGGER AS
$BODY$
BEGIN
    IF OLD."Статус архивации" = TRUE AND NEW."Статус архивации" = FALSE THEN
        RAISE EXCEPTION 'Нельзя разархивировать брокерский счёт, который уже был архивирован (id: %)', OLD."ID брокерского счёта"
        USING ERRCODE = 'check_violation';
    END IF;

    IF NEW."Статус архивации" = TRUE AND OLD."Статус архивации" = FALSE THEN
        IF NEW."Баланс" > 0 THEN
            RAISE EXCEPTION 'Нельзя архивировать брокерский счёт с положительным балансом (текущий баланс: %)', NEW."Баланс"
                  USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;

CREATE TRIGGER _trg_validate_archive_brokerage_account
    BEFORE UPDATE OF "Статус архивации"
    ON public."Брокерский счёт"
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_validate_archive_brokerage_account();


CREATE TABLE "История операций бр. счёта"
(
  "ID операции бр. счёта" Serial NOT NULL UNIQUE,
  "Сумма операции" Numeric(12,2) NOT NULL,
  "Время" Timestamp(6) NOT NULL,
  "ID брокерского счёта" Integer NOT NULL,
  "ID сотрудника" Integer NOT NULL,
  "ID типа операции бр. счёта" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship29" ON "История операций бр. счёта" ("ID сотрудника");
CREATE INDEX "IX_Relationship33" ON "История операций бр. счёта" ("ID типа операции бр. счёта");
ALTER TABLE "История операций бр. счёта" ADD CONSTRAINT "Unique_Identifier17" PRIMARY KEY ("ID операции бр. счёта","ID брокерского счёта");

-- Table Тип операции брокерского счёта

CREATE TABLE "Тип операции брокерского счёта"
(
  "ID типа операции бр. счёта" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Тип операции брокерского счёта" ADD CONSTRAINT "Unique_Identifier2" PRIMARY KEY ("ID типа операции бр. счёта");

-- Table Дивиденды

CREATE TABLE "Дивиденды"
(
  "ID дивиденда" Serial NOT NULL,
  "Дата" Date NOT NULL,
  "Сумма" Numeric(12,2) NOT NULL,
  "ID ценной бумаги" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Дивиденды" ADD CONSTRAINT "Unique_Identifier14" PRIMARY KEY ("ID дивиденда","ID ценной бумаги");

-- Table Список валют

CREATE TABLE "Список валют"
(
  "ID валюты" Serial NOT NULL,
  "Код" Char(3) NOT NULL,
  "Символ" Character varying(10) NOT NULL,
  "Статус архивации" BOOLEAN NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Список валют" ADD CONSTRAINT "Unique_Identifier6" PRIMARY KEY ("ID валюты");

INSERT INTO "Список валют"("Код", "Символ", "Статус архивации")
VALUES
('RUB', '₽', false);

CREATE OR REPLACE FUNCTION validate_currency_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Запрещаем УДАЛЕНИЕ записи с ID = 1
    IF TG_OP = 'DELETE' AND OLD."ID валюты" = 1 THEN
        RAISE EXCEPTION 'Удаление базовой валюты с ID = 1 запрещено'
              USING ERRCODE = 'check_violation';
    END IF;

    -- Запрещаем любое изменение (UPDATE) записи с ID = 1
    -- (это обычно базовая валюта, например RUB, которую нельзя менять)
    IF TG_OP = 'UPDATE' AND OLD."ID валюты" = 1 THEN
        RAISE EXCEPTION 'Изменение базовой валюты с ID = 1 запрещено'
              USING ERRCODE = 'check_violation';
    END IF;

    -- Запрещаем изменение ID валюты для любой записи
    IF TG_OP = 'UPDATE' AND OLD."ID валюты" != NEW."ID валюты" THEN
        RAISE EXCEPTION 'Изменение поля "ID валюты" запрещено'
              USING ERRCODE = 'check_violation';
    END IF;

    -- Запрещаем создание записи с ID = 1 (если вдруг кто-то попробует)
    IF TG_OP = 'INSERT' AND NEW."ID валюты" = 1 THEN
        RAISE EXCEPTION 'Создание записи с ID валюты = 1 запрещено. Этот ID зарезервирован для системной валюты'
              USING ERRCODE = 'check_violation';
    END IF;

    -- Приводим код к верхнему регистру
    NEW."Код" := UPPER(TRIM(NEW."Код"));
    IF char_length(NEW."Код") != 3 THEN
        RAISE EXCEPTION 'Поле "Код" должно содержать ровно 3 символа. Текущая длина: %', char_length(NEW."Код");
    END IF;

    IF NEW."Код" !~ '^[A-Z]{3}$' THEN
        RAISE EXCEPTION 'Поле "Код" должно состоять из 3 латинских букв в верхнем регистре (A-Z). Полученное значение: "%"', NEW."Код";
    END IF;

    IF NEW."Символ" ~ '\s' THEN
        RAISE EXCEPTION 'Поле "Символ" не должно содержать пробелов, табуляций и других whitespace-символов';
    END IF;

    -- Проверка уникальности "Код" среди неархивированных валют
    IF EXISTS (
        SELECT 1
        FROM "Список валют" c
        WHERE c."Код" = NEW."Код"
          AND c."Статус архивации" = false
          AND c."ID валюты" IS DISTINCT FROM NEW."ID валюты"
    ) THEN
        RAISE EXCEPTION 'Код валюты "%" уже существует среди активных (неархивированных) валют', NEW."Код"
              USING ERRCODE = 'unique_violation';
    END IF;

    -- Проверка уникальности "Символ" среди неархивированных валют
    IF EXISTS (
        SELECT 1
        FROM "Список валют" c
        WHERE c."Символ" = NEW."Символ"
          AND c."Статус архивации" = false
          AND c."ID валюты" IS DISTINCT FROM NEW."ID валюты"
    ) THEN
        RAISE EXCEPTION 'Символ валюты "%" уже существует среди активных (неархивированных) валют', NEW."Символ"
              USING ERRCODE = 'unique_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_currency_fields_before_insert_or_update
    BEFORE INSERT OR UPDATE OR DELETE ON "Список валют"
    FOR EACH ROW
    EXECUTE FUNCTION validate_currency_fields();

-- Table Тип предложения

CREATE TABLE "Тип предложения"
(
  "ID типа предложения" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Тип предложения" ADD CONSTRAINT "Unique_Identifier3" PRIMARY KEY ("ID типа предложения");

-- Table Предложение

CREATE TABLE "Статус предложения"
(
	"ID статуса" Serial NOT NULL,
	"Статус" Character varying(30) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Статус предложения" ADD CONSTRAINT "Unique_Identifier1337" PRIMARY KEY ("ID статуса");

CREATE TABLE "Предложение"
(
  "ID предложения" Serial NOT NULL,
  "Сумма" Numeric(12,2) NOT NULL,
  "Сумма в валюте" Numeric(12, 2) NOT NULL,
  "ID операции бр. счёта" Integer NOT NULL,
  "ID ценной бумаги" Integer NOT NULL,
  "ID брокерского счёта" Integer NOT NULL,
  "ID типа предложения" Integer NOT NULL,
  "ID статуса предложения" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship20" ON "Предложение" ("ID ценной бумаги");
CREATE INDEX "IX_Relationship36" ON "Предложение" ("ID типа предложения");
ALTER TABLE "Предложение" ADD CONSTRAINT "Unique_Identifier11" PRIMARY KEY ("ID предложения","ID брокерского счёта");

-- Table Банк

CREATE TABLE "Банк"
(
  "ID банка" Serial NOT NULL,
  "Наименование" Character varying(120) NOT NULL,
  "ИНН" Character varying(40) NOT NULL,
  "ОГРН" Character varying(40) NOT NULL,
  "БИК" Character varying(40) NOT NULL,
  "Срок действия лицензии" Date NOT NULL,
  "Статус архивации" Boolean NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Банк" ADD CONSTRAINT "Unique_Identifier8" PRIMARY KEY ("ID банка");

CREATE OR REPLACE FUNCTION public.trg_validate_bank_before_insert_or_update()
RETURNS TRIGGER AS
$BODY$
BEGIN
    -- Убираем лишние пробелы
    NEW."Наименование" := TRIM(NEW."Наименование");
    NEW."ИНН" := TRIM(NEW."ИНН");
    NEW."ОГРН" := TRIM(NEW."ОГРН");
    NEW."БИК" := TRIM(NEW."БИК");

    IF NEW."Наименование" = '' OR NEW."ИНН" = '' OR NEW."ОГРН" = '' OR NEW."БИК" = '' THEN
        RAISE EXCEPTION 'Все поля банка обязательны для заполнения';
    END IF;

    IF NEW."БИК" !~ '^\d{9}$' THEN
        RAISE EXCEPTION 'БИК должен состоять ровно из 9 цифр (получено: %)', NEW."БИК";
    END IF;

    IF NEW."ИНН" !~ '^\d{10}$|^\d{12}$' THEN
        RAISE EXCEPTION 'ИНН должен состоять из 10 или 12 цифр (получено: %)', NEW."ИНН";
    END IF;

    IF NEW."ОГРН" !~ '^\d{13}$|^\d{15}$' THEN
        RAISE EXCEPTION 'ОГРН должен состоять из 13 или 15 цифр (получено: %)', NEW."ОГРН";
    END IF;

    IF NEW."Срок действия лицензии" < CURRENT_DATE THEN
        RAISE EXCEPTION 'Срок действия лицензии не может быть в прошлом (указана дата: %)', NEW."Срок действия лицензии";
    END IF;

    -- Уникальность БИК (если ещё нет уникального индекса)
    PERFORM 1
    FROM public."Банк"
    WHERE "БИК" = NEW."БИК"
      AND "ID банка" IS DISTINCT FROM NEW."ID банка";
    IF FOUND THEN
        RAISE EXCEPTION 'Банк с БИК % уже существует', NEW."БИК";
    END IF;

    -- Уникальность ИНН (опционально, если нужно)
    PERFORM 1
    FROM public."Банк"
    WHERE "ИНН" = NEW."ИНН"
      AND "ID банка" IS DISTINCT FROM NEW."ID банка";
    IF FOUND THEN
        RAISE EXCEPTION 'Банк с ИНН % уже существует', NEW."ИНН";
    END IF;

    RETURN NEW;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;

-- Привязываем триггер
CREATE TRIGGER trg_bank_validation
    BEFORE INSERT OR UPDATE ON public."Банк"
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_validate_bank_before_insert_or_update();

-- Table История цены

CREATE TABLE "История цены"
(
  "ID зап. ист. цены" Serial NOT NULL,
  "Дата" Date NOT NULL,
  "Цена" Numeric(12,2) NOT NULL,
  "ID ценной бумаги" Integer NOT NULL,
  UNIQUE ("Дата", "Цена")
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship50" ON "История цены" ("ID ценной бумаги");
ALTER TABLE "История цены" ADD CONSTRAINT "Unique_Identifier15" PRIMARY KEY ("ID зап. ист. цены");


CREATE OR REPLACE FUNCTION check_history_price_non_negative()
RETURNS TRIGGER AS $$
BEGIN
    -- Проверяем, что цена не меньше нуля
    IF NEW."Цена" < 0 THEN
        RAISE EXCEPTION 'Цена не может быть меньше нуля. Полученное значение: %', NEW."Цена";
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_price_before_insert
    BEFORE INSERT OR UPDATE ON public."История цены"
    FOR EACH ROW
    EXECUTE FUNCTION check_history_price_non_negative();

CREATE TABLE currency_rate (
    id SERIAL PRIMARY KEY,
    currency_id INT NOT NULL,
    rate NUMERIC(20, 8) NOT NULL,
    rate_date DATE NOT NULL DEFAULT CURRENT_DATE,
    UNIQUE (currency_id, rate_date) -- Один курс на пару в день
);

CREATE OR REPLACE FUNCTION check_currency_rate_positive()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Проверяем, что курс положительный
    IF NEW.rate <= 0 THEN
        RAISE EXCEPTION 'Курс валюты должен быть положительным числом. Получено: %', NEW.rate;
    END IF;

    -- Также можно проверить, что курс не NULL (хотя у нас есть NOT NULL constraint)
    IF NEW.rate IS NULL THEN
        RAISE EXCEPTION 'Курс валюты не может быть NULL';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_rate_positive_insert_or_update
    BEFORE INSERT OR UPDATE ON public.currency_rate
    FOR EACH ROW
    EXECUTE FUNCTION check_currency_rate_positive();

CREATE TABLE "Статус блока пользователя" (
	"ID статуса блокировки" Serial PRIMARY KEY,
	"Статус" VARCHAR(30) NOT NULL
)
WITH (autovacuum_enabled=true);

CREATE TABLE "Уровень прав админа" (
    "ID уровня прав" Serial PRIMARY KEY,
    "Уровень прав" VARCHAR(30) NOT NULL UNIQUE
)
WITH (autovacuum_enabled=true);
-- Create foreign keys (relationships) section -------------------------------------------------

ALTER TABLE "Персонал"
ADD CONSTRAINT "Relationship56"
FOREIGN KEY ("ID уровня прав")
REFERENCES "Уровень прав админа" ("ID уровня прав")
ON DELETE RESTRICT
ON UPDATE RESTRICT;

ALTER TABLE "Предложение"
ADD CONSTRAINT "FK_Status_Offer"
FOREIGN KEY ("ID статуса предложения")
REFERENCES "Статус предложения"("ID статуса")
ON UPDATE RESTRICT
ON DELETE RESTRICT;

ALTER TABLE "Предложение"
ADD CONSTRAINT "FK_BrOpHistory"
FOREIGN KEY ("ID операции бр. счёта")
REFERENCES "История операций бр. счёта"("ID операции бр. счёта")
ON UPDATE RESTRICT
ON DELETE RESTRICT;

ALTER TABLE "Пользователь"
ADD CONSTRAINT "Relationship55"
FOREIGN KEY ("ID статуса блокировки")
REFERENCES "Статус блока пользователя"("ID статуса блокировки")
ON DELETE RESTRICT
ON UPDATE RESTRICT;

ALTER TABLE "Пользователь"
  ADD CONSTRAINT "Relationship4"
    FOREIGN KEY ("ID статуса верификации")
    REFERENCES "Статус верификации" ("ID статуса верификации")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Депозитарный счёт"
  ADD CONSTRAINT "Relationship13"
    FOREIGN KEY ("ID пользователя")
    REFERENCES "Пользователь" ("ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

ALTER TABLE "Баланс депозитарного счёта"
  ADD CONSTRAINT "Relationship14"
    FOREIGN KEY ("ID депозитарного счёта", "ID пользователя")
    REFERENCES "Депозитарный счёт" ("ID депозитарного счёта", "ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship15"
    FOREIGN KEY ("ID депозитарного счёта", "ID пользователя")
    REFERENCES "Депозитарный счёт" ("ID депозитарного счёта", "ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

ALTER TABLE "Баланс депозитарного счёта"
  ADD CONSTRAINT "Relationship17"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Предложение"
  ADD CONSTRAINT "Relationship20"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Брокерский счёт"
  ADD CONSTRAINT "Relationship22"
    FOREIGN KEY ("ID банка")
    REFERENCES "Банк" ("ID банка")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "История операций бр. счёта"
  ADD CONSTRAINT "Relationship23"
    FOREIGN KEY ("ID брокерского счёта")
    REFERENCES "Брокерский счёт" ("ID брокерского счёта")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

ALTER TABLE "Брокерский счёт"
  ADD CONSTRAINT "Relationship25"
    FOREIGN KEY ("ID валюты")
    REFERENCES "Список валют" ("ID валюты")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship27"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship28"
    FOREIGN KEY ("ID сотрудника")
    REFERENCES "Персонал" ("ID сотрудника")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "История операций бр. счёта"
  ADD CONSTRAINT "Relationship29"
    FOREIGN KEY ("ID сотрудника")
    REFERENCES "Персонал" ("ID сотрудника")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Предложение"
  ADD CONSTRAINT "Relationship30"
    FOREIGN KEY ("ID брокерского счёта")
    REFERENCES "Брокерский счёт" ("ID брокерского счёта")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship31"
    FOREIGN KEY ("ID операции бр. счёта", "ID брокерского счёта")
    REFERENCES "История операций бр. счёта" ("ID операции бр. счёта", "ID брокерского счёта")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

ALTER TABLE "История операций бр. счёта"
  ADD CONSTRAINT "Relationship33"
    FOREIGN KEY ("ID типа операции бр. счёта")
    REFERENCES "Тип операции брокерского счёта" ("ID типа операции бр. счёта")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Персонал"
  ADD CONSTRAINT "Relationship34"
    FOREIGN KEY ("ID статуса трудоустройства")
    REFERENCES "Статус трудоустройства" ("ID статуса трудоустройства")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "История операций деп. счёта"
  ADD CONSTRAINT "Relationship35"
    FOREIGN KEY ("ID типа операции деп. счёта")
    REFERENCES "Тип операции депозитарного счёта" ("ID типа операции деп. счёта")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Предложение"
  ADD CONSTRAINT "Relationship36"
    FOREIGN KEY ("ID типа предложения")
    REFERENCES "Тип предложения" ("ID типа предложения")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Дивиденды"
  ADD CONSTRAINT "Relationship48"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

ALTER TABLE "Паспорт"
  ADD CONSTRAINT "Relationship49"
    FOREIGN KEY ("ID пользователя")
    REFERENCES "Пользователь" ("ID пользователя")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

ALTER TABLE "История цены"
  ADD CONSTRAINT "Relationship50"
    FOREIGN KEY ("ID ценной бумаги")
    REFERENCES "Список ценных бумаг" ("ID ценной бумаги")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Список ценных бумаг"
  ADD CONSTRAINT "Relationship51"
    FOREIGN KEY ("ID валюты")
    REFERENCES "Список валют" ("ID валюты")
      ON DELETE RESTRICT
      ON UPDATE RESTRICT;

ALTER TABLE "Брокерский счёт"
	ADD CONSTRAINT "Relationship52"
    FOREIGN KEY ("ID пользователя")
    REFERENCES "Пользователь"("ID пользователя")
    ON DELETE CASCADE
    ON UPDATE CASCADE;


ALTER TABLE currency_rate
ADD CONSTRAINT "Relationship53"
    FOREIGN KEY (currency_id)
    REFERENCES "Список валют"("ID валюты")
    ON DELETE RESTRICT
    ON UPDATE RESTRICT;

-- Справочники, которые не будут изменяться
INSERT INTO "Тип операции депозитарного счёта"("Тип")
VALUES
('Покупка'),
('Продажа'),
('Заморозка ЦБ'),
('Разморозка ЦБ');

INSERT INTO "Тип операции брокерского счёта"("Тип")
VALUES
('Пополнение'),
('Снятие'),
('Покупка ЦБ'),
('Покупка ЦБ (в)'),
('Продажа ЦБ'),
('Empty');

INSERT INTO "Тип предложения"("Тип")
VALUES
('Покупка'),
('Продажа');

INSERT INTO "Статус блока пользователя"("Статус")
VALUES
('Не заблокирован'),
('Заблокирован');

INSERT INTO "Уровень прав админа" ("Уровень прав")
VALUES
('Megaadmin'),
('Admin'),
('Broker'),
('Verifier');

INSERT INTO "Статус верификации"("Статус верификации")
VALUES
('Не подтверждён'),
('Подтверждён'),
('Ожидает верификации');

INSERT INTO "Статус предложения"("Статус")
VALUES
('Не подтверждён'),
('Подтверждён'),
('Ожидает верификации');

-- Справочники, которые могут изменяться
INSERT INTO "Статус трудоустройства"("Статус трудоустройства")
VALUES
('Активен'),
('Уволен'),
('Отпуск');


INSERT INTO public."Персонал" (
    "Номер трудового договора",
    "Логин",
    "Пароль",
    "ID статуса трудоустройства",
    "ID уровня прав"
) VALUES
(1,'megaadmin','$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', 1, 1),
(2,'system','', 1, 1);


-- todo: add inn as parameter
CREATE OR REPLACE FUNCTION public.add_brokerage_account(
    p_user_id       INTEGER,
    p_bank_id       INTEGER,
    p_currency_id   INTEGER
)
RETURNS INTEGER AS
$BODY$
DECLARE
    v_account_id INTEGER;
    v_bik        VARCHAR(40);
BEGIN
    -- Проверка существования банка
    SELECT "БИК"
    INTO v_bik
    FROM public."Банк"
    WHERE "ID банка" = p_bank_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Банк с ID % не найден', p_bank_id
              USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- Проверка существования валюты (и что она не архивирована)
    PERFORM 1
    FROM public."Список валют"
    WHERE "ID валюты" = p_currency_id
      AND "Статус архивации" = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Валюта с ID % не найдена или архивирована', p_currency_id
              USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- Создаём брокерский счёт с нулевым балансом
    INSERT INTO public."Брокерский счёт" (
        "Баланс",
        "ID банка",
        "БИК",
        "ИНН",
        "ID валюты",
        "ID пользователя",
        "Статус архивации"
    )
    VALUES (
        0.00,
        p_bank_id,
        v_bik,
        ' ',
        p_currency_id,
        p_user_id,
        false
    )
    RETURNING "ID брокерского счёта" INTO v_account_id;

    RETURN v_account_id;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


CREATE OR REPLACE FUNCTION public.delete_brokerage_account( -- todo: convert function to procedure
    p_account_id INTEGER,
    p_user_id    INTEGER
)
RETURNS VOID AS
$BODY$
BEGIN
    -- Проверяем существование и принадлежность счёта
    IF NOT EXISTS (
        SELECT 1
        FROM public."Брокерский счёт"
        WHERE "ID брокерского счёта" = p_account_id
          AND "ID пользователя" = p_user_id
    ) THEN
        RAISE EXCEPTION 'Брокерский счёт с ID % не найден или не принадлежит вам', p_account_id;
    END IF;

    -- Проверяем баланс
    IF (SELECT "Баланс" FROM public."Брокерский счёт" WHERE "ID брокерского счёта" = p_account_id) != 0 THEN
        RAISE EXCEPTION 'Нельзя удалить брокерский счёт с ненулевым балансом';
    END IF;

    -- Удаляем счёт (каскадное удаление через FK ON DELETE CASCADE, если настроено)
    DELETE FROM public."Брокерский счёт"
    WHERE "ID брокерского счёта" = p_account_id;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


CREATE OR REPLACE FUNCTION public.add_bank(
    p_name               VARCHAR(120),
    p_inn                VARCHAR(40),
    p_ogrn               VARCHAR(40),
    p_bik                VARCHAR(40),
    p_license_expiry_date DATE
)
RETURNS INTEGER AS
$BODY$
DECLARE
    v_bank_id INTEGER;
BEGIN
    -- Все валидации теперь в триггере — здесь только вставка
    INSERT INTO public."Банк" (
        "Наименование",
        "ИНН",
        "ОГРН",
        "БИК",
        "Срок действия лицензии",
        "Статус архивации"
    )
    VALUES (
        p_name,
        p_inn,
        p_ogrn,
        p_bik,
        p_license_expiry_date,
        false
    )
    RETURNING "ID банка" INTO v_bank_id;

    RETURN v_bank_id;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


CREATE OR REPLACE FUNCTION public.submit_passport(
    p_user_id INTEGER,
    p_last_name VARCHAR,
    p_first_name VARCHAR,
    p_patronymic VARCHAR,
    p_series VARCHAR,
    p_number VARCHAR,
    p_gender VARCHAR,
    p_birth_date DATE,
    p_birth_place VARCHAR,
    p_registration_place VARCHAR,
    p_issue_date DATE,
    p_issued_by VARCHAR
)
RETURNS INTEGER AS
$BODY$
DECLARE
    v_passport_id INTEGER;
BEGIN
    IF EXISTS (SELECT 1 FROM "Паспорт" WHERE "ID пользователя" = p_user_id) THEN
        RAISE EXCEPTION 'Паспорт уже привязан к пользователю'
              USING ERRCODE = 'unique_violation';
    END IF;

    -- Вставляем паспорт
    INSERT INTO "Паспорт" (
    "ID пользователя", "Фамилия", "Имя", "Отчество", "Серия", "Номер",
    "Пол", "Дата рождения", "Место рождения", "Место прописки",
    "Дата выдачи", "Кем выдан", "Актуальность"
) VALUES (
    p_user_id, p_last_name, p_first_name, p_patronymic, p_series, p_number,
    p_gender, p_birth_date, p_birth_place, p_registration_place,
    p_issue_date, p_issued_by, TRUE
)
RETURNING "ID паспорта" INTO v_passport_id;

    -- Обновляем статус верификации пользователя
    UPDATE "Пользователь"
    SET "ID статуса верификации" = 3  -- "Ожидает верификации"
    WHERE "ID пользователя" = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Пользователь с ID % не найден', p_user_id;
    END IF;

    RETURN v_passport_id;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION public.change_brokerage_account_balance(
    p_account_id integer,
    p_amount numeric,
    p_brokerage_operation_type integer,  -- Теперь используется как ID типа операции
    p_staff_id integer DEFAULT 2
)
    RETURNS INTEGER
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE SECURITY DEFINER PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_current_balance NUMERIC(12,2);
    v_operation_id INTEGER;
BEGIN
    -- Проверяем, существует ли тип операции
    PERFORM 1
    FROM public."Тип операции брокерского счёта"
    WHERE "ID типа операции бр. счёта" = p_brokerage_operation_type;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Тип операции брокерского счёта с ID % не найден', p_brokerage_operation_type;
    END IF;

    -- Блокируем строку счёта
    PERFORM 1 FROM "Брокерский счёт"
    WHERE "ID брокерского счёта" = p_account_id
    FOR UPDATE;

    -- Получаем текущий баланс
    SELECT "Баланс" INTO v_current_balance
    FROM "Брокерский счёт"
    WHERE "ID брокерского счёта" = p_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Счёт с ID % не найден', p_account_id;
    END IF;

    -- Проверка на отрицательный баланс при выводе
    IF v_current_balance + p_amount < 0 THEN
        RAISE EXCEPTION 'Недостаточно средств на счёте (текущий баланс: %, запрос: %)',
                        v_current_balance, p_amount;
    END IF;

    -- Обновляем баланс
    UPDATE "Брокерский счёт"
    SET "Баланс" = "Баланс" + p_amount
    WHERE "ID брокерского счёта" = p_account_id;

    -- Пишем запись в историю и получаем ID операции
    INSERT INTO "История операций бр. счёта" (
        "Сумма операции",
        "Время",
        "ID брокерского счёта",
        "ID сотрудника",
        "ID типа операции бр. счёта"  -- Теперь используем p_brokerage_operation_type
    ) VALUES (
        p_amount,
        now(),
        p_account_id,
        p_staff_id,
        p_brokerage_operation_type  -- ← Вставляем p_brokerage_operation_type вместо v_operation_type_id
    )
    RETURNING "ID операции бр. счёта" INTO v_operation_id;

    RETURN v_operation_id;
END;
$BODY$;

CREATE OR REPLACE FUNCTION check_user_verification_status(user_id integer) -- todo: rename function to get_...
RETURNS boolean AS $$
DECLARE
    verification_status_text varchar(20);
BEGIN
    -- Получаем статус верификации для указанного пользователя
    SELECT v."Статус верификации" INTO verification_status_text
    FROM "Пользователь" u
    INNER JOIN "Статус верификации" v ON u."ID статуса верификации" = v."ID статуса верификации"
    WHERE u."ID пользователя" = user_id;

    -- Если запись не найдена, возвращаем false
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Возвращаем true если статус "Подтверждён", иначе false
    RETURN verification_status_text = 'Подтверждён';
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_user_securities(user_id INT)
RETURNS TABLE (
    security_name TEXT,
    lot_size NUMERIC(12,2),
    isin TEXT,
    has_dividends BOOLEAN,
    amount DECIMAL,
    currency_code CHAR(3),
    currency_symbol VARCHAR(10)
) AS $$
    SELECT
        s."Наименование" AS security_name,
        s."Размер лота" AS lot_size,
        s."ISIN" AS isin,
        s."Выплата дивидендов" AS has_dividends,
        bds."Сумма" AS amount,
        c."Код" AS currency_code,
        c."Символ" AS currency_symbol
    FROM "Депозитарный счёт" ds
    JOIN "Баланс депозитарного счёта" bds
        ON bds."ID депозитарного счёта" = ds."ID депозитарного счёта"
    JOIN "Список ценных бумаг" s
        ON s."ID ценной бумаги" = bds."ID ценной бумаги"
    JOIN "Список валют" c
        ON c."ID валюты" = s."ID валюты"
    WHERE ds."ID пользователя" = user_id;
$$ LANGUAGE sql;


CREATE OR REPLACE FUNCTION public.get_user_offers(
	user_id integer)
    RETURNS TABLE(id integer, "offer_type" text, "security_name" text, "quantity" numeric, "proposal_status" integer)
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
    SELECT
		p."ID предложения" AS "id",
        t."Тип" AS "offer_type",
        b."Наименование" AS "security_name",
        p."Сумма" AS "quantity",
		p."ID статуса предложения" AS "proposal_status"
    FROM "Предложение" p
    LEFT JOIN "Список ценных бумаг" b
        ON p."ID ценной бумаги" = b."ID ценной бумаги"
    LEFT JOIN "Тип предложения" t
        ON p."ID типа предложения" = t."ID типа предложения"
    JOIN "Брокерский счёт" acc
        ON p."ID брокерского счёта" = acc."ID брокерского счёта"
    WHERE acc."ID пользователя" = user_id
	ORDER BY id DESC;
$BODY$;


CREATE OR REPLACE FUNCTION public.get_exchange_stocks() -- список всех ценных бумаг с доп. информацией (вкладка "биржа")
RETURNS TABLE (
    id              INTEGER,
    ticker          VARCHAR,
    price           NUMERIC(12,2),
    currency        VARCHAR(10),
    change          NUMERIC(6,2)
)
LANGUAGE sql
STABLE
AS $$
WITH last_prices AS (
    SELECT
        ph."ID ценной бумаги",
        ph."Цена",
        ph."Дата",
        ROW_NUMBER() OVER (
            PARTITION BY ph."ID ценной бумаги"
            ORDER BY ph."Дата" DESC
        ) AS rn
    FROM "История цены" ph
),
prices AS (
    SELECT
        s."ID ценной бумаги" AS id,
        s."Наименование" AS ticker,
        lp."Цена" AS last_price,
        prev."Цена" AS prev_price,
        c."Символ" AS currency
    FROM "Список ценных бумаг" s
    JOIN last_prices lp
        ON lp."ID ценной бумаги" = s."ID ценной бумаги"
       AND lp.rn = 1
    LEFT JOIN last_prices prev
        ON prev."ID ценной бумаги" = s."ID ценной бумаги"
       AND prev.rn = 2
    JOIN "Список валют" c
        ON c."ID валюты" = s."ID валюты"
)
SELECT
    id,
    ticker,
    last_price AS price,
    currency,
    CASE
        WHEN prev_price IS NULL OR prev_price = 0 THEN 0
        ELSE ROUND(
            ((last_price - prev_price) / prev_price) * 100,
            2
        )
    END AS change
FROM prices
ORDER BY ticker;
$$;


CREATE OR REPLACE FUNCTION public.get_brokerage_account_operations(
    p_account_id integer)
    RETURNS TABLE(
        "Время" timestamp without time zone,
        "Тип операции" character varying,
        "Сумма операции" numeric,
        "Символ валюты" character varying
    )
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000
AS $BODY$
    SELECT
        h."Время",
        t."Тип" AS "Тип операции",
        h."Сумма операции",
        c."Символ" AS "Символ валюты"
    FROM "История операций бр. счёта" h
    JOIN "Тип операции брокерского счёта" t ON h."ID типа операции бр. счёта" = t."ID типа операции бр. счёта"
    JOIN "Брокерский счёт" b ON h."ID брокерского счёта" = b."ID брокерского счёта"
    JOIN "Список валют" c ON b."ID валюты" = c."ID валюты"
    WHERE h."ID брокерского счёта" = p_account_id
    ORDER BY h."Время" DESC;
$BODY$;

-- Курс CUR1/CUR2
CREATE OR REPLACE FUNCTION get_currency_rate(
    p_currency1 INT,
    p_currency2 INT,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS NUMERIC(20,8)
LANGUAGE plpgsql
AS $$
DECLARE
    base_id CONSTANT INT := 1;  -- ID рубля РФ
    rate1 NUMERIC(20,8);        -- курс currency1 к RUB
    rate2 NUMERIC(20,8);        -- курс currency2 к RUB
    found_date DATE;
BEGIN
    -- Курс для currency1 (RUB → currency1)
    IF p_currency1 = base_id THEN
        rate1 := 1.0;
    ELSE
        -- Ищем ближайший курс ДО или НА дату
        SELECT rate, rate_date
        INTO rate1, found_date
        FROM currency_rate
        WHERE currency_id = p_currency1
          AND rate_date <= p_date
        ORDER BY rate_date DESC
        LIMIT 1;

        IF rate1 IS NULL THEN
            RAISE EXCEPTION 'Нет курса для валюты % ни на %, ни до этой даты',
                            p_currency1, p_date;
        END IF;

        -- Для удобства можно вывести предупреждение, если не точная дата
        IF found_date < p_date THEN
            RAISE NOTICE 'Для валюты % использован курс на % (ближайший предыдущий)',
                         p_currency1, found_date;
        END IF;
    END IF;

    -- Курс для currency2 (RUB → currency2)
    IF p_currency2 = base_id THEN
        rate2 := 1.0;
    ELSE
        SELECT rate, rate_date
        INTO rate2, found_date
        FROM currency_rate
        WHERE currency_id = p_currency2
          AND rate_date <= p_date
        ORDER BY rate_date DESC
        LIMIT 1;

        IF rate2 IS NULL THEN
            RAISE EXCEPTION 'Нет курса для валюты % ни на %, ни до этой даты',
                            p_currency2, p_date;
        END IF;

        IF found_date < p_date THEN
            RAISE NOTICE 'Для валюты % использован курс на % (ближайший предыдущий)',
                         p_currency2, found_date;
        END IF;
    END IF;
    RETURN rate1 / rate2;
END;
$$;


-- Курс p_target_currency_id/RUB
CREATE OR REPLACE FUNCTION get_currency_rate(p_target_currency_id INT)
RETURNS NUMERIC AS $$
    SELECT get_currency_rate(p_target_currency_id, 1);
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION public.get_currencies_info()
    RETURNS TABLE(
        "ID валюты" integer,
        "Код" character(3),
        "Символ" character varying(10),
        "Статус архивации" boolean,
        "Курс" numeric
    )
    LANGUAGE 'sql'
    COST 100
    STABLE PARALLEL SAFE
    ROWS 1000
AS $BODY$
    SELECT
        "ID валюты",
        "Код",
        "Символ",
        "Статус архивации",
        get_currency_rate("ID валюты") as "Курс"
    FROM "Список валют"
    ORDER BY 1;
$BODY$;

CREATE OR REPLACE FUNCTION get_depo_value(
    p_depo_id INT,
    p_user_id INT,
    p_currency_id INT
) RETURNS NUMERIC AS $$
DECLARE
    total_value NUMERIC := 0;
    paper_value NUMERIC;
    paper_currency_id INT;
    exchange_rate NUMERIC;
    latest_date DATE;
    paper_price NUMERIC;
BEGIN
    -- Перебираем все ценные бумаги на депозитарном счете
    FOR paper_currency_id, paper_price, paper_value IN
        SELECT
            s."ID валюты",
            COALESCE(ph."Цена", 0) as price,
            b."Сумма" as quantity
        FROM "Баланс депозитарного счёта" b
        JOIN "Список ценных бумаг" s
            ON s."ID ценной бумаги" = b."ID ценной бумаги"
        LEFT JOIN LATERAL (
            SELECT ph."Цена"
            FROM "История цены" ph
            WHERE ph."ID ценной бумаги" = b."ID ценной бумаги"
            ORDER BY ph."Дата" DESC
            LIMIT 1
        ) ph ON TRUE
        WHERE b."ID депозитарного счёта" = p_depo_id
          AND b."ID пользователя" = p_user_id
    LOOP
        -- Если цена не найдена, пропускаем
        IF paper_price IS NULL OR paper_price = 0 THEN
            CONTINUE;
        END IF;
        paper_value := paper_value * paper_price;
        exchange_rate := get_currency_rate(paper_currency_id, p_currency_id);
        total_value := total_value + (paper_value / exchange_rate);
    END LOOP;

    RETURN COALESCE(total_value, 0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.get_brokerage_account_value(
    p_brokerage_account_id INTEGER,
    p_target_currency_id   INTEGER,
    p_date                 DATE DEFAULT CURRENT_DATE
)
RETURNS NUMERIC(20,8) AS
$BODY$
DECLARE
    v_balance          NUMERIC(12,2);
    v_account_currency_id INTEGER;
    v_converted_amount NUMERIC(20,8);
BEGIN
    -- Получаем баланс и валюту счёта
    SELECT "Баланс", "ID валюты"
    INTO v_balance, v_account_currency_id
    FROM public."Брокерский счёт"
    WHERE "ID брокерского счёта" = p_brokerage_account_id;

    -- Если счёт не найден — бросаем ошибку
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Брокерский счёт с ID % не существует', p_brokerage_account_id
              USING ERRCODE = 'no_data_found';
    END IF;

    -- Если валюта счёта уже целевая — возвращаем баланс без конвертации
    IF v_account_currency_id = p_target_currency_id THEN
        RETURN v_balance;
    END IF;

    v_converted_amount := v_balance * public.get_currency_rate(
        p_currency1 => v_account_currency_id,   -- из валюты счёта
        p_currency2 => p_target_currency_id,   -- в целевую валюту
        p_date      => p_date
    );

    RETURN ROUND(v_converted_amount, 8);  -- округляем до 8 знаков после запятой
END;
$BODY$
LANGUAGE plpgsql VOLATILE;


CREATE OR REPLACE FUNCTION public.get_total_account_value(
    p_user_id integer,
    p_currency_id integer)
    RETURNS numeric
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    total NUMERIC := 0;
    depo RECORD;
    bs_sum NUMERIC := 0;
BEGIN
    -- Сумма по всем депозитарным счетам (предполагаем, что calc_depo_value уже использует get_currency_rate или будет обновлена аналогично)
    FOR depo IN
        SELECT "ID депозитарного счёта" AS id
        FROM "Депозитарный счёт"
        WHERE "ID пользователя" = p_user_id
    LOOP
        total := total + get_depo_value(depo.id, p_user_id, p_currency_id);
    END LOOP;

    -- Сумма по брокерским счетам с конвертацией через get_currency_rate
    SELECT COALESCE(SUM(
        bs."Баланс" * public.get_currency_rate(bs."ID валюты", p_currency_id, CURRENT_DATE)
    ), 0)
    INTO bs_sum
    FROM "Брокерский счёт" bs
    WHERE bs."ID пользователя" = p_user_id;

    total := total + COALESCE(bs_sum, 0);

    RETURN COALESCE(total, 0);
END;
$BODY$;

CREATE OR REPLACE FUNCTION calc_offer_value(
    p_offer_id INT
) RETURNS NUMERIC AS $$
DECLARE
    paper_id INT;
    qty NUMERIC := 0;
    price NUMERIC := 0;
    latest_date DATE;
BEGIN
    -- Получаем ID ценной бумаги и количество из предложения
    SELECT "ID ценной бумаги", "Сумма"
    INTO paper_id, qty
    FROM "Предложение"
    WHERE "ID предложения" = p_offer_id;

    -- Если предложение не найдено — возвращаем 0
    IF paper_id IS NULL THEN
        RETURN 0;
    END IF;

    -- Находим последнюю дату с данными для этой бумаги
    SELECT MAX("Дата")
    INTO latest_date
    FROM "История цены"
    WHERE "ID ценной бумаги" = paper_id;

    -- Если нет данных по цене — возвращаем 0
    IF latest_date IS NULL THEN
        RETURN 0;
    END IF;

    -- Берём последнюю цену
    SELECT "Цена"
    INTO price
    FROM "История цены"
    WHERE "ID ценной бумаги" = paper_id
      AND "Дата" = latest_date
    LIMIT 1;

    -- Если цены нет — возвращаем 0, иначе вычисляем стоимость
    RETURN COALESCE(qty, 0) * COALESCE(price, 0);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION calc_depo_growth(
    p_depo_id INT,
    p_user_id INT,
    p_interval TEXT
) RETURNS NUMERIC AS $$
DECLARE
    current_value NUMERIC := 0;
    past_value NUMERIC := 0;
    target_date DATE;
BEGIN
    -- 1. Текущая стоимость депозита в RUB
    current_value := calc_depo_value(p_depo_id, p_user_id, 1); -- 1 = RUB

    -- 2. Определяем дату в прошлом
    target_date := (CURRENT_DATE - p_interval::interval)::DATE;

    -- 3. Стоимость депозита на целевую дату в прошлом
    SELECT
        SUM(b."Сумма" * COALESCE(ph."Цена", 0))
    INTO past_value
    FROM "Баланс депозитарного счёта" b
    LEFT JOIN LATERAL (
        SELECT ph."Цена"
        FROM "История цены" ph
        WHERE ph."ID ценной бумаги" = b."ID ценной бумаги"
          AND ph."Дата" <= target_date
        ORDER BY ph."Дата" DESC
        LIMIT 1
    ) ph ON TRUE
    WHERE b."ID депозитарного счёта" = p_depo_id
      AND b."ID пользователя" = p_user_id;

    RETURN COALESCE(current_value, 0) - COALESCE(past_value, 0);
END;
$$ LANGUAGE plpgsql;


-- 2.7 calc_stock_growth: рост цены акции за день
CREATE OR REPLACE FUNCTION calc_stock_growth(
    p_paper_id INT
) RETURNS NUMERIC AS $$
DECLARE
    today_price NUMERIC := 0;
    yesterday_price NUMERIC := 0;
    latest_date DATE;
    prev_date DATE;
BEGIN
    -- Находим последнюю дату с данными
    SELECT MAX("Дата")
    INTO latest_date
    FROM "История цены"
    WHERE "ID ценной бумаги" = p_paper_id;

    -- Если нет данных
    IF latest_date IS NULL THEN
        RETURN 0;
    END IF;

    -- Получаем цену за последний день
    SELECT "Цена"
    INTO today_price
    FROM "История цены"
    WHERE "ID ценной бумаги" = p_paper_id
      AND "Дата" = latest_date
    LIMIT 1;

    -- Находим предыдущую дату (последний день перед latest_date)
    SELECT MAX("Дата")
    INTO prev_date
    FROM "История цены"
    WHERE "ID ценной бумаги" = p_paper_id
      AND "Дата" < latest_date;

    -- Если есть предыдущая дата, получаем цену за нее
    IF prev_date IS NOT NULL THEN
        SELECT "Цена"
        INTO yesterday_price
        FROM "История цены"
        WHERE "ID ценной бумаги" = p_paper_id
          AND "Дата" = prev_date
        LIMIT 1;
    END IF;

    RETURN COALESCE(today_price, 0) - COALESCE(yesterday_price, 0);
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


CREATE OR REPLACE FUNCTION public.get_security_value( -- цена 1 ед. ценной бумаги в заданной валюте
    p_security_id  integer,
    p_currency_id  integer
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_price         numeric;
    v_security_cur  integer;
    v_rate          numeric;
    v_latest_date   date;
BEGIN
    -- 1. Находим последнюю дату с данными для этой бумаги
    SELECT MAX(ip."Дата")
    INTO v_latest_date
    FROM "История цены" ip
    WHERE ip."ID ценной бумаги" = p_security_id;

    -- Если данных нет
    IF v_latest_date IS NULL THEN
        RETURN NULL;
    END IF;

    -- 2. Берём последнюю цену и валюту бумаги
    SELECT
        ip."Цена",
        s."ID валюты"
    INTO
        v_price,
        v_security_cur
    FROM "История цены" ip
    JOIN "Список ценных бумаг" s
        ON s."ID ценной бумаги" = ip."ID ценной бумаги"
    WHERE ip."ID ценной бумаги" = p_security_id
      AND ip."Дата" = v_latest_date
    LIMIT 1;

    -- Если цена не найдена
    IF v_price IS NULL THEN
        RETURN NULL;
    END IF;

    -- 3. Если валюта совпадает — просто возвращаем цену
    IF v_security_cur = p_currency_id THEN
        RETURN v_price;
    END IF;

    -- 4. Получаем курс конвертации
    v_rate := get_currency_rate(v_security_cur, p_currency_id);

    IF v_rate IS NULL THEN
        RETURN NULL;
    END IF;

    -- 5. Итоговая стоимость одной бумаги в целевой валюте
    RETURN ROUND(v_price / v_rate, 8);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_security_value_native( -- цена 1 ед. ценной бумаги в собственной валюте
    p_security_id integer
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_price numeric;
BEGIN
    -- Берём последнюю цену бумаги
    SELECT ip."Цена"
    INTO v_price
    FROM "История цены" ip
    WHERE ip."ID ценной бумаги" = p_security_id
    ORDER BY ip."Дата" DESC
    LIMIT 1;

    -- Если цена не найдена
    IF v_price IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN v_price;
END;
$$;

CREATE OR REPLACE FUNCTION add_buy_proposal(
    p_security_id INTEGER,
    p_brokerage_account_id INTEGER,
    p_lot_amount_to_buy INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_lot_size NUMERIC(12,2);
    v_security_price NUMERIC(12,2);
    v_total_quantity NUMERIC(12,2); -- Общее количество ценных бумаг
    v_total_cost NUMERIC(12,2);     -- Общая стоимость в валюте (для списания)

    v_operation_id INTEGER;         -- ID новой операции в истории (на всякий случай, если понадобится)
    v_proposal_id INTEGER;          -- ID нового предложения

    v_buy_type_id INTEGER := 1;                 -- Покупка
    v_active_status_id INTEGER := 3;            -- Новое/активное предложение
    v_employee_id INTEGER := 2;                 -- По умолчанию сотрудник 5
BEGIN
    -- Проверка: количество лотов должно быть строго больше нуля
    IF p_lot_amount_to_buy <= 0 THEN
        RAISE EXCEPTION 'Количество лотов для покупки должно быть строго больше нуля (получено: %)', p_lot_amount_to_buy;
    END IF;

    -- 1. Получаем размер лота ценной бумаги
    SELECT "Размер лота"
    INTO v_lot_size
    FROM public."Список ценных бумаг"
    WHERE "ID ценной бумаги" = p_security_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ценная бумага с ID % не найдена', p_security_id;
    END IF;

    -- 2. Получаем текущую цену одной бумаги
    v_security_price := get_security_value_native(p_security_id);

    -- 3. Вычисляем общее количество ценных бумаг
    v_total_quantity := v_lot_size * p_lot_amount_to_buy;

    -- 4. Вычисляем общую стоимость (для списания)
    v_total_cost := v_total_quantity * v_security_price;

    -- 5. Изменяем баланс и пишем в историю через специализированную функцию
    -- Передаём отрицательную сумму → функция сама определит тип операции = 2 (списание)
    SELECT change_brokerage_account_balance(
        p_account_id := p_brokerage_account_id,
        p_amount     := -v_total_cost,
        p_brokerage_operation_type := 3,        -- <-- Исправлено: теперь именованный
        p_staff_id   := v_employee_id
    ) INTO v_operation_id;

    -- 6. Получаем следующий ID для предложения
    v_proposal_id := nextval('"Предложение_ID предложения_seq"'::regclass);

    -- 7. Создаём предложение на покупку
    INSERT INTO public."Предложение" (
        "Сумма",                        -- количество ценных бумаг
        "Сумма в валюте",
		"ID операции бр. счёта",
		"ID ценной бумаги",
        "ID брокерского счёта",
        "ID типа предложения",
        "ID статуса предложения"
    ) VALUES (
        v_total_quantity,
		v_total_cost,
		v_operation_id,
        p_security_id,
        p_brokerage_account_id,
        v_buy_type_id,
        v_active_status_id
    );

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_sell_proposal(
    p_security_id INTEGER,
    p_brokerage_account_id INTEGER,
    p_lot_amount_to_sell INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_lot_size NUMERIC(12,2);
    v_total_quantity NUMERIC(12,2); -- Общее количество ценных бумаг для продажи
	v_total_cost NUMERIC(12, 2);

    v_user_id INTEGER; -- ID пользователя
    v_deposit_account_id INTEGER; -- ID депозитарного счёта

    v_current_deposit_balance NUMERIC(12,2); -- Текущее доступное количество бумаг

    v_brokerage_operation_id INTEGER; -- ID вставленной записи в бр. истории
    v_deposit_operation_id INTEGER;   -- ID вставленной записи в деп. истории (не обязателен, но оставляем)
    v_proposal_id INTEGER;            -- ID нового предложения

    v_sell_type_id INTEGER := 2;      -- Тип предложения: продажа
    v_active_status_id INTEGER := 3;  -- Статус нового предложения
    v_employee_id INTEGER := 2;       -- Сотрудник по умолчанию
	v_empty_brokerage_type INTEGER := 6; -- Неотображающаяся операция
    v_lock_deposit_operation_type_id INTEGER := 3; -- Тип операции деп. счёта: заморозка
BEGIN
    -- 1. Проверка: количество лотов должно быть строго больше нуля
    IF p_lot_amount_to_sell <= 0 THEN
        RAISE EXCEPTION 'Количество лотов для продажи должно быть строго больше нуля (получено: %)', p_lot_amount_to_sell;
    END IF;

    -- 2. Получаем размер лота ценной бумаги
    SELECT "Размер лота"
    INTO v_lot_size
    FROM public."Список ценных бумаг"
    WHERE "ID ценной бумаги" = p_security_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ценная бумага с ID % не найдена', p_security_id;
    END IF;

    -- 3. Вычисляем общее количество ценных бумаг для продажи
    v_total_quantity := v_lot_size * p_lot_amount_to_sell;
	v_total_cost := v_total_quantity * get_security_value_native(p_security_id);

    -- 4. Получаем ID пользователя по брокерскому счёту
    SELECT "ID пользователя"
    INTO v_user_id
    FROM public."Брокерский счёт"
    WHERE "ID брокерского счёта" = p_brokerage_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Брокерский счёт с ID % не найден', p_brokerage_account_id;
    END IF;

    -- 5. Получаем ID депозитарного счёта по ID пользователя
    SELECT "ID депозитарного счёта"
    INTO v_deposit_account_id
    FROM public."Депозитарный счёт"
    WHERE "ID пользователя" = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Депозитарный счёт для пользователя ID % не найден', v_user_id;
    END IF;

    -- 6. Проверяем наличие и достаточность свободного баланса ценных бумаг
    SELECT "Сумма"
    INTO v_current_deposit_balance
    FROM public."Баланс депозитарного счёта"
    WHERE "ID депозитарного счёта" = v_deposit_account_id
      AND "ID пользователя" = v_user_id
      AND "ID ценной бумаги" = p_security_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Запись баланса для ценной бумаги ID % на депозитарном счёте пользователя ID % не найдена',
            p_security_id, v_user_id;
    END IF;

    IF v_current_deposit_balance < v_total_quantity THEN
        RAISE EXCEPTION 'Недостаточно свободных ценных бумаг на депозитарном счёте. Доступно: %, требуется: %',
            v_current_deposit_balance, v_total_quantity;
    END IF;

    -- 7. Замораживаем бумаги: уменьшаем доступное количество
    UPDATE public."Баланс депозитарного счёта"
    SET "Сумма" = "Сумма" - v_total_quantity
    WHERE "ID депозитарного счёта" = v_deposit_account_id
      AND "ID пользователя" = v_user_id
      AND "ID ценной бумаги" = p_security_id;

    INSERT INTO public."История операций бр. счёта" (
        "Сумма операции",
        "Время",
        "ID брокерского счёта",
        "ID сотрудника",
        "ID типа операции бр. счёта"
    ) VALUES (
        0,
        CURRENT_TIMESTAMP,
        p_brokerage_account_id,
        v_employee_id,
        v_empty_brokerage_type
    )
    RETURNING "ID операции бр. счёта" INTO v_brokerage_operation_id;

    INSERT INTO public."История операций деп. счёта" (
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
        v_total_quantity,
        CURRENT_TIMESTAMP,
        v_deposit_account_id,
        v_user_id,
        p_security_id,
        v_employee_id,
        v_brokerage_operation_id,
        p_brokerage_account_id,
        v_lock_deposit_operation_type_id
    )
    RETURNING "ID операции деп. счёта" INTO v_deposit_operation_id;
    INSERT INTO public."Предложение" (
        "Сумма",
        "Сумма в валюте",
		"ID операции бр. счёта",
		"ID ценной бумаги",
        "ID брокерского счёта",
        "ID типа предложения",
        "ID статуса предложения"
    ) VALUES (
        v_total_quantity,
		v_total_cost,
		v_brokerage_operation_id,
        p_security_id,
        p_brokerage_account_id,
        v_sell_type_id,
        v_active_status_id
    )
    RETURNING "ID предложения" INTO v_proposal_id;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.process_buy_proposal(
    p_employee_id integer,
    p_proposal_id integer,
    p_verify boolean
)
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
COST 100
AS $BODY$
DECLARE
    v_brokerage_account_id INTEGER;
    v_security_id INTEGER;
    v_quantity NUMERIC(12,2);
    v_cost NUMERIC(12,2);

    v_deposit_account_id INTEGER;
    v_user_id INTEGER;

    v_broker_operation_id INTEGER;
    v_new_broker_operation_id INTEGER;
    v_new_deposit_operation_id INTEGER;

    c_buy_type_id CONSTANT INTEGER := 1;
    c_active_status_id CONSTANT INTEGER := 3;
    c_approved_status_id CONSTANT INTEGER := 2;
    c_rejected_status_id CONSTANT INTEGER := 1;
    c_deposit_operation_type_id CONSTANT INTEGER := 1;
	c_brokerage_operation_return_type_id CONSTANT INTEGER := 4;
BEGIN
    SELECT
        p."ID брокерского счёта",
        p."ID ценной бумаги",
        p."Сумма" AS quantity,
        p."Сумма в валюте" AS cost,
        p."ID операции бр. счёта" AS broker_operation_id,
        ba."ID пользователя"
    INTO
        v_brokerage_account_id,
        v_security_id,
        v_quantity,
        v_cost,
        v_broker_operation_id,
        v_user_id
    FROM public."Предложение" p
    JOIN public."Брокерский счёт" ba ON ba."ID брокерского счёта" = p."ID брокерского счёта"
    WHERE p."ID предложения" = p_proposal_id
      AND p."ID типа предложения" = c_buy_type_id
      AND p."ID статуса предложения" = c_active_status_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Предложение с ID % не найдено или уже обработано/не является активным предложением на покупку', p_proposal_id;
    END IF;

    SELECT "ID депозитарного счёта"
    INTO v_deposit_account_id
    FROM public."Депозитарный счёт"
    WHERE "ID пользователя" = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'У пользователя с ID % не найден депозитарный счёт', v_user_id;
    END IF;

    IF p_verify THEN
        PERFORM 1
        FROM public."Баланс депозитарного счёта"
        WHERE "ID депозитарного счёта" = v_deposit_account_id
          AND "ID пользователя" = v_user_id
          AND "ID ценной бумаги" = v_security_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'В балансе депозитарного счёта отсутствует запись для ценной бумаги ID % у пользователя ID %', v_security_id, v_user_id;
        END IF;

        UPDATE public."Баланс депозитарного счёта"
        SET "Сумма" = "Сумма" + v_quantity
        WHERE "ID депозитарного счёта" = v_deposit_account_id
          AND "ID пользователя" = v_user_id
          AND "ID ценной бумаги" = v_security_id;

        INSERT INTO public."История операций деп. счёта" (
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
            v_quantity,
            CURRENT_TIMESTAMP,
            v_deposit_account_id,
            v_user_id,
            v_security_id,
            p_employee_id,
            v_broker_operation_id,
            v_brokerage_account_id,
            c_deposit_operation_type_id
        )
        RETURNING "ID операции деп. счёта" INTO v_new_deposit_operation_id;
        UPDATE public."Предложение"
        SET "ID статуса предложения" = c_approved_status_id
        WHERE "ID предложения" = p_proposal_id;
    ELSE
        SELECT change_brokerage_account_balance(
    p_account_id := v_brokerage_account_id,
    p_amount := v_cost,
    p_brokerage_operation_type := c_brokerage_operation_return_type_id, -- <-- Исправлено
    p_staff_id := p_employee_id
) INTO v_new_broker_operation_id;
        UPDATE public."Предложение"
        SET "ID статуса предложения" = c_rejected_status_id
        WHERE "ID предложения" = p_proposal_id;
    END IF;

    RAISE NOTICE 'Предложение % успешно %', p_proposal_id, CASE WHEN p_verify THEN 'одобрено' ELSE 'отклонено' END;
END;
$BODY$;


CREATE OR REPLACE FUNCTION public.process_sell_proposal(
	p_employee_id integer,
	p_proposal_id integer,
	p_verify boolean)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_proposal RECORD;

    v_brokerage_account_id INTEGER;
    v_security_id INTEGER;
    v_quantity NUMERIC(12,2);          -- количество ценных бумаг
    v_cost NUMERIC(12,2);              -- ожидаемая сумма в валюте (при продаже)

    v_deposit_account_id INTEGER;
    v_user_id INTEGER;

    v_broker_operation_id INTEGER;     -- ID операции в истории бр. счёта (сумма 0 изначально)
	v_depo_operation_id INTEGER;

    c_sell_type_id CONSTANT INTEGER := 2;                   -- Тип предложения "Продажа"
    c_active_status_id CONSTANT INTEGER := 3;               -- Статус "Новое/Активное"
    c_approved_status_id CONSTANT INTEGER := 2;             -- Статус "Одобрено"
    c_rejected_status_id CONSTANT INTEGER := 1;             -- Статус "Отклонено"

    -- Типы операций депозитарного счёта
    c_depo_sell CONSTANT INTEGER := 2;       -- Списание ценных бумаг (при продаже)
    c_depo_unfreeze CONSTANT INTEGER := 4;        -- Разморозка ЦБ
	c_brokerage_operation_sell_id CONSTANT INTEGER := 5;
BEGIN
    -- 1. Получаем данные предложения и проверяем, что оно активно и на продажу
    SELECT
        p."ID предложения",
        p."ID брокерского счёта",
        p."ID ценной бумаги",
        p."Сумма" AS quantity,
        p."Сумма в валюте" AS cost,
        p."ID операции бр. счёта" AS broker_operation_id,
        ba."ID пользователя"
    INTO v_proposal
    FROM public."Предложение" p
    JOIN public."Брокерский счёт" ba ON ba."ID брокерского счёта" = p."ID брокерского счёта"
    WHERE p."ID предложения" = p_proposal_id
      AND p."ID типа предложения" = c_sell_type_id
      AND p."ID статуса предложения" = c_active_status_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Предложение на продажу с ID % не найдено или уже обработано', p_proposal_id;
    END IF;

    v_brokerage_account_id := v_proposal."ID брокерского счёта";
    v_security_id := v_proposal."ID ценной бумаги";
    v_quantity := v_proposal.quantity;
    v_cost := v_proposal.cost;
    v_broker_operation_id := v_proposal.broker_operation_id;
    v_user_id := v_proposal."ID пользователя";

    -- 2. Находим депозитарный счёт пользователя
    SELECT "ID депозитарного счёта"
    INTO v_deposit_account_id
    FROM public."Депозитарный счёт"
    WHERE "ID пользователя" = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'У пользователя с ID % не найден депозитарный счёт', v_user_id;
    END IF;

	-- Одобрение заявки на продажу ценных бумаг:
	-- 1. Пополнение брокерского счёта, который используется для покупки бумаг
	-- 2. Изменение статуса на "Одобрено".
	-- 3. В записи истории деп. счёта: заморожено -> продано
    IF p_verify THEN
        UPDATE public."История операций бр. счёта"
        SET "Сумма операции" = v_cost,
		"ID типа операции бр. счёта" = c_brokerage_operation_sell_id,
		"Время" = CURRENT_TIMESTAMP
        WHERE "ID операции бр. счёта" = v_broker_operation_id;

		UPDATE public."История операций деп. счёта"
		SET "ID типа операции деп. счёта" = c_depo_sell
		WHERE "ID операции бр. счёта" = v_broker_operation_id;

		UPDATE public."Брокерский счёт"
		SET "Баланс" = "Баланс" + v_cost
		WHERE "ID брокерского счёта" = v_brokerage_account_id;

		UPDATE public."Предложение"
        SET "ID статуса предложения" = c_approved_status_id
        WHERE "ID предложения" = p_proposal_id;

	-- Отклонение заявки на продажу ценных бумаг:
	-- 1. Разморозка замороженных ценных бумаг
	-- 2. Изменение статуса на "Отклонено".
    ELSE
        PERFORM 1
        FROM public."Баланс депозитарного счёта"
        WHERE "ID депозитарного счёта" = v_deposit_account_id
          AND "ID пользователя" = v_user_id
          AND "ID ценной бумаги" = v_security_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'В балансе депозитарного счёта отсутствует запись для ценной бумаги ID %', v_security_id;
        END IF;

        UPDATE public."Баланс депозитарного счёта"
        SET "Сумма" = "Сумма" + v_quantity
        WHERE "ID депозитарного счёта" = v_deposit_account_id
          AND "ID пользователя" = v_user_id
          AND "ID ценной бумаги" = v_security_id;

        INSERT INTO public."История операций деп. счёта" (
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
            v_quantity,
            CURRENT_TIMESTAMP,
            v_deposit_account_id,
            v_user_id,
            v_security_id,
            p_employee_id,
            v_broker_operation_id,
            v_brokerage_account_id,
            c_depo_unfreeze
        );

        UPDATE public."Предложение"
        SET "ID статуса предложения" = c_rejected_status_id
        WHERE "ID предложения" = p_proposal_id;
    END IF;

    RAISE NOTICE 'Предложение на продажу % успешно %', p_proposal_id, CASE WHEN p_verify THEN 'одобрено' ELSE 'отклонено' END;
END;
$BODY$;


CREATE OR REPLACE FUNCTION process_proposal(
    p_employee_id INTEGER,
    p_proposal_id INTEGER,
    p_verify BOOLEAN
)
RETURNS VOID AS $$
DECLARE
    v_current_status_id INTEGER;
    v_proposal_type_id INTEGER;
BEGIN
    -- 1. Проверка существования сотрудника
    PERFORM 1
    FROM public."Персонал"
    WHERE "ID сотрудника" = p_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Сотрудник с ID % не найден', p_employee_id;
    END IF;

    -- 2. Получаем тип и статус предложения, блокируем строку
    SELECT "ID типа предложения", "ID статуса предложения"
    INTO v_proposal_type_id, v_current_status_id
    FROM public."Предложение"
    WHERE "ID предложения" = p_proposal_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Предложение с ID % не найдено', p_proposal_id;
    END IF;

    -- 3. Проверка, что предложение ожидает верификации (статус ID = 3)
    IF v_current_status_id != 3 THEN
        RAISE EXCEPTION 'Предложение с ID % уже обработано или имеет недопустимый статус (текущий статус ID: %)',
            p_proposal_id, v_current_status_id;
    END IF;

    -- 4. В зависимости от типа предложения вызываем соответствующую функцию
    IF v_proposal_type_id = 1 THEN
        -- Покупка
        PERFORM process_buy_proposal(p_employee_id, p_proposal_id, p_verify);
    ELSIF v_proposal_type_id = 2 THEN
        -- Продажа
        PERFORM process_sell_proposal(p_employee_id, p_proposal_id, p_verify);
    ELSE
        RAISE EXCEPTION 'Неизвестный тип предложения ID % для предложения ID %',
            v_proposal_type_id, p_proposal_id;
    END IF;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.get_total_lot_price(
    p_security_id integer,
    p_lot_amount integer
)
    RETURNS numeric
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_price_per_share numeric;   -- цена одной акции в native валюте
    v_lot_size numeric;          -- размер лота
    v_total_price numeric;
BEGIN
    -- Защита от некорректного количества
    IF p_lot_amount <= 0 THEN
        RETURN NULL;
    END IF;

    -- Последняя цена одной акции
    v_price_per_share := public.get_security_value_native(p_security_id);

    IF v_price_per_share IS NULL THEN
        RETURN NULL;
    END IF;

    -- Размер лота из справочника
    SELECT "Размер лота"
    INTO v_lot_size
    FROM public."Список ценных бумаг"
    WHERE "ID ценной бумаги" = p_security_id;

    IF v_lot_size IS NULL OR v_lot_size <= 0 THEN
        RETURN NULL;
    END IF;

    -- Итоговая стоимость = цена_акции × размер_лота × количество_лотов
    v_total_price := v_price_per_share * v_lot_size * p_lot_amount;

    RETURN v_total_price;
END;
$BODY$;

CREATE OR REPLACE FUNCTION public.add_security(
    p_ticker character varying,
    p_isin character varying,
    p_lot_size numeric,
    p_price numeric,
    p_currency_id integer,
    p_has_dividends boolean
)
RETURNS integer
LANGUAGE 'plpgsql'
COST 100
VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_security_id INTEGER;
    r_deposit_account RECORD;
BEGIN
    -- 1. Проверка: размер лота должен быть строго больше нуля
    IF p_lot_size <= 0 THEN
        RAISE EXCEPTION 'Размер лота должен быть строго больше нуля (получено: %)', p_lot_size;
    END IF;

    -- 2. Проверка существования валюты
    PERFORM 1
    FROM public."Список валют"
    WHERE "ID валюты" = p_currency_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Валюта с ID % не найдена', p_currency_id;
    END IF;

    -- 3. Проверка уникальности ISIN
    PERFORM 1
    FROM public."Список ценных бумаг"
    WHERE "ISIN" = p_isin;

    IF FOUND THEN
        RAISE EXCEPTION 'Ценная бумага с ISIN % уже существует', p_isin;
    END IF;

    -- 4. Добавляем запись в "Список ценных бумаг"
    INSERT INTO public."Список ценных бумаг" (
        "Наименование",
        "Размер лота",
        "ISIN",
        "Выплата дивидендов",
        "ID валюты"
    ) VALUES (
        p_ticker,
        p_lot_size,
        p_isin,
        p_has_dividends,
        p_currency_id
    )
    RETURNING "ID ценной бумаги" INTO v_security_id;

    -- 5. Добавляем первую запись в историю цены
    INSERT INTO public."История цены" (
        "Дата",
        "Цена",
        "ID ценной бумаги"
    ) VALUES (
        CURRENT_DATE,
        p_price,
        v_security_id
    );

    -- 6. Цикл по всем депозитарным счетам и добавление нулевого баланса для новой бумаги
    FOR r_deposit_account IN
        SELECT "ID депозитарного счёта", "ID пользователя"
        FROM public."Депозитарный счёт"
    LOOP
        INSERT INTO public."Баланс депозитарного счёта" (
            "Сумма",
            "ID депозитарного счёта",
            "ID пользователя",
            "ID ценной бумаги"
        )
        VALUES (
            0.00,
            r_deposit_account."ID депозитарного счёта",
            r_deposit_account."ID пользователя",
            v_security_id
        );
    END LOOP;

    -- Возвращаем ID новой ценной бумаги
    RETURN v_security_id;
END;
$BODY$;

CREATE OR REPLACE FUNCTION public.change_stock_price( -- todo: convert to procedure
    p_stock_id integer,
    p_new_price numeric(12,2)
)
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
COST 100
AS $BODY$
DECLARE
    v_today DATE := CURRENT_DATE;
    v_exists INTEGER;
BEGIN
    -- Проверка существования ценной бумаги
    PERFORM 1
    FROM public."Список ценных бумаг"
    WHERE "ID ценной бумаги" = p_stock_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ценная бумага с ID % не найдена', p_stock_id;
    END IF;

    -- Проверка, что цена положительная
    IF p_new_price <= 0 THEN
        RAISE EXCEPTION 'Цена должна быть строго больше нуля (получено: %)', p_new_price;
    END IF;

    -- Проверяем, есть ли уже запись на сегодняшнюю дату
    SELECT 1
    INTO v_exists
    FROM public."История цены"
    WHERE "ID ценной бумаги" = p_stock_id
      AND "Дата" = v_today;

    IF FOUND THEN
        -- Если запись на сегодня уже есть — обновляем цену
        UPDATE public."История цены"
        SET "Цена" = p_new_price
        WHERE "ID ценной бумаги" = p_stock_id
          AND "Дата" = v_today;

        RAISE NOTICE 'Цена ценной бумаги ID % на дату % обновлена до %', p_stock_id, v_today, p_new_price;
    ELSE
        -- Если записи нет — добавляем новую
        INSERT INTO public."История цены" (
            "Дата",
            "Цена",
            "ID ценной бумаги"
        ) VALUES (
            v_today,
            p_new_price,
            p_stock_id
        );

        RAISE NOTICE 'Добавлена новая запись цены % для ценной бумаги ID % на дату %', p_new_price, p_stock_id, v_today;
    END IF;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE public.verify_user_passport(
    p_passport_id INTEGER,
    OUT p_success BOOLEAN,
    OUT p_error_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id INTEGER;
    v_deposit_account_id INTEGER;
    v_securities RECORD;
BEGIN
    -- Инициализируем OUT-параметры явно (обязательно, так как DEFAULT запрещён)
    p_success := NULL;
    p_error_message := NULL;

    -- Находим ID пользователя по паспорту
    SELECT "ID пользователя" INTO v_user_id
    FROM public."Паспорт"
    WHERE "ID паспорта" = p_passport_id;

    IF NOT FOUND THEN
        p_error_message := format('Паспорт с ID %s не найден', p_passport_id);
        p_success := FALSE;
        RETURN;
    END IF;

    -- Проверяем, есть ли уже депозитарный счёт у пользователя
    SELECT "ID депозитарного счёта" INTO v_deposit_account_id
    FROM public."Депозитарный счёт"
    WHERE "ID пользователя" = v_user_id;

    IF FOUND THEN
        p_error_message := format('У пользователя с ID %s уже существует депозитарный счёт. Повторная верификация паспорта невозможна.', v_user_id);
        p_success := FALSE;
        RETURN;
    END IF;

    -- Создаём новый депозитарный счёт
    INSERT INTO public."Депозитарный счёт" (
        "Номер депозитарного договора",
        "Дата открытия",
        "ID пользователя"
    )
    VALUES (
        'Договор № ' || to_char(current_date, 'YYYYMMDD') || '-' || v_user_id,
        current_date,
        v_user_id
    )
    RETURNING "ID депозитарного счёта" INTO v_deposit_account_id;

    -- Создаём записи в таблице баланса для каждой ценной бумаги с нулевым остатком
    FOR v_securities IN
        SELECT "ID ценной бумаги"
        FROM public."Список ценных бумаг"
    LOOP
        INSERT INTO public."Баланс депозитарного счёта" (
            "Сумма",
            "ID депозитарного счёта",
            "ID пользователя",
            "ID ценной бумаги"
        )
        VALUES (
            0.00,
            v_deposit_account_id,
            v_user_id,
            v_securities."ID ценной бумаги"
        );
    END LOOP;

    -- Помечаем паспорт как актуальный после успешной верификации
    UPDATE public."Паспорт"
    SET "Актуальность" = true
    WHERE "ID паспорта" = p_passport_id;

    -- Обновляем статус верификации пользователя
    UPDATE public."Пользователь"
    SET "ID статуса верификации" = 2
    WHERE "ID пользователя" = v_user_id;

    -- Успешное завершение
    p_success := TRUE;

EXCEPTION
    WHEN OTHERS THEN
        p_error_message := SQLERRM;
        p_success := FALSE;
END;
$$;


CREATE OR REPLACE PROCEDURE register_user(
    p_login VARCHAR(30),
    p_password VARCHAR(60),
    p_email VARCHAR(40),
    OUT p_user_id INTEGER,
    OUT p_error_message TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Инициализируем OUT-параметры
    p_user_id := NULL;
    p_error_message := NULL;

    -- Проверяем уникальность логина
    PERFORM 1 FROM public."Пользователь" WHERE "Логин" = p_login;
    IF FOUND THEN
        p_error_message := 'Логин уже занят';
        RETURN;
    END IF;

    -- Проверяем уникальность email
    PERFORM 1 FROM public."Пользователь" WHERE "Электронная почта" = p_email;
    IF FOUND THEN
        p_error_message := 'Email уже зарегистрирован';
        RETURN;
    END IF;

    -- Принимаем уже захэшированный пароль
    -- v_hashed_password не нужен, можно использовать p_password напрямую

    -- Создаём пользователя
    INSERT INTO public."Пользователь" (
        "Электронная почта",
        "Дата регистрации",
        "Логин",
        "Пароль",
        "ID статуса верификации",
        "ID статуса блокировки"
    )
    VALUES (
        p_email,
        CURRENT_DATE,
        p_login,
        p_password,
        1,  -- начальный статус верификации
        1   -- начальный статус блокировки (не заблокирован)
    )
    RETURNING "ID пользователя" INTO p_user_id;

    -- Успех — p_error_message остаётся NULL

EXCEPTION
    WHEN OTHERS THEN
        p_error_message := SQLERRM;
        p_user_id := NULL;
END;
$$;

CREATE OR REPLACE PROCEDURE register_staff(
    p_login VARCHAR(30),
    p_password VARCHAR(60),
    p_contract_number VARCHAR(40),
    p_rights_level_id INTEGER,
    p_employment_status_id INTEGER,
    OUT p_staff_id INTEGER,
    OUT p_error_message TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Инициализируем OUT-параметры
    p_staff_id := NULL;
    p_error_message := NULL;

    -- Проверяем уникальность логина
    PERFORM 1 FROM public."Персонал" WHERE "Логин" = p_login;
    IF FOUND THEN
        p_error_message := 'Логин уже занят';
        RETURN;
    END IF;

    -- Проверяем уникальность номера договора
    PERFORM 1 FROM public."Персонал" WHERE "Номер трудового договора" = p_contract_number;
    IF FOUND THEN
        p_error_message := 'Номер договора уже занят';
        RETURN;
    END IF;

    -- Создаём сотрудника
    INSERT INTO public."Персонал" (
        "Номер трудового договора",
        "Логин",
        "Пароль",
        "ID статуса трудоустройства",
        "ID уровня прав"
    )
    VALUES (
        p_contract_number,
        p_login,
        p_password,
        p_employment_status_id,
        p_rights_level_id
    )
    RETURNING "ID сотрудника" INTO p_staff_id;

    -- Успех — p_error_message остаётся NULL

EXCEPTION
    WHEN OTHERS THEN
        p_error_message := SQLERRM;
        p_staff_id := NULL;
END;
$$;

CREATE OR REPLACE PROCEDURE public.change_currency_info(
    IN p_currency_id integer,
    IN p_new_code character varying,
    IN p_new_symbol character varying,
    IN p_new_rate_to_ruble numeric,
    OUT p_error_message character varying)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_archived BOOLEAN;
    v_currency_exists BOOLEAN;
    v_current_code character(3);
    v_current_symbol character varying(10);
BEGIN
    -- Инициализируем выходной параметр
    p_error_message := NULL;

    -- Проверка: p_currency_id не может быть NULL
    IF p_currency_id IS NULL THEN
        p_error_message := 'ID валюты не может быть NULL';
        RETURN;
    END IF;

    -- Проверяем, существует ли валюта с таким ID
    SELECT "Статус архивации", "Код", "Символ"
    INTO v_archived, v_current_code, v_current_symbol
    FROM public."Список валют"
    WHERE "ID валюты" = p_currency_id;

    -- Сохраняем результат проверки существования
    v_currency_exists := FOUND;

    -- Проверка 1: Существование валюты
    IF NOT v_currency_exists THEN
        p_error_message := format('Валюта с ID %s не существует', p_currency_id);
        RETURN;
    END IF;

    -- Проверка 2: Статус архивации
    IF v_archived THEN
        p_error_message := format('Валюта с ID %s находится в архиве и не может быть изменена', p_currency_id);
        RETURN;
    END IF;

    -- Проверка: если все IN параметры (кроме ID) NULL, то нечего обновлять
    IF p_new_code IS NULL AND p_new_symbol IS NULL AND p_new_rate_to_ruble IS NULL THEN
        p_error_message := 'Не указано ни одного параметра для изменения';
        RETURN;
    END IF;

    BEGIN
        -- Обновляем код и символ валюты только если параметры не NULL
        -- Определяем, какие поля нужно обновлять
        IF p_new_code IS NOT NULL OR p_new_symbol IS NOT NULL THEN
            UPDATE public."Список валют"
            SET
                "Код" = CASE
                    WHEN p_new_code IS NOT NULL THEN UPPER(TRIM(p_new_code))::character(3)
                    ELSE v_current_code
                END,
                "Символ" = CASE
                    WHEN p_new_symbol IS NOT NULL THEN TRIM(p_new_symbol)
                    ELSE v_current_symbol
                END
            WHERE "ID валюты" = p_currency_id;
        END IF;

        -- Обновляем (или добавляем) курс на текущую дату только если p_new_rate_to_ruble не NULL
        IF p_new_rate_to_ruble IS NOT NULL THEN
            -- Дополнительная проверка: курс должен быть положительным
            IF p_new_rate_to_ruble <= 0 THEN
                p_error_message := format('Курс валюты должен быть положительным числом, получено: %s', p_new_rate_to_ruble);
                RETURN;
            END IF;

            INSERT INTO public.currency_rate (currency_id, rate, rate_date)
            VALUES (p_currency_id, p_new_rate_to_ruble, CURRENT_DATE)
            ON CONFLICT (currency_id, rate_date)
            DO UPDATE SET rate = EXCLUDED.rate;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Перехватываем любые исключения (включая от триггеров) и возвращаем сообщение об ошибке
            p_error_message := format('Ошибка при обновлении валюты: %s', SQLERRM);
            RETURN;
    END;

    -- Если все успешно, p_error_message остается NULL

END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.archive_currency(
    IN currency_id integer,
    OUT p_error_message character varying)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_currency_exists BOOLEAN;
    v_is_already_archived BOOLEAN;
    v_used_in_accounts BOOLEAN;
    v_used_in_securities BOOLEAN;
    v_accounts_count INTEGER;
    v_securities_count INTEGER;
BEGIN
    -- Инициализируем выходной параметр
    p_error_message := NULL;

    -- Проверяем, существует ли валюта с таким ID
    SELECT EXISTS(
        SELECT 1
        FROM public."Список валют"
        WHERE "ID валюты" = currency_id
    ) INTO v_currency_exists;

    -- Проверка 1: Существование валюты
    IF NOT v_currency_exists THEN
        p_error_message := format('Валюта с ID %s не существует', currency_id);
        RETURN;
    END IF;

    -- Проверяем, не архивирована ли валюта уже
    SELECT "Статус архивации"
    INTO v_is_already_archived
    FROM public."Список валют"
    WHERE "ID валюты" = currency_id;

    -- Проверка 2: Проверка статуса архивации
    IF v_is_already_archived THEN
        p_error_message := format('Валюта с ID %s уже находится в архиве', currency_id);
        RETURN;
    END IF;

    -- Проверка использования в таблице "Брокерский счёт"
    SELECT EXISTS(
        SELECT 1
        FROM public."Брокерский счёт"
        WHERE "ID валюты" = currency_id
    ) INTO v_used_in_accounts;

    IF v_used_in_accounts THEN
        -- Получаем количество для информационного сообщения
        SELECT COUNT(*)
        INTO v_accounts_count
        FROM public."Брокерский счёт"
        WHERE "ID валюты" = currency_id;

        p_error_message := format(
            'Валюта с ID %s используется в %s брокерском(их) счете(ах). Архивация невозможна.',
            currency_id, v_accounts_count
        );
        RETURN;
    END IF;

    -- Проверка использования в таблице "Список ценных бумаг"
    SELECT EXISTS(
        SELECT 1
        FROM public."Список ценных бумаг"
        WHERE "ID валюты" = currency_id
    ) INTO v_used_in_securities;

    IF v_used_in_securities THEN
        -- Получаем количество для информационного сообщения
        SELECT COUNT(*)
        INTO v_securities_count
        FROM public."Список ценных бумаг"
        WHERE "ID валюты" = currency_id;

        p_error_message := format(
            'Валюта с ID %s используется в %s ценной(ых) бумаге(ах). Архивация невозможна.',
            currency_id, v_securities_count
        );
        RETURN;
    END IF;

    BEGIN
        -- Обновляем статус архивации валюты
        UPDATE public."Список валют"
        SET "Статус архивации" = TRUE
        WHERE "ID валюты" = currency_id;

        -- Проверяем, что обновление прошло успешно
        IF NOT FOUND THEN
            p_error_message := format('Не удалось обновить статус архивации для валюты с ID %s', currency_id);
            RETURN;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Перехватываем любые исключения (включая от триггера) и возвращаем сообщение об ошибке
            p_error_message := format('Ошибка при архивации валюты: %s', SQLERRM);
            RETURN;
    END;

    -- Если все успешно, p_error_message остается NULL
    -- Можно добавить логирование успешной операции, если необходимо
    RAISE NOTICE 'Валюта с ID %s успешно архивирована', currency_id;

END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.add_currency(
    p_code character varying,
    p_symbol character varying,
    p_rate_to_ruble numeric,
    OUT p_currency_id integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_currency_id INTEGER;
BEGIN
    p_currency_id := NULL;
    p_error_message := NULL;

    BEGIN
        INSERT INTO public."Список валют" ("Код", "Символ", "Статус архивации")
        VALUES (
            UPPER(TRIM(p_code)),
            TRIM(p_symbol),
            FALSE
        )
        RETURNING "ID валюты" INTO v_currency_id;

        INSERT INTO public.currency_rate (currency_id, rate, rate_date)
        VALUES (v_currency_id, p_rate_to_ruble, CURRENT_DATE);

        p_currency_id := v_currency_id;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
            p_currency_id := NULL;
    END;
END;
$BODY$;

call add_currency('usd', '$', 100, null, null);
call add_currency('eur', '€', 120, null, null);

SELECT add_bank('ПАО Сбербанк', '7707083893', '1027700132195', '044525225', '2036-11-27'::DATE);
SELECT add_bank('Банк ВТБ (ПАО)', '7702070139', '1027700031594', '044525187', '2032-10-17'::DATE);
SELECT add_bank('АО "Альфа-Банк"', '7728168971', '1027700067328', '044525593', '2031-12-31'::DATE);
SELECT add_bank('ПАО Банк "ФК Открытие"', '7706092528', '1027700389635', '044525297', '2029-08-14'::DATE);
SELECT add_bank('АО "Тинькофф Банк"', '7710140679', '1027739642281', '044525974', '2030-06-22'::DATE);
SELECT add_bank('ПАО "Росбанк"', '7736018783', '1027739026157', '044525256', '2033-03-15'::DATE);
SELECT add_bank('АО "Райффайзенбанк"', '7744000303', '1027700159232', '044525700', '2030-12-31'::DATE);
SELECT add_bank('ПАО "Совкомбанк"', '4401144210', '1047796016277', '044525360', '2031-07-10'::DATE);

select add_security('SBER', 'SBER', 2, 100, 1, true);
select add_security('AFLT', 'AFLT', 3, 10, 1, false);
select add_security('BTC', 'BTC', 1, 100000, 2, true);
select add_security('EURS', 'EURS', 2, 1, 3, true);

-- pass: 123456
CALL register_staff('admin', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '8800', 2, 1, NULL, NULL);
CALL register_staff('admin2', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '88000', 2, 1, NULL, NULL);
CALL register_staff('broker', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '8801', 3, 1, NULL, NULL);
CALL register_staff('verifier', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '8802', 4, 1, NULL, NULL);

call register_user('1', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '12345@example.com', null, null); -- password: 123456
select submit_passport(1, 'Медведев', 'Даниил', 'Андреевич', '0114', '439954', 'м', '2004-01-01', 'г. Барнаул', 'г. Барнаул', '2020-01-01', 'ГУ МВД РФ');
call verify_user_passport(1, null, null);

call register_user('2', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', 'email2@example.com', null, null);
select submit_passport(2, 'Иванов', 'Иван', 'Иванович', '0113', '439957', 'м', '2004-01-01', 'г. Барнаул', 'г. Барнаул', '2020-01-01', 'ГУ МВД РФ');

call register_user('3', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', 'email3@example.com', null, null);

select add_brokerage_account(1, 1, 1);
select add_brokerage_account(1, 3, 2);
select add_brokerage_account(1, 2, 3);
