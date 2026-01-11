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
          AND n.nspname NOT LIKE 'pg_toast%s'
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

CREATE OR REPLACE FUNCTION public.is_valid_isin(p_isin text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_isin text;
    v_expanded text := '';
    v_char char;
    v_num int;
    v_sum int := 0;
    v_alt boolean := false;
BEGIN
    IF p_isin IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Нормализация
    v_isin := upper(trim(p_isin));

    -- Формат: 12 символов, первые 2 буквы
    IF length(v_isin) != 12
       OR v_isin !~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$'
    THEN
        RETURN FALSE;
    END IF;

    -- Расширяем ISIN (буквы → числа)
    FOR i IN 1..length(v_isin) LOOP
        v_char := substr(v_isin, i, 1);

        IF v_char ~ '[A-Z]' THEN
            v_expanded := v_expanded || (ascii(v_char) - 55);
        ELSE
            v_expanded := v_expanded || v_char;
        END IF;
    END LOOP;

    -- Алгоритм Луна (справа налево)
    FOR i IN reverse length(v_expanded)..1 LOOP
        v_num := substr(v_expanded, i, 1)::int;

        IF v_alt THEN
            v_num := v_num * 2;
            IF v_num > 9 THEN
                v_num := v_num - 9;
            END IF;
        END IF;

        v_sum := v_sum + v_num;
        v_alt := NOT v_alt;
    END LOOP;

    RETURN (v_sum % 10 = 0);
END;
$$;


CREATE OR REPLACE FUNCTION public.validate_russian_inn_legal(p_inn character varying)
    RETURNS boolean
    LANGUAGE 'plpgsql'
    IMMUTABLE
AS $BODY$
DECLARE
    v_inn_clean character varying;
    v_sum INTEGER := 0;
    v_check_digit INTEGER;
    v_coeff CONSTANT INTEGER[] := ARRAY[2,4,10,3,5,9,4,6,8];
BEGIN
    -- Убираем пробелы и дефисы
    v_inn_clean := replace(replace(p_inn, ' ', ''), '-', '');

    -- ИНН юридического лица строго 10 цифр
    IF length(v_inn_clean) <> 10 THEN
        RETURN FALSE;
    END IF;

    -- Только цифры
    IF v_inn_clean !~ '^\d{10}$' THEN
        RETURN FALSE;
    END IF;

    -- Вычисляем контрольную сумму
    v_sum := 0;
    FOR i IN 1..9 LOOP
        v_sum := v_sum + substring(v_inn_clean FROM i FOR 1)::integer * v_coeff[i];
    END LOOP;

    v_check_digit := (v_sum % 11) % 10;

    -- Сравниваем с 10-й цифрой
    RETURN v_check_digit = substring(v_inn_clean FROM 10 FOR 1)::integer;
END;
$BODY$;

CREATE OR REPLACE FUNCTION public.validate_russian_inn_individual(p_inn character varying)
    RETURNS boolean
    LANGUAGE 'plpgsql'
    IMMUTABLE
AS $BODY$
DECLARE
    v_inn_clean character varying;
    v_sum INTEGER := 0;
    v_check_digit INTEGER;
    v_coeff INTEGER[];
BEGIN
    -- Убираем пробелы и дефисы
    v_inn_clean := replace(replace(p_inn, ' ', ''), '-', '');

    -- ИНН физлица строго 12 цифр
    IF length(v_inn_clean) <> 12 THEN
        RETURN FALSE;
    END IF;

    -- Только цифры
    IF v_inn_clean !~ '^\d{12}$' THEN
        RETURN FALSE;
    END IF;

    -- Первая контрольная сумма (11-я цифра)
    v_coeff := ARRAY[7, 2, 4, 10, 3, 5, 9, 4, 6, 8];
    v_sum := 0;
    FOR i IN 1..10 LOOP
        v_sum := v_sum + substring(v_inn_clean FROM i FOR 1)::integer * v_coeff[i];
    END LOOP;
    v_check_digit := (v_sum % 11) % 10;

    IF v_check_digit != substring(v_inn_clean FROM 11 FOR 1)::integer THEN
        RETURN FALSE;
    END IF;

    -- Вторая контрольная сумма (12-я цифра)
    v_coeff := ARRAY[3, 7, 2, 4, 10, 3, 5, 9, 4, 6, 8];
    v_sum := 0;
    FOR i IN 1..11 LOOP
        v_sum := v_sum + substring(v_inn_clean FROM i FOR 1)::integer * v_coeff[i];
    END LOOP;
    v_check_digit := (v_sum % 11) % 10;

    RETURN v_check_digit = substring(v_inn_clean FROM 12 FOR 1)::integer;
END;
$BODY$;

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
        RAISE EXCEPTION 'Триггер вызван на неподдерживаемой таблице %s', TG_TABLE_NAME;
    END IF;

    IF amount_value < 0 THEN
        RAISE EXCEPTION 'Сумма не может быть отрицательной! Попытка установить значение %s (таблица: %s, ID: %s)'
            , amount_value
            , TG_TABLE_NAME
            , account_id;
    END IF;

    RETURN NEW;
END;
$$;

-- Create tables section -------------------------------------------------

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
WITH (autovacuum_enabled=true);
ALTER TABLE "Паспорт" ADD CONSTRAINT "Unique_Identifier16" PRIMARY KEY ("ID паспорта","ID пользователя");

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

CREATE TABLE "Список ценных бумаг"
(
  "ID ценной бумаги" Serial NOT NULL,
  "Наименование" Character varying(120) NOT NULL,
  "Размер лота" Numeric(12,2) NOT NULL,
  "ISIN" Character varying(40) NOT NULL,
  "ID валюты" Integer NOT NULL,
  "Статус архивации" BOOLEAN NOT NULL DEFAULT FALSE
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship51" ON "Список ценных бумаг" ("ID валюты");
ALTER TABLE "Список ценных бумаг" ADD CONSTRAINT "Unique_Identifier5" PRIMARY KEY ("ID ценной бумаги");

ALTER TABLE public."Список ценных бумаг"
ADD CONSTRAINT chk_isin_valid
CHECK (is_valid_isin("ISIN"));

CREATE OR REPLACE FUNCTION public.trg_validate_security_before_insert()
RETURNS TRIGGER AS
$BODY$
BEGIN
    -- Автоматический перевод ISIN в верхний регистр
    NEW."ISIN" = UPPER(NEW."ISIN");

    -- Валидация тикера (Наименование): только латинские буквы и автоматический перевод в верхний регистр
    IF NEW."Наименование" IS NOT NULL AND NEW."Наименование" != '' THEN
        -- Проверка на наличие только латинских букв
        IF NEW."Наименование" !~ '^[A-Za-z]+$' THEN
            RAISE EXCEPTION 'Тикер должен содержать только латинские буквы (получено: %)', NEW."Наименование";
        END IF;

        -- Автоматический перевод в верхний регистр
        NEW."Наименование" = UPPER(NEW."Наименование");
    END IF;

    -- Валидация размера лота
    IF NEW."Размер лота" <= 0 THEN
        RAISE EXCEPTION 'Размер лота должен быть строго больше нуля (получено: %)', NEW."Размер лота";
    END IF;

    -- Проверка существования валюты
    PERFORM 1 FROM public."Список валют" WHERE "ID валюты" = NEW."ID валюты";
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Валюта с ID %s не найдена', NEW."ID валюты";
    END IF;

    -- Проверка уникальности ISIN среди неархивированных записей
    PERFORM 1 FROM public."Список ценных бумаг"
    WHERE "Статус архивации" = FALSE AND "ISIN" = NEW."ISIN"
    AND "ID ценной бумаги" IS DISTINCT FROM NEW."ID ценной бумаги";
    IF FOUND THEN
        RAISE EXCEPTION 'Неархивированная ценная бумага с ISIN % уже существует', NEW."ISIN";
    END IF;

    -- Проверка уникальности тикера среди неархивированных записей
    PERFORM 1 FROM public."Список ценных бумаг"
    WHERE "Статус архивации" = FALSE AND "Наименование" = NEW."Наименование"
    AND "ID ценной бумаги" IS DISTINCT FROM NEW."ID ценной бумаги";
    IF FOUND THEN
        RAISE EXCEPTION 'Неархивированная ценная бумага с тикером % уже существует', NEW."Наименование";
    END IF;

    RETURN NEW;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;

CREATE TRIGGER trg_validate_security_before_insert_or_update
    BEFORE INSERT OR UPDATE ON public."Список ценных бумаг"
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_validate_security_before_insert();

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
  "ИНН" Character varying(30) NOT NULL UNIQUE,
  "БИК" Character varying(30) NOT NULL,
  "ID банка" Integer NOT NULL,
  "ID пользователя" Integer NOT NULL,
  "ID валюты" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship22" ON "Брокерский счёт" ("ID банка");
CREATE INDEX "IX_Relationship25" ON "Брокерский счёт" ("ID валюты");
CREATE INDEX "IX_Relationship52" ON "Брокерский счёт" ("ID пользователя");
ALTER TABLE "Брокерский счёт" ADD CONSTRAINT "Unique_Identifier12" PRIMARY KEY ("ID брокерского счёта");

CREATE OR REPLACE TRIGGER trg_prevent_negative_balance
    BEFORE INSERT OR UPDATE OF "Баланс"
    ON public."Брокерский счёт"
    FOR EACH ROW
    EXECUTE FUNCTION prevent_negative_balance();

-- Триггерная функция для валидации ИНН физического лица в брокерском счёте
CREATE OR REPLACE FUNCTION public.trg_validate_inn_individual()
    RETURNS trigger
    LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    IF NEW."ИНН" IS NULL OR TRIM(NEW."ИНН") = '' THEN
        RAISE EXCEPTION 'ИНН не может быть пустым'
            USING ERRCODE = 'not_null_violation';
    END IF;

    IF length(replace(replace(NEW."ИНН", ' ', ''), '-', '')) <> 12 THEN
        RAISE EXCEPTION 'ИНН физического лица должен содержать ровно 12 цифр (получено: %)', NEW."ИНН"
            USING ERRCODE = 'check_violation';
    END IF;

    IF NOT validate_russian_inn_individual(NEW."ИНН") THEN
        RAISE EXCEPTION 'Некорректный ИНН физического лица: %', NEW."ИНН"
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION public.trg_validate_inn_individual()
    OWNER TO postgres;

-- Триггер на таблицу "Брокерский счёт"
CREATE OR REPLACE TRIGGER trg_validate_inn_individual
    BEFORE INSERT OR UPDATE OF "ИНН"
    ON public."Брокерский счёт"
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_validate_inn_individual();

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

CREATE TABLE "Тип операции брокерского счёта"
(
  "ID типа операции бр. счёта" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Тип операции брокерского счёта" ADD CONSTRAINT "Unique_Identifier2" PRIMARY KEY ("ID типа операции бр. счёта");

CREATE TABLE "Список валют"
(
  "ID валюты" Serial NOT NULL,
  "Код" Char(3) NOT NULL,
  "Символ" Character varying(10) NOT NULL,
  "Статус архивации" BOOLEAN NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Список валют" ADD CONSTRAINT "Unique_Identifier6" PRIMARY KEY ("ID валюты");

INSERT INTO "Список валют" ("Код", "Символ", "Статус архивации")
VALUES ('RUB', '₽', false);

CREATE OR REPLACE FUNCTION validate_currency_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Запрещаем УДАЛЕНИЕ записи с ID = 1
    IF TG_OP = 'DELETE' AND OLD."ID валюты" = 1 THEN
        RAISE EXCEPTION 'Удаление базовой валюты (RUB) с ID = 1 запрещено'
              USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'UPDATE' AND OLD."ID валюты" = 1 THEN
        RAISE EXCEPTION 'Изменение базовой валюты (RUB) с ID = 1 запрещено'
              USING ERRCODE = 'check_violation';
    END IF;

    -- Запрещаем изменение ID валюты для любой записи
    IF TG_OP = 'UPDATE' AND OLD."ID валюты" != NEW."ID валюты" THEN
        RAISE EXCEPTION 'Изменение поля "ID валюты" запрещено'
              USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'INSERT' AND NEW."ID валюты" = 1 THEN
        RAISE EXCEPTION 'Создание записи с ID валюты = 1 запрещено. Этот ID зарезервирован для системной валюты'
              USING ERRCODE = 'check_violation';
    END IF;

    -- Приводим код к верхнему регистру
    NEW."Код" := UPPER(TRIM(NEW."Код"));

    IF NEW."Код" !~ '^[A-Z]{3}$' THEN
        RAISE EXCEPTION 'Поле "Код" должно состоять из 3 латинских букв в верхнем регистре (A-Z). Полученное значение: "%"', NEW."Код";
    END IF;

    IF NEW."Символ" ~ '\s' OR CHARACTER_LENGTH(NEW."Символ") = 0 THEN
        RAISE EXCEPTION 'Поле "Символ" не должно быть пустым или содержать пробелов, табуляций и других whitespace-символов';
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

CREATE TABLE "Тип предложения"
(
  "ID типа предложения" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Тип предложения" ADD CONSTRAINT "Unique_Identifier3" PRIMARY KEY ("ID типа предложения");

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

CREATE TABLE "Банк"
(
  "ID банка" Serial NOT NULL,
  "Наименование" Character varying(120) NOT NULL UNIQUE,
  "ИНН" Character varying(40) NOT NULL UNIQUE,
  "ОГРН" Character varying(40) NOT NULL UNIQUE,
  "БИК" Character varying(40) NOT NULL UNIQUE,
  "Срок действия лицензии" Date NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Банк" ADD CONSTRAINT "Unique_Identifier8" PRIMARY KEY ("ID банка");

CREATE OR REPLACE FUNCTION public.trg_validate_bank_before_insert_or_update()
RETURNS TRIGGER AS
$BODY$
BEGIN
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
    IF length(replace(replace(NEW."ИНН", ' ', ''), '-', '')) = 10 THEN
        IF NOT validate_russian_inn_legal(NEW."ИНН") THEN
            RAISE EXCEPTION 'Некорректный ИНН юридического лица: %', NEW."ИНН"
                USING ERRCODE = 'check_violation';
        END IF;
    ELSIF length(replace(replace(NEW."ИНН", ' ', ''), '-', '')) = 12 THEN
        RAISE EXCEPTION 'Для банков разрешён только 10-значный ИНН юридического лица (получено 12 цифр: %)', NEW."ИНН";
    ELSE
        RAISE EXCEPTION 'ИНН банка должен состоять ровно из 10 цифр (получено: %)', NEW."ИНН";
    END IF;

    IF NEW."ОГРН" !~ '^\d{13}$|^\d{15}$' THEN
        RAISE EXCEPTION 'ОГРН должен состоять из 13 или 15 цифр (получено: %)', NEW."ОГРН";
    END IF;

    IF NEW."Срок действия лицензии" < CURRENT_DATE THEN
        RAISE EXCEPTION 'Срок действия лицензии не может быть в прошлом (указана дата: %)', NEW."Срок действия лицензии";
    END IF;

    RETURN NEW;
END;
$BODY$
LANGUAGE plpgsql VOLATILE;

CREATE TRIGGER trg_bank_validation
    BEFORE INSERT OR UPDATE ON public."Банк"
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_validate_bank_before_insert_or_update();

CREATE TABLE "История цены"
(
  "ID зап. ист. цены" Serial NOT NULL,
  "Дата" Date NOT NULL,
  "Цена" Numeric(12,2) NOT NULL,
  "ID ценной бумаги" Integer NOT NULL,
  UNIQUE ("Дата", "ID ценной бумаги")
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship50" ON "История цены" ("ID ценной бумаги");
ALTER TABLE "История цены" ADD CONSTRAINT "Unique_Identifier15" PRIMARY KEY ("ID зап. ист. цены");


CREATE OR REPLACE FUNCTION check_history_price_non_negative()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW."Цена" <= 0 THEN
        RAISE EXCEPTION 'Цена должна быть положительной. Полученное значение: %', NEW."Цена";
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
    UNIQUE (currency_id, rate_date)
);

CREATE OR REPLACE FUNCTION check_currency_rate_positive()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.rate <= 0 THEN
        RAISE EXCEPTION 'Курс валюты должен быть положительным числом. Получено: %s', NEW.rate;
    END IF;

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
('Отклонено'),
('Одобрено'),
('На рассмотрении');

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

CREATE OR REPLACE FUNCTION get_user_verification_status(user_id integer)
RETURNS boolean AS $$
DECLARE
    verification_status_text varchar(20);
BEGIN
    SELECT v."Статус верификации" INTO verification_status_text
    FROM "Пользователь" u
    INNER JOIN "Статус верификации" v ON u."ID статуса верификации" = v."ID статуса верификации"
    WHERE u."ID пользователя" = user_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    RETURN verification_status_text = 'Подтверждён';
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_user_securities(user_id INT)
RETURNS TABLE (
    security_name TEXT,
    lot_size NUMERIC(12,2),
    isin TEXT,
    amount DECIMAL,
    currency_code CHAR(3),
    currency_symbol VARCHAR(10)
) AS $$
    SELECT
        s."Наименование" AS security_name,
        s."Размер лота" AS lot_size,
        s."ISIN" AS isin,
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
    RETURNS TABLE(
    id integer,
    "offer_type" text,
    "security_name" text,
    "security_isin" text,
    "quantity" numeric,
    "proposal_status" integer
    )
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
    SELECT
		p."ID предложения" AS "id",
        t."Тип" AS "offer_type",
        b."Наименование" AS "security_name",
        b."ISIN" AS "security_isin",
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


CREATE OR REPLACE FUNCTION public.get_exchange_stocks()
RETURNS TABLE (
    id              INTEGER,
    ticker          VARCHAR,
    isin            VARCHAR,
    lot_size        NUMERIC(12,2),
    price           NUMERIC(12,2),
    currency        VARCHAR(10),
    change          NUMERIC(6,2),
    is_archived     BOOLEAN
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
        s."ISIN" AS isin,
        s."Размер лота" AS lot_size,

        lp."Цена" AS last_price,
        prev."Цена" AS prev_price,

        c."Символ" AS currency,
        s."Статус архивации" AS is_archived

    FROM "Список ценных бумаг" s

    LEFT JOIN last_prices lp
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
    isin,
    lot_size,

    COALESCE(last_price, 0) AS price,
    currency,

    CASE
        WHEN prev_price IS NULL OR prev_price = 0 OR last_price IS NULL THEN 0
        ELSE ROUND(
            ((last_price - prev_price) / prev_price) * 100,
            2
        )
    END AS change,

    is_archived
FROM prices
ORDER BY isin;

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
    currency1_archived BOOLEAN;
    currency2_archived BOOLEAN;
BEGIN
    -- Проверяем, не являются ли валюты архивными
    SELECT "Статус архивации" INTO currency1_archived
    FROM "Список валют"
    WHERE "ID валюты" = p_currency1;

    SELECT "Статус архивации" INTO currency2_archived
    FROM "Список валют"
    WHERE "ID валюты" = p_currency2;

    -- Если одна из валют не найдена или архивна, возвращаем 0
    IF currency1_archived IS NULL OR currency1_archived = TRUE OR
       currency2_archived IS NULL OR currency2_archived = TRUE THEN
        RETURN 0.0;
    END IF;

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
            RAISE EXCEPTION 'Нет курса для валюты %s ни на %s, ни до этой даты',
                            p_currency1, p_date;
        END IF;

        -- Для удобства можно вывести предупреждение, если не точная дата
        IF found_date < p_date THEN
            RAISE NOTICE 'Для валюты %s использован курс на %s (ближайший предыдущий)',
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
            RAISE EXCEPTION 'Нет курса для валюты %sни на %, ни до этой даты',
                            p_currency2, p_date;
        END IF;

        IF found_date < p_date THEN
            RAISE NOTICE 'Для валюты %s использован курс на %s (ближайший предыдущий)',
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

CREATE OR REPLACE FUNCTION public.change_brokerage_account_balance(
    p_account_id integer,
    p_amount numeric,
    p_brokerage_operation_type integer,
    p_staff_id integer,
    OUT p_operation_id integer,
    OUT p_error_message text
)
RETURNS record
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC(12,2);
BEGIN
    p_operation_id := NULL;
    p_error_message := NULL;

    -- Проверяем тип операции
    PERFORM 1
    FROM public."Тип операции брокерского счёта"
    WHERE "ID типа операции бр. счёта" = p_brokerage_operation_type;

    IF NOT FOUND THEN
        p_error_message := format(
            'Тип операции брокерского счёта с ID %s не найден',
            p_brokerage_operation_type
        );
        RETURN;
    END IF;

    -- Блокируем счёт
    SELECT "Баланс"
    INTO v_current_balance
    FROM public."Брокерский счёт"
    WHERE "ID брокерского счёта" = p_account_id
    FOR UPDATE;

    IF NOT FOUND THEN
        p_error_message := format(
            'Счёт с ID %s не найден',
            p_account_id
        );
        RETURN;
    END IF;

    -- Проверка на отрицательный баланс
    IF v_current_balance + p_amount < 0 THEN
        p_error_message := format(
            'Недостаточно средств на счёте (текущий баланс: %s, запрос: %s)',
            v_current_balance,
            abs(p_amount)
        );
        RETURN;
    END IF;

    -- Обновляем баланс
    UPDATE public."Брокерский счёт"
    SET "Баланс" = "Баланс" + p_amount
    WHERE "ID брокерского счёта" = p_account_id;

    -- Пишем историю операций
    INSERT INTO public."История операций бр. счёта" (
        "Сумма операции",
        "Время",
        "ID брокерского счёта",
        "ID сотрудника",
        "ID типа операции бр. счёта"
    ) VALUES (
        p_amount,
        now(),
        p_account_id,
        p_staff_id,
        p_brokerage_operation_type
    )
    RETURNING "ID операции бр. счёта"
    INTO p_operation_id;
END;
$$;




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
        total_value := total_value + (paper_value * exchange_rate);
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
        RAISE EXCEPTION 'Брокерский счёт с ID %s не существует', p_brokerage_account_id
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


CREATE OR REPLACE FUNCTION public.verify_user_passport(
    p_passport_id integer
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id INTEGER;
    v_deposit_account_id INTEGER;
    v_securities RECORD;
BEGIN
    -- Находим пользователя
    SELECT "ID пользователя"
    INTO v_user_id
    FROM public."Паспорт"
    WHERE "ID паспорта" = p_passport_id;

    IF NOT FOUND THEN
        RETURN format('Паспорт с ID %s не найден', p_passport_id);
    END IF;

    -- Проверяем депозитарный счёт
    SELECT "ID депозитарного счёта"
    INTO v_deposit_account_id
    FROM public."Депозитарный счёт"
    WHERE "ID пользователя" = v_user_id;

    IF FOUND THEN
        RETURN format(
            'У пользователя с ID %s уже существует депозитарный счёт. Повторная верификация невозможна.',
            v_user_id
        );
    END IF;

    -- Создаём депозитарный счёт
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
    RETURNING "ID депозитарного счёта"
    INTO v_deposit_account_id;

    -- Создаём балансы
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

    -- Обновляем паспорт
    UPDATE public."Паспорт"
    SET "Актуальность" = true
    WHERE "ID паспорта" = p_passport_id;

    -- Обновляем статус пользователя
    UPDATE public."Пользователь"
    SET "ID статуса верификации" = 2
    WHERE "ID пользователя" = v_user_id;

    RETURN NULL; -- успех

EXCEPTION
    WHEN OTHERS THEN
        RETURN format('Ошибка верификации паспорта: %s', SQLERRM);
END;
$$;


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

CREATE OR REPLACE FUNCTION public.process_buy_proposal(
    p_employee_id integer,
    p_proposal_id integer,
    p_verify boolean
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_brokerage_account_id INTEGER;
    v_security_id INTEGER;
    v_quantity NUMERIC(12,2);
    v_cost NUMERIC(12,2);
    v_deposit_account_id INTEGER;
    v_user_id INTEGER;
    v_broker_operation_id INTEGER;

    -- Переменные для работы с измененной функцией change_brokerage_account_balance
    v_return_operation_id INTEGER;
    v_error_message TEXT;

    -- Константы
    c_buy_type_id CONSTANT INTEGER := 1;
    c_active_status_id CONSTANT INTEGER := 3;
    c_approved_status_id CONSTANT INTEGER := 2;
    c_rejected_status_id CONSTANT INTEGER := 1;
    c_deposit_operation_type_id CONSTANT INTEGER := 1;
    c_brokerage_operation_return_type_id CONSTANT INTEGER := 4;
BEGIN
    -- Получаем данные предложения
    SELECT
        p."ID брокерского счёта",
        p."ID ценной бумаги",
        p."Сумма",
        p."Сумма в валюте",
        p."ID операции бр. счёта",
        ba."ID пользователя"
    INTO
        v_brokerage_account_id,
        v_security_id,
        v_quantity,
        v_cost,
        v_broker_operation_id,
        v_user_id
    FROM public."Предложение" p
    JOIN public."Брокерский счёт" ba
        ON ba."ID брокерского счёта" = p."ID брокерского счёта"
    WHERE p."ID предложения" = p_proposal_id
      AND p."ID типа предложения" = c_buy_type_id
      AND p."ID статуса предложения" = c_active_status_id;

    IF NOT FOUND THEN
        RETURN format(
            'Предложение с ID %s не найдено или не является активным предложением на покупку',
            p_proposal_id
        );
    END IF;

    -- Находим депозитарный счёт пользователя
    SELECT "ID депозитарного счёта"
    INTO v_deposit_account_id
    FROM public."Депозитарный счёт"
    WHERE "ID пользователя" = v_user_id;

    IF NOT FOUND THEN
        RETURN format(
            'У пользователя с ID %s не найден депозитарный счёт',
            v_user_id
        );
    END IF;

    IF p_verify THEN
        -- ✅ Одобрение покупки: зачисляем ценные бумаги на депозитарный счёт
        UPDATE public."Баланс депозитарного счёта"
        SET "Сумма" = "Сумма" + v_quantity
        WHERE "ID депозитарного счёта" = v_deposit_account_id
          AND "ID пользователя" = v_user_id
          AND "ID ценной бумаги" = v_security_id;

        -- Записываем операцию в депозитарный счёт
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
        );

        -- Обновляем статус предложения на "одобрено"
        UPDATE public."Предложение"
        SET "ID статуса предложения" = c_approved_status_id
        WHERE "ID предложения" = p_proposal_id;

    ELSE
        -- ❌ Отклонение покупки: возвращаем деньги на брокерский счёт
        -- Вызываем измененную функцию через SELECT
        SELECT p_operation_id, p_error_message
        INTO v_return_operation_id, v_error_message
        FROM public.change_brokerage_account_balance(
            p_account_id := v_brokerage_account_id,
            p_amount := v_cost,
            p_brokerage_operation_type := c_brokerage_operation_return_type_id,
            p_staff_id := p_employee_id
        );

        -- Проверяем наличие ошибки
        IF v_error_message IS NOT NULL THEN
            RETURN format('Ошибка при возврате средств: %s', v_error_message);
        END IF;

        -- Обновляем статус предложения на "отклонено"
        UPDATE public."Предложение"
        SET "ID статуса предложения" = c_rejected_status_id
        WHERE "ID предложения" = p_proposal_id;
    END IF;

    RETURN NULL;

EXCEPTION
    WHEN OTHERS THEN
        RETURN SQLERRM;
END;
$$;


CREATE OR REPLACE FUNCTION public.process_sell_proposal(
    p_employee_id integer,
    p_proposal_id integer,
    p_verify boolean,
    OUT p_error_message text)
    RETURNS text
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
    -- Инициализируем переменную ошибки как NULL (успех)
    p_error_message := NULL;

    -- 1. Получаем данные предложения и проверяем, что оно активно и на продажу
    BEGIN
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
            p_error_message := 'Предложение на продажу с ID ' || p_proposal_id || ' не найдено или уже обработано';
            RETURN;
        END IF;

        v_brokerage_account_id := v_proposal."ID брокерского счёта";
        v_security_id := v_proposal."ID ценной бумаги";
        v_quantity := v_proposal.quantity;
        v_cost := v_proposal.cost;
        v_broker_operation_id := v_proposal.broker_operation_id;
        v_user_id := v_proposal."ID пользователя";
    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := 'Ошибка при получении данных предложения: ' || SQLERRM;
            RETURN;
    END;

    -- 2. Находим депозитарный счёт пользователя
    BEGIN
        SELECT "ID депозитарного счёта"
        INTO v_deposit_account_id
        FROM public."Депозитарный счёт"
        WHERE "ID пользователя" = v_user_id;

        IF NOT FOUND THEN
            p_error_message := 'У пользователя с ID ' || v_user_id || ' не найден депозитарный счёт';
            RETURN;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := 'Ошибка при поиске депозитарного счёта: ' || SQLERRM;
            RETURN;
    END;

    -- Одобрение заявки на продажу ценных бумаг:
    IF p_verify THEN
        BEGIN
            -- Обновляем историю операций брокерского счёта
            UPDATE public."История операций бр. счёта"
            SET "Сумма операции" = v_cost,
                "ID типа операции бр. счёта" = c_brokerage_operation_sell_id,
                "Время" = CURRENT_TIMESTAMP
            WHERE "ID операции бр. счёта" = v_broker_operation_id;

            -- Обновляем историю операций депозитарного счёта
            UPDATE public."История операций деп. счёта"
            SET "ID типа операции деп. счёта" = c_depo_sell
            WHERE "ID операции бр. счёта" = v_broker_operation_id;

            -- Пополняем брокерский счёт
            UPDATE public."Брокерский счёт"
            SET "Баланс" = "Баланс" + v_cost
            WHERE "ID брокерского счёта" = v_brokerage_account_id;

            -- Обновляем статус предложения
            UPDATE public."Предложение"
            SET "ID статуса предложения" = c_approved_status_id
            WHERE "ID предложения" = p_proposal_id;

        EXCEPTION
            WHEN OTHERS THEN
                p_error_message := 'Ошибка при одобрении предложения: ' || SQLERRM;
                RETURN;
        END;
    -- Отклонение заявки на продажу ценных бумаг:
    ELSE
        BEGIN
            -- Проверяем наличие записи в балансе депозитарного счёта
            PERFORM 1
            FROM public."Баланс депозитарного счёта"
            WHERE "ID депозитарного счёта" = v_deposit_account_id
              AND "ID пользователя" = v_user_id
              AND "ID ценной бумаги" = v_security_id;

            IF NOT FOUND THEN
                p_error_message := 'В балансе депозитарного счёта отсутствует запись для ценной бумаги ID ' || v_security_id;
                RETURN;
            END IF;

            -- Размораживаем ценные бумаги
            UPDATE public."Баланс депозитарного счёта"
            SET "Сумма" = "Сумма" + v_quantity
            WHERE "ID депозитарного счёта" = v_deposit_account_id
              AND "ID пользователя" = v_user_id
              AND "ID ценной бумаги" = v_security_id;

            -- Записываем операцию разморозки
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

            -- Обновляем статус предложения
            UPDATE public."Предложение"
            SET "ID статуса предложения" = c_rejected_status_id
            WHERE "ID предложения" = p_proposal_id;

        EXCEPTION
            WHEN OTHERS THEN
                p_error_message := 'Ошибка при отклонении предложения: ' || SQLERRM;
                RETURN;
        END;
    END IF;

    -- Если дошли до этого места, операция успешна
    -- p_error_message остаётся NULL

EXCEPTION
    WHEN OTHERS THEN
        p_error_message := 'Непредвиденная ошибка: ' || SQLERRM;
        RETURN;
END;
$BODY$;

CREATE OR REPLACE FUNCTION public.process_proposal(
    p_employee_id integer,
    p_proposal_id integer,
    p_verify boolean
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status_id INTEGER;
    v_proposal_type_id INTEGER;
    v_error_msg text;
BEGIN
    PERFORM 1
    FROM public."Персонал"
    WHERE "ID сотрудника" = p_employee_id;

    IF NOT FOUND THEN
        RETURN format('Сотрудник с ID %s не найден', p_employee_id);
    END IF;

    SELECT "ID типа предложения", "ID статуса предложения"
    INTO v_proposal_type_id, v_current_status_id
    FROM public."Предложение"
    WHERE "ID предложения" = p_proposal_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN format('Предложение с ID %s не найдено', p_proposal_id);
    END IF;

    IF v_current_status_id != 3 THEN
        RETURN format(
            'Предложение с ID %s имеет недопустимый статус (%s)',
            p_proposal_id,
            v_current_status_id
        );
    END IF;

    IF v_proposal_type_id = 1 THEN
        v_error_msg := public.process_buy_proposal(
            p_employee_id,
            p_proposal_id,
            p_verify
        );
    ELSIF v_proposal_type_id = 2 THEN
        v_error_msg := public.process_sell_proposal(
            p_employee_id,
            p_proposal_id,
            p_verify
        );
    ELSE
        RETURN format(
            'Неизвестный тип предложения ID %s',
            v_proposal_type_id
        );
    END IF;

    RETURN v_error_msg;
EXCEPTION
    WHEN OTHERS THEN
        RETURN SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_security(
    p_stock_id integer,
    p_employee_id integer
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_proposal_id integer;
    v_error_msg text;
    v_stock_ticker varchar;
BEGIN
    IF p_stock_id IS NULL OR p_stock_id <= 0 THEN
        RETURN 'Неверный ID ценной бумаги';
    END IF;

    SELECT "Наименование"
    INTO v_stock_ticker
    FROM public."Список ценных бумаг"
    WHERE "ID ценной бумаги" = p_stock_id;

    IF v_stock_ticker IS NULL THEN
        RETURN format('Ценная бумага с ID %s не найдена', p_stock_id);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public."Список ценных бумаг"
        WHERE "ID ценной бумаги" = p_stock_id
          AND "Статус архивации" = TRUE
    ) THEN
        RETURN format(
            'Ценная бумага "%s" (ID %s) уже архивирована',
            v_stock_ticker, p_stock_id
        );
    END IF;

    -- ⬇️ ВАЖНО: теперь вызываем FUNCTION, а не PROCEDURE
    FOR v_proposal_id IN
        SELECT p."ID предложения"
        FROM public."Предложение" p
        WHERE p."ID ценной бумаги" = p_stock_id
          AND p."ID статуса предложения" = 3
    LOOP
        v_error_msg := public.process_proposal(
            p_employee_id,
            v_proposal_id,
            FALSE
        );

        IF v_error_msg IS NOT NULL AND trim(v_error_msg) <> '' THEN
            RETURN format(
                'Ошибка при отклонении предложения ID %s для бумаги "%s": %s',
                v_proposal_id,
                v_stock_ticker,
                v_error_msg
            );
        END IF;
    END LOOP;

    DELETE FROM "Баланс депозитарного счёта"
    WHERE "ID ценной бумаги" = p_stock_id;

    DELETE FROM "История цены"
    WHERE "ID ценной бумаги" = p_stock_id;

    UPDATE public."Список ценных бумаг"
    SET "Статус архивации" = TRUE
    WHERE "ID ценной бумаги" = p_stock_id;

    RETURN NULL;
EXCEPTION
    WHEN OTHERS THEN
        RETURN format(
            'Неожиданная ошибка при архивации: %s',
            SQLERRM
        );
END;
$$;

CREATE OR REPLACE FUNCTION public.register_staff(
    p_login character varying,
    p_password character varying,
    p_contract_number character varying,
    p_rights_level_id integer,
    p_employment_status_id integer
)
RETURNS TABLE(staff_id integer, error_message text)
LANGUAGE plpgsql
AS $$
BEGIN
    staff_id := NULL;
    error_message := NULL;

    IF EXISTS (
        SELECT 1 FROM public."Персонал"
        WHERE "Логин" = p_login
    ) THEN
        error_message := 'Логин уже занят';
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public."Персонал"
        WHERE "Номер трудового договора" = p_contract_number
    ) THEN
        error_message := 'Номер договора уже занят';
        RETURN;
    END IF;

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
    RETURNING "ID сотрудника"
    INTO staff_id;

        -- УСПЕХ
    RETURN QUERY
    SELECT staff_id, NULL::text;
EXCEPTION
    WHEN OTHERS THEN
        error_message := SQLERRM;
        staff_id := NULL;
        RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION get_stock_growth(
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

    SELECT "Цена"
    INTO today_price
    FROM "История цены"
    WHERE "ID ценной бумаги" = p_paper_id
      AND "Дата" = latest_date
    LIMIT 1;

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
    v_total_price := v_price_per_share * v_lot_size * p_lot_amount;
    RETURN v_total_price;
END;
$BODY$;

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
    IN p_currency_id integer,
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
    v_deleted_rates_count INTEGER := 0;
BEGIN
    -- Инициализируем выходной параметр
    p_error_message := NULL;

    -- Проверяем, существует ли валюта с таким ID
    SELECT EXISTS(
        SELECT 1
        FROM public."Список валют"
        WHERE "ID валюты" = p_currency_id
    ) INTO v_currency_exists;

    -- Проверка 1: Существование валюты
    IF NOT v_currency_exists THEN
        p_error_message := format('Валюта с ID %s не существует', p_currency_id);
        RETURN;
    END IF;

    SELECT "Статус архивации"
    INTO v_is_already_archived
    FROM public."Список валют"
    WHERE "ID валюты" = p_currency_id;

    -- Проверка 2: Проверка статуса архивации
    IF v_is_already_archived THEN
        p_error_message := format('Валюта с ID %s уже находится в архиве', p_currency_id);
        RETURN;
    END IF;

    -- Проверка использования в таблице "Брокерский счёт"
    SELECT EXISTS(
        SELECT 1
        FROM public."Брокерский счёт"
        WHERE "ID валюты" = p_currency_id
    ) INTO v_used_in_accounts;

    IF v_used_in_accounts THEN
        -- Получаем количество для информационного сообщения
        SELECT COUNT(*)
        INTO v_accounts_count
        FROM public."Брокерский счёт"
        WHERE "ID валюты" = p_currency_id;

        p_error_message := format(
            'Валюта с ID %s используется в %s брокерском(их) счете(ах). Архивация невозможна.',
            p_currency_id, v_accounts_count
        );
        RETURN;
    END IF;

    -- Проверка использования в таблице "Список ценных бумаг"
    SELECT EXISTS(
        SELECT 1
        FROM public."Список ценных бумаг"
        WHERE "ID валюты" = p_currency_id AND "Статус архивации" = FALSE
    ) INTO v_used_in_securities;

    IF v_used_in_securities THEN
        SELECT COUNT(*)
        INTO v_securities_count
        FROM public."Список ценных бумаг"
        WHERE "ID валюты" = p_currency_id AND "Статус архивации" = FALSE;

        p_error_message := format(
            'Валюта с ID %s используется в %s неархивных ценной(ых) бумаге(ах). Архивация невозможна.',
            p_currency_id, v_securities_count
        );
        RETURN;
    END IF;

    BEGIN
        -- Удаляем записи из таблицы currency_rate перед архивацией
        DELETE FROM public."currency_rate"
        WHERE "currency_rate"."currency_id" = p_currency_id; -- Уточняем таблицу

        GET DIAGNOSTICS v_deleted_rates_count = ROW_COUNT;

        -- Обновляем статус архивации валюты
        UPDATE public."Список валют"
        SET "Статус архивации" = TRUE
        WHERE "ID валюты" = p_currency_id;

        -- Проверяем, что обновление прошло успешно
        IF NOT FOUND THEN
            p_error_message := format('Не удалось обновить статус архивации для валюты с ID %s', p_currency_id);
            RETURN;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Перехватываем любые исключения (включая от триггера) и возвращаем сообщение об ошибке
            p_error_message := format('Ошибка при архивации валюты: %s', SQLERRM);
            RETURN;
    END;

    -- Если все успешно, p_error_message остается NULL
    RAISE NOTICE 'Валюта с ID %s успешно архивирована. Удалено %s записей из currency_rate',
                 p_currency_id, v_deleted_rates_count;

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

CREATE OR REPLACE PROCEDURE public.submit_passport(
    p_user_id integer,
    p_last_name character varying,
    p_first_name character varying,
    p_patronymic character varying,
    p_series character varying,
    p_number character varying,
    p_gender character varying,
    p_birth_date date,
    p_birth_place character varying,
    p_registration_place character varying,
    p_issue_date date,
    p_issued_by character varying,
    OUT p_passport_id integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_passport_id INTEGER;
BEGIN
    p_passport_id := NULL;
    p_error_message := NULL;

    BEGIN
        IF EXISTS (SELECT 1 FROM "Паспорт" WHERE "ID пользователя" = p_user_id) THEN
            p_error_message := 'Паспорт уже привязан к пользователю';
            RETURN;
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

        UPDATE "Пользователь"
        SET "ID статуса верификации" = 3 -- "Ожидает верификации"
        WHERE "ID пользователя" = p_user_id;

        IF NOT FOUND THEN
            p_error_message := format('Пользователь с ID %s не найден', p_user_id);
            RETURN;
        END IF;

        p_passport_id := v_passport_id;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
            p_passport_id := NULL;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.delete_brokerage_account(
    p_account_id integer,
    p_user_id integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    p_error_message := NULL;

    BEGIN
        -- Проверяем существование и принадлежность счёта
        IF NOT EXISTS (
            SELECT 1
            FROM public."Брокерский счёт"
            WHERE "ID брокерского счёта" = p_account_id
              AND "ID пользователя" = p_user_id
        ) THEN
            p_error_message := format('Брокерский счёт с ID %s не найден или не принадлежит вам', p_account_id);
            RETURN;
        END IF;

        -- Проверяем баланс
        IF (SELECT "Баланс" FROM public."Брокерский счёт" WHERE "ID брокерского счёта" = p_account_id) != 0 THEN
            p_error_message := 'Нельзя удалить брокерский счёт с ненулевым балансом';
            RETURN;
        END IF;

        -- Удаляем счёт
        DELETE FROM public."Брокерский счёт"
        WHERE "ID брокерского счёта" = p_account_id;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.add_bank(
    p_name character varying,
    p_inn character varying,
    p_ogrn character varying,
    p_bik character varying,
    p_license_expiry_date date,
    OUT p_bank_id integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_bank_id INTEGER;
BEGIN
    p_bank_id := NULL;
    p_error_message := NULL;

    BEGIN
        INSERT INTO public."Банк" (
            "Наименование",
            "ИНН",
            "ОГРН",
            "БИК",
            "Срок действия лицензии"
        )
        VALUES (
            p_name,
            p_inn,
            p_ogrn,
            p_bik,
            p_license_expiry_date
        )
        RETURNING "ID банка" INTO v_bank_id;

        p_bank_id := v_bank_id;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
            p_bank_id := NULL;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.add_brokerage_account(
    IN p_user_id integer,
    IN p_bank_id integer,
    IN p_currency_id integer,
    IN p_inn character varying,
    OUT p_account_id integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_account_id INTEGER;
    v_bik VARCHAR(40);
BEGIN
    p_account_id := NULL;
    p_error_message := NULL;

    BEGIN
        -- Проверка существования банка
        SELECT "БИК"
        INTO v_bik
        FROM public."Банк"
        WHERE "ID банка" = p_bank_id;

        IF NOT FOUND THEN
            p_error_message := format('Банк с ID %s не найден', p_bank_id);
            RETURN;
        END IF;

        -- Проверка существования валюты (и что она не архивирована)
        PERFORM 1
        FROM public."Список валют"
        WHERE "ID валюты" = p_currency_id
          AND "Статус архивации" = FALSE;

        IF NOT FOUND THEN
            p_error_message := format('Валюта с ID %s не найдена или архивирована', p_currency_id);
            RETURN;
        END IF;

        -- Создаём брокерский счёт с нулевым балансом
        INSERT INTO public."Брокерский счёт" (
            "Баланс",
            "ID банка",
            "БИК",
            "ИНН",
            "ID валюты",
            "ID пользователя"
        )
        VALUES (
            0.00,
            p_bank_id,
            v_bik,
            p_inn,
            p_currency_id,
            p_user_id
        )
        RETURNING "ID брокерского счёта" INTO v_account_id;

        p_account_id := v_account_id;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
            p_account_id := NULL;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.add_buy_proposal(
    p_security_id integer,
    p_brokerage_account_id integer,
    p_lot_amount_to_buy integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_lot_size NUMERIC(12,2);
    v_security_price NUMERIC(12,2);
    v_total_quantity NUMERIC(12,2);
    v_total_cost NUMERIC(12,2);
    v_operation_id INTEGER;
    v_proposal_id INTEGER;
    v_func_result RECORD;
    v_buy_type_id CONSTANT INTEGER := 1;
    v_active_status_id CONSTANT INTEGER := 3;
    v_employee_id CONSTANT INTEGER := 2;
BEGIN
    p_error_message := NULL;

    BEGIN
        -- Проверка входных параметров
        IF p_lot_amount_to_buy <= 0 THEN
            p_error_message := format('Количество лотов для покупки должно быть строго больше нуля (получено: %s)', p_lot_amount_to_buy);
            RETURN;
        END IF;

        -- Получаем размер лота
        SELECT "Размер лота" INTO v_lot_size
        FROM public."Список ценных бумаг"
        WHERE "ID ценной бумаги" = p_security_id;

        IF NOT FOUND THEN
            p_error_message := format('Ценная бумага с ID %s не найдена', p_security_id);
            RETURN;
        END IF;

        -- Получаем текущую цену ценной бумаги
        v_security_price := get_security_value_native(p_security_id);

        -- Рассчитываем общее количество и стоимость
        v_total_quantity := v_lot_size * p_lot_amount_to_buy;
        v_total_cost := v_total_quantity * v_security_price;

        -- Вызываем функцию для изменения баланса счета
        v_func_result := public.change_brokerage_account_balance(
            p_account_id := p_brokerage_account_id,
            p_amount := -v_total_cost,
            p_brokerage_operation_type := 3,
            p_staff_id := v_employee_id
        );

        -- Извлекаем значения из результата функции
        v_operation_id := v_func_result.p_operation_id;
        p_error_message := v_func_result.p_error_message;

        -- Проверяем наличие ошибки
        IF p_error_message IS NOT NULL THEN
            RETURN;
        END IF;

        -- Проверяем, что операция была создана
        IF v_operation_id IS NULL THEN
            p_error_message := 'Ошибка при создании операции списания средств';
            RETURN;
        END IF;

        -- Создаем предложение на покупку
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
            v_operation_id,
            p_security_id,
            p_brokerage_account_id,
            v_buy_type_id,
            v_active_status_id
        )
        RETURNING "ID предложения" INTO v_proposal_id;

        -- Логируем успешное создание
        RAISE NOTICE 'Создано предложение на покупку ID: %, стоимость: %, операция: %',
            v_proposal_id, v_total_cost, v_operation_id;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.add_security(
    p_ticker character varying,
    p_isin character varying,
    p_lot_size numeric,
    p_price numeric,
    p_currency_id integer,
    OUT p_security_id integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_security_id INTEGER;
    r_deposit_account RECORD;
BEGIN
    p_security_id := NULL;
    p_error_message := NULL;

    BEGIN
        IF p_lot_size <= 0 THEN
            p_error_message := format('Размер лота должен быть строго больше нуля (получено: %s)', p_lot_size);
            RETURN;
        END IF;

        PERFORM 1 FROM public."Список валют" WHERE "ID валюты" = p_currency_id;
        IF NOT FOUND THEN
            p_error_message := format('Валюта с ID %s не найдена', p_currency_id);
            RETURN;
        END IF;

        PERFORM 1 FROM public."Список ценных бумаг" WHERE "ISIN" = p_isin;
        IF FOUND THEN
            p_error_message := format('Ценная бумага с ISIN %s уже существует', p_isin);
            RETURN;
        END IF;

        INSERT INTO public."Список ценных бумаг" (
            "Наименование",
            "Размер лота",
            "ISIN",
            "ID валюты"
        ) VALUES (
            p_ticker,
            p_lot_size,
            p_isin,
            p_currency_id
        )
        RETURNING "ID ценной бумаги" INTO v_security_id;

        INSERT INTO public."История цены" (
            "Дата",
            "Цена",
            "ID ценной бумаги"
        ) VALUES (
            CURRENT_DATE,
            p_price,
            v_security_id
        );

        FOR r_deposit_account IN
            SELECT "ID депозитарного счёта", "ID пользователя"
            FROM public."Депозитарный счёт"
        LOOP
            INSERT INTO public."Баланс депозитарного счёта" (
                "Сумма",
                "ID депозитарного счёта",
                "ID пользователя",
                "ID ценной бумаги"
            ) VALUES (
                0.00,
                r_deposit_account."ID депозитарного счёта",
                r_deposit_account."ID пользователя",
                v_security_id
            );
        END LOOP;

        p_security_id := v_security_id;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
            p_security_id := NULL;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.add_sell_proposal(
    p_security_id integer,
    p_brokerage_account_id integer,
    p_lot_amount_to_sell integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_lot_size NUMERIC(12,2);
    v_total_quantity NUMERIC(12,2);
    v_total_cost NUMERIC(12,2);
    v_user_id INTEGER;
    v_deposit_account_id INTEGER;
    v_current_deposit_balance NUMERIC(12,2);
    v_brokerage_operation_id INTEGER;
    v_deposit_operation_id INTEGER;
    v_proposal_id INTEGER;
    v_sell_type_id CONSTANT INTEGER := 2;
    v_active_status_id CONSTANT INTEGER := 3;
    v_employee_id CONSTANT INTEGER := 2;
    v_empty_brokerage_type CONSTANT INTEGER := 6;
    v_lock_deposit_operation_type_id CONSTANT INTEGER := 3;
BEGIN
    p_error_message := NULL;

    BEGIN
        IF p_lot_amount_to_sell <= 0 THEN
            p_error_message := format('Количество лотов для продажи должно быть строго больше нуля (получено: %s)', p_lot_amount_to_sell);
            RETURN;
        END IF;

        SELECT "Размер лота" INTO v_lot_size
        FROM public."Список ценных бумаг"
        WHERE "ID ценной бумаги" = p_security_id;

        IF NOT FOUND THEN
            p_error_message := format('Ценная бумага с ID %s не найдена', p_security_id);
            RETURN;
        END IF;

        v_total_quantity := v_lot_size * p_lot_amount_to_sell;
        v_total_cost := v_total_quantity * get_security_value_native(p_security_id);

        SELECT "ID пользователя" INTO v_user_id
        FROM public."Брокерский счёт"
        WHERE "ID брокерского счёта" = p_brokerage_account_id;

        IF NOT FOUND THEN
            p_error_message := format('Брокерский счёт с ID %s не найден', p_brokerage_account_id);
            RETURN;
        END IF;

        SELECT "ID депозитарного счёта" INTO v_deposit_account_id
        FROM public."Депозитарный счёт"
        WHERE "ID пользователя" = v_user_id;

        IF NOT FOUND THEN
            p_error_message := format('Депозитарный счёт для пользователя ID %s не найден', v_user_id);
            RETURN;
        END IF;

        SELECT "Сумма" INTO v_current_deposit_balance
        FROM public."Баланс депозитарного счёта"
        WHERE "ID депозитарного счёта" = v_deposit_account_id
          AND "ID пользователя" = v_user_id
          AND "ID ценной бумаги" = p_security_id
        FOR UPDATE;

        IF NOT FOUND THEN
            p_error_message := format('Запись баланса для ценной бумаги ID %s на депозитарном счёте пользователя ID %s не найдена',
                p_security_id, v_user_id);
            RETURN;
        END IF;

        IF v_current_deposit_balance < v_total_quantity THEN
            p_error_message := format('Недостаточно свободных ценных бумаг для продажи. Доступно: %s, требуется: %s',
                v_current_deposit_balance, v_total_quantity);
            RETURN;
        END IF;

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
        );

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.change_stock_price(
    p_stock_id integer,
    p_new_price numeric,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_today DATE := CURRENT_DATE;
    v_exists INTEGER;
BEGIN
    p_error_message := NULL;
    BEGIN
        -- Проверка существования ценной бумаги
        PERFORM 1
        FROM public."Список ценных бумаг"
        WHERE "ID ценной бумаги" = p_stock_id;

        IF NOT FOUND THEN
            p_error_message := format('Ценная бумага с ID %s не найдена', p_stock_id);
            RETURN;
        END IF;

        SELECT 1 INTO v_exists
        FROM public."История цены"
        WHERE "ID ценной бумаги" = p_stock_id
          AND "Дата" = v_today;

        IF FOUND THEN
            -- Обновляем существующую запись
            UPDATE public."История цены"
            SET "Цена" = p_new_price
            WHERE "ID ценной бумаги" = p_stock_id
              AND "Дата" = v_today;
        ELSE
            -- Добавляем новую запись
            INSERT INTO public."История цены" (
                "Дата",
                "Цена",
                "ID ценной бумаги"
            ) VALUES (
                v_today,
                p_new_price,
                p_stock_id
            );
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.add_proposal(
    IN p_user_id integer,
    IN p_security_id integer,
    IN p_brokerage_account_id integer,
    IN p_proposal_type_id integer,
    IN p_lot_amount integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    v_security_archived BOOLEAN;
    v_security_ticker VARCHAR;
    v_security_currency_id INTEGER;
    v_account_currency_id INTEGER;
BEGIN
    p_error_message := NULL;

    BEGIN
        -- Проверка типа предложения
        IF p_proposal_type_id NOT IN (1, 2) THEN
            p_error_message := format('Некорректный тип предложения: %s (допустимо 1 или 2)', p_proposal_type_id);
            RETURN;
        END IF;

        -- Проверка количества лотов
        IF p_lot_amount <= 0 THEN
            p_error_message := format('Количество лотов должно быть строго больше нуля (получено: %s)', p_lot_amount);
            RETURN;
        END IF;

        -- Проверка существования брокерского счёта и принадлежности пользователю
        PERFORM 1
        FROM public."Брокерский счёт"
        WHERE "ID брокерского счёта" = p_brokerage_account_id
          AND "ID пользователя" = p_user_id;

        IF NOT FOUND THEN
            p_error_message := format('Брокерский счёт с ID %s не найден или не принадлежит пользователю ID %s',
                                    p_brokerage_account_id, p_user_id);
            RETURN;
        END IF;

        -- Проверка существования ценной бумаги и её статус архивации
        SELECT s."Статус архивации", s."Наименование", s."ID валюты",
               ba."ID валюты"
        INTO v_security_archived, v_security_ticker, v_security_currency_id,
             v_account_currency_id
        FROM public."Список ценных бумаг" s
        CROSS JOIN public."Брокерский счёт" ba
        WHERE s."ID ценной бумаги" = p_security_id
          AND ba."ID брокерского счёта" = p_brokerage_account_id;

        -- Если бумага не найдена
        IF v_security_ticker IS NULL THEN
            p_error_message := format('Ценная бумага с ID %s не найдена', p_security_id);
            RETURN;
        END IF;

        -- Проверка на архивность ценной бумаги
        IF v_security_archived THEN
            p_error_message := format('Ценная бумага "%s" (ID %s) архивирована и недоступна для торговли',
                                    v_security_ticker, p_security_id);
            RETURN;
        END IF;

        -- Проверка соответствия валюты счёта и бумаги
        IF v_security_currency_id != v_account_currency_id THEN
            p_error_message := format(
                'Валюта ценной бумаги "%s" (ID %s) не соответствует валюте брокерского счёта ID %s',
                v_security_ticker, p_security_id, p_brokerage_account_id
            );
            RETURN;
        END IF;

        -- Вызов соответствующей процедуры в зависимости от типа
        IF p_proposal_type_id = 1 THEN
            -- Покупка
            CALL add_buy_proposal(p_security_id, p_brokerage_account_id, p_lot_amount, p_error_message);
        ELSIF p_proposal_type_id = 2 THEN
            -- Продажа
            CALL add_sell_proposal(p_security_id, p_brokerage_account_id, p_lot_amount, p_error_message);
        END IF;

        -- Если дочерняя процедура вернула ошибку — она уже в p_error_message
        IF p_error_message IS NOT NULL THEN
            RETURN;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.delete_bank(
    IN p_bank_id integer,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    p_error_message := NULL;
    BEGIN
        PERFORM 1 FROM public."Банк" WHERE "ID банка" = p_bank_id;
        IF NOT FOUND THEN
            p_error_message := format('Банк с ID %s не найден', p_bank_id);
            RETURN;
        END IF;

        PERFORM 1 FROM public."Брокерский счёт" WHERE "ID банка" = p_bank_id;
        IF FOUND THEN
            p_error_message := format('Нельзя удалить банк с ID %s: он используется в брокерских счетах', p_bank_id);
            RETURN;
        END IF;

        DELETE FROM public."Банк" WHERE "ID банка" = p_bank_id;

        IF NOT FOUND THEN
            p_error_message := format('Не удалось удалить банк с ID %s', p_bank_id);
            RETURN;
        END IF;

    EXCEPTION
        WHEN foreign_key_violation THEN
            p_error_message := format('Нельзя удалить банк с ID %s: на него есть ссылки в других таблицах', p_bank_id);
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.update_bank(
    IN p_bank_id integer,
    IN p_name character varying,
    IN p_inn character varying,
    IN p_ogrn character varying,
    IN p_bik character varying,
    IN p_license_expiry_date date,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    p_error_message := NULL;

    BEGIN
        -- Проверка существования банка
        PERFORM 1 FROM public."Банк" WHERE "ID банка" = p_bank_id;
        IF NOT FOUND THEN
            p_error_message := format('Банк с ID %s не найден', p_bank_id);
            RETURN;
        END IF;

        -- Обновляем только непустые поля (NULL не меняет значение)
        UPDATE public."Банк"
        SET
            "Наименование" = COALESCE(p_name, "Наименование"),
            "ИНН" = COALESCE(p_inn, "ИНН"),
            "ОГРН" = COALESCE(p_ogrn, "ОГРН"),
            "БИК" = COALESCE(p_bik, "БИК"),
            "Срок действия лицензии" = COALESCE(p_license_expiry_date, "Срок действия лицензии")
        WHERE "ID банка" = p_bank_id;

        IF NOT FOUND THEN
            p_error_message := format('Не удалось обновить банк с ID %s', p_bank_id);
            RETURN;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
    END;
END;
$BODY$;

CREATE OR REPLACE PROCEDURE public.update_security(
    IN p_stock_id integer,
    IN p_ticker character varying,
    IN p_isin character varying,
    IN p_lot_size integer,
    IN p_price numeric,
    OUT p_error_message character varying
)
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    p_error_message := NULL;
    BEGIN
        PERFORM 1 FROM public."Список ценных бумаг" WHERE "ID ценной бумаги" = p_stock_id;
        IF NOT FOUND THEN
            p_error_message := format('Ценная бумага с ID %s не найдена', p_stock_id);
            RETURN;
        END IF;

        UPDATE public."Список ценных бумаг"
        SET
            "Наименование" = COALESCE(p_ticker, "Наименование"),
            "ISIN" = COALESCE(p_isin, "ISIN"),
            "Размер лота" = COALESCE(p_lot_size, "Размер лота")
        WHERE "ID ценной бумаги" = p_stock_id;

        -- Если нужно обновить текущую цену — вызываем процедуру change_stock_price
        IF p_price IS NOT NULL THEN
            CALL public.change_stock_price(
                p_stock_id := p_stock_id,
                p_new_price := p_price,
                p_error_message := p_error_message
            );

            -- Если при изменении цены произошла ошибка
            IF p_error_message IS NOT NULL THEN
                RETURN;
            END IF;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            p_error_message := SQLERRM;
    END;
END;
$BODY$;

call add_currency('usd', '$', 100, null, null);
call add_currency('eur', '€', 200, null, null);

call add_bank('ПАО Сбербанк', '7707083893', '1027700132195', '044525225', '2036-11-27'::DATE, null, null);
--call add_bank('Банк ВТБ (ПАО)', '7702070139', '1027700031594', '044525187', '2032-10-17'::DATE, null, null);
--call add_bank('АО "Альфа-Банк"', '7728168971', '1027700067328', '044525593', '2031-12-31'::DATE, null, null);
--call add_bank('ПАО Банк "ФК Открытие"', '7706092528', '1027700389635', '044525297', '2029-08-14'::DATE, null, null);
--call add_bank('АО "Тинькофф Банк"', '7710140679', '1027739642281', '044525974', '2030-06-22'::DATE, null, null);

call add_security('SBER', 'RU0009029540', 2, 100, 1, null, null);
--call add_security('GAZP', 'RU000A0JR4A1', 3, 10, 1, null, null);

-- pass: 123456
select * from register_staff('admin', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '8800', 2, 1);
select * from register_staff('admin2', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '88000', 2, 1);
select * from register_staff('broker', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '8801', 3, 1);
select * from register_staff('verifier', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '8802', 4, 1);

call register_user('1', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', '12345@example.com', null, null); -- password: 123456
call submit_passport(1, 'Медведев', 'Даниил', 'Андреевич', '0114', '439954', 'м', '2004-01-01', 'г. Барнаул', 'г. Барнаул', '2020-01-01', 'ГУ МВД РФ', null, null);
select verify_user_passport(1);

call register_user('2', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', 'email2@example.com', null, null);
call submit_passport(2, 'Иванов', 'Иван', 'Иванович', '0113', '439957', 'м', '2004-01-01', 'г. Барнаул', 'г. Барнаул', '2020-01-01', 'ГУ МВД РФ', null, null);
select verify_user_passport(2);

call register_user('3', '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO', 'email3@example.com', null, null);

call add_brokerage_account(1, 1, 1, '500100732259', null, null);
call add_brokerage_account(1, 1, 3, '600133890863', null, null);
select change_brokerage_account_balance(1, 1000000, 1, 2);


call add_buy_proposal(1, 1, 1, null);
select process_proposal(1, 1, true);

call add_proposal(1, 1, 1, 1, 2, null);
