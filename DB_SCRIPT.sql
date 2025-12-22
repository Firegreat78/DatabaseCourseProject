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
WITH (autovacuum_enabled=true);
ALTER TABLE "Депозитарный счёт" ADD CONSTRAINT "Unique_Identifier13" PRIMARY KEY ("ID депозитарного счёта","ID пользователя");
ALTER TABLE "Депозитарный счёт" ADD CONSTRAINT unique_user_deposit_account UNIQUE ("ID пользователя");

-- Table Баланс депозитарного счёта

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
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship51" ON "Список ценных бумаг" ("ID валюты");
ALTER TABLE "Список ценных бумаг" ADD CONSTRAINT "Unique_Identifier5" PRIMARY KEY ("ID ценной бумаги");

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
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship27" ON "История операций деп. счёта" ("ID ценной бумаги");
CREATE INDEX "IX_Relationship28" ON "История операций деп. счёта" ("ID сотрудника");
CREATE INDEX "IX_Relationship35" ON "История операций деп. счёта" ("ID типа операции деп. счёта");
ALTER TABLE "История операций деп. счёта" ADD CONSTRAINT "Unique_Identifier18" PRIMARY KEY ("ID операции деп. счёта","ID депозитарного счёта","ID пользователя","ID операции бр. счёта","ID брокерского счёта");

-- Table Тип операции депозитарного счёта

CREATE TABLE "Тип операции депозитарного счёта"
(
  "ID типа операции деп. счёта" Serial NOT NULL,
  "Тип" Character varying(15) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Тип операции депозитарного счёта" ADD CONSTRAINT "Unique_Identifier1" PRIMARY KEY ("ID типа операции деп. счёта");

-- Table Брокерский счёт

CREATE TABLE "Брокерский счёт"
(
  "ID брокерского счёта" Serial NOT NULL,
  "Баланс" Numeric(12,2) NOT NULL,
  "ИНН" Character varying(30) NOT NULL,
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

-- Table История операций бр. счёта

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
  "Код" Char(3) NOT NULL UNIQUE,
  "Символ" Character varying(10) NOT NULL
)
WITH (autovacuum_enabled=true);
ALTER TABLE "Список валют" ADD CONSTRAINT "Unique_Identifier6" PRIMARY KEY ("ID валюты");

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
WITH (autovacuum_enabled=true);
ALTER TABLE "Банк" ADD CONSTRAINT "Unique_Identifier8" PRIMARY KEY ("ID банка");

-- Table История цены

CREATE TABLE "История цены"
(
  "ID зап. ист. цены" Serial NOT NULL,
  "Дата" Date NOT NULL,
  "Цена" Numeric(12,2) NOT NULL,
  "ID ценной бумаги" Integer NOT NULL
)
WITH (autovacuum_enabled=true);
CREATE INDEX "IX_Relationship50" ON "История цены" ("ID ценной бумаги");
ALTER TABLE "История цены" ADD CONSTRAINT "Unique_Identifier15" PRIMARY KEY ("ID зап. ист. цены");

CREATE TABLE currency_rate (
    id SERIAL PRIMARY KEY,
    base_currency_id INT NOT NULL,
    target_currency_id INT NOT NULL,
    rate NUMERIC(20, 8) NOT NULL,
    rate_date DATE NOT NULL DEFAULT CURRENT_DATE,
    rate_time TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (base_currency_id, target_currency_id, rate_date) -- Один курс на пару в день
);

CREATE TABLE "Статус блока пользователя" (
	"ID статуса блокировки" Serial PRIMARY KEY,
	"Статус" VARCHAR(30) NOT NULL
)
WITH (autovacuum_enabled=true);

-- Create foreign keys (relationships) section -------------------------------------------------

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
    FOREIGN KEY ("ID брокерского счёта")
    REFERENCES "Брокерский счёт" ("ID брокерского счёта")
      ON DELETE CASCADE
      ON UPDATE CASCADE;

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

ALTER TABLE "Брокерский счёт"
	ADD CONSTRAINT "Relationship52"
    FOREIGN KEY ("ID пользователя")
    REFERENCES "Пользователь"("ID пользователя")
    ON DELETE CASCADE
    ON UPDATE CASCADE;


ALTER TABLE currency_rate
ADD CONSTRAINT "Relationship53"
    FOREIGN KEY (base_currency_id)
    REFERENCES "Список валют"("ID валюты")
    ON DELETE RESTRICT
    ON UPDATE RESTRICT;

ALTER TABLE currency_rate
ADD CONSTRAINT "Relationship54"
    FOREIGN KEY (target_currency_id)
    REFERENCES "Список валют"("ID валюты")
    ON DELETE RESTRICT
    ON UPDATE RESTRICT;


INSERT INTO "Статус верификации"("Статус верификации")
VALUES
('Не подтверждён'),
('Подтверждён'),
('Ожидает верификации');

INSERT INTO "Статус трудоустройства"("Статус трудоустройства")
VALUES
('Активен'),
('Уволен'),
('Отпуск');

INSERT INTO "Статус предложения"("Статус")
VALUES
('Не подтверждён'),
('Подтверждён'),
('Ожидает верификации');

INSERT INTO public."Персонал" (
    "Номер трудового договора",
    "Логин",
    "Пароль",
    "Уровень прав",
    "ID статуса трудоустройства"
) VALUES
(1,'megaadmin','$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO','1',1), --Мега админ
(2,'admin','$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO','2',1),     --Админ
(3,'broker','$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO','3',1),    --Брокер
(4,'verifier','$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO','4',1),  --Верификатор
(5,'system','','5',1);  --Система


INSERT INTO "Список валют"("Код", "Символ")
VALUES
('RUB', '₽'),
('USD', '$');

-- 5. Банки
INSERT INTO "Банк"("Наименование", "ИНН", "ОГРН", "БИК", "Срок действия лицензии")
VALUES
('Сбербанк', '1234567890', '102030405060', '044525225', '2030-12-31');

-- 6. Ценные бумаги
INSERT INTO "Список ценных бумаг"("Наименование", "Размер лота", "ISIN", "Выплата дивидендов", "ID валюты")
VALUES
('Газпром', 10, 'RU0007661625', TRUE, 1),
('Сбербанк', 5, 'RU0009029540', TRUE, 1),
('Биткоин', 1, 'BTC', FALSE, 2);

INSERT INTO "История цены" ("Дата", "Цена", "ID ценной бумаги")
VALUES
-- Ценная бумага 1 (например, Сбер)
('2025-12-04', 288.20, 1),  -- Цена закрытия
('2025-12-05', 292.50, 1),
('2025-12-06', 290.80, 1),
('2025-12-07', 295.10, 1),
('2025-12-08', 298.40, 1),
('2025-12-09', 302.70, 1),
('2025-12-10', 300.50, 1),
('2025-12-11', 305.80, 1),
('2025-12-12', 310.20, 1),
('2025-12-13', 315.60, 1),

-- Ценная бумага 2 (например, Газпром)
('2025-12-04', 147.80, 2),
('2025-12-05', 150.20, 2),
('2025-12-06', 148.90, 2),
('2025-12-07', 152.40, 2),
('2025-12-08', 155.10, 2),
('2025-12-09', 158.60, 2),
('2025-12-10', 156.30, 2),
('2025-12-11', 160.80, 2),
('2025-12-12', 164.50, 2),
('2025-12-13', 168.20, 2),

-- Ценная бумага 3 (Биткоин)
('2025-12-04', 93500.00, 3),
('2025-12-05', 92800.00, 3),
('2025-12-06', 91000.00, 3),
('2025-12-07', 92500.00, 3),
('2025-12-08', 94000.00, 3),
('2025-12-09', 93500.00, 3),
('2025-12-10', 92000.00, 3),
('2025-12-11', 90500.00, 3),
('2025-12-12', 89000.00, 3),
('2025-12-13', 87500.00, 3);

-- 7. Типы операций депозитарного счёта
INSERT INTO "Тип операции депозитарного счёта"("Тип")
VALUES
('Покупка'),
('Продажа'),
('Заморозка ЦБ'),
('Разморозка ЦБ');

-- 8. Типы операций брокерского счёта
INSERT INTO "Тип операции брокерского счёта"("Тип")
VALUES
('Пополнение'),
('Снятие'),
('Покупка ЦБ'),
('Покупка ЦБ (в)'),
('Продажа ЦБ'),
('Empty');

-- 9. Типы предложений
INSERT INTO "Тип предложения"("Тип")
VALUES
('Покупка'),
('Продажа');

INSERT INTO "Статус блока пользователя"("Статус")
VALUES
('Не заблокирован'),
('Заблокирован');


-- =========================
-- 2) ФУНКЦИИ
-- =========================

CREATE OR REPLACE FUNCTION public.change_brokerage_account_balance(
    p_account_id integer,
    p_amount numeric,
    p_brokerage_operation_type integer,  -- Теперь используется как ID типа операции
    p_staff_id integer DEFAULT 5
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

ALTER FUNCTION public.change_brokerage_account_balance(integer, numeric, integer, integer)
    OWNER TO postgres;

CREATE OR REPLACE FUNCTION check_user_verification_status(user_id integer)
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

ALTER FUNCTION public.get_user_offers(integer)
    OWNER TO postgres;


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

ALTER FUNCTION public.get_exchange_stocks()
    OWNER TO postgres;


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

-- 2.1 get_currency_rate: вернёт КУРС по ID валюты (курс в рублях за единицу валюты).
CREATE OR REPLACE FUNCTION get_currency_rate(
    p_base_currency_id INTEGER,
    p_target_currency_id INTEGER
)
RETURNS NUMERIC AS $$
DECLARE
    v_rate NUMERIC;
BEGIN
    -- Если валюты одинаковые — курс всегда 1
    IF p_base_currency_id = p_target_currency_id THEN
        RETURN 1.0;
    END IF;

    -- Если один из ID NULL — возвращаем NULL
    IF p_base_currency_id IS NULL OR p_target_currency_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- 1. Прямой курс: сначала на сегодня, потом самый свежий ≤ сегодня
    SELECT rate INTO v_rate
    FROM currency_rate
    WHERE base_currency_id = p_base_currency_id
      AND target_currency_id = p_target_currency_id
      AND rate_date <= CURRENT_DATE
    ORDER BY rate_date DESC
    LIMIT 1;

    IF v_rate IS NOT NULL THEN
        RETURN ROUND(v_rate, 8);
    END IF;

    -- 2. Обратный курс: ищем target → base (самый свежий ≤ сегодня)
    SELECT rate INTO v_rate
    FROM currency_rate
    WHERE base_currency_id = p_target_currency_id
      AND target_currency_id = p_base_currency_id
      AND rate_date <= CURRENT_DATE
    ORDER BY rate_date DESC
    LIMIT 1;

    IF v_rate IS NOT NULL THEN
        RETURN ROUND(1.0 / v_rate, 8);
    END IF;

    -- 3. Если вообще ничего не найдено — возвращаем NULL
    RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;


CREATE OR REPLACE FUNCTION get_currency_rate(p_target_currency_id INT)
RETURNS NUMERIC AS $$
    SELECT get_currency_rate(1, p_target_currency_id);  -- 1 = RUB id
$$ LANGUAGE sql STABLE;


-- 2.2 convert_amount: конвертирует сумму из currency_from -> currency_to
CREATE OR REPLACE FUNCTION convert_amount(
    p_amount NUMERIC,
    p_from_currency_id INT,   -- ID валюты, ИЗ которой конвертируем
    p_to_currency_id INT      -- ID валюты, В которую конвертируем
)
RETURNS NUMERIC AS $$
DECLARE
    v_rate NUMERIC;
BEGIN
    -- Если сумма NULL или 0 — возвращаем 0
    IF p_amount IS NULL OR p_amount = 0 THEN
        RETURN 0;
    END IF;

    -- Если валюты не указаны — возвращаем null
    IF p_from_currency_id IS NULL OR p_to_currency_id IS NULL THEN
        RETURN NULL;  -- или RETURN 0;
    END IF;

    -- Если валюты одинаковые — просто возвращаем сумму
    IF p_from_currency_id = p_to_currency_id THEN
        RETURN ROUND(p_amount, 8);
    END IF;

    v_rate := get_currency_rate(p_from_currency_id, p_to_currency_id);

    IF v_rate IS NULL OR v_rate = 0 THEN
        RAISE NOTICE 'Курс от % к % не найден', p_from_currency_id, p_to_currency_id;
        RETURN 0;  -- или RAISE EXCEPTION, если хочешь строгую ошибку
    END IF;

    -- Конвертация: p_amount (в from) * rate (from → to)
    RETURN ROUND(p_amount * v_rate, 8);
END;
$$ LANGUAGE plpgsql STABLE;


CREATE OR REPLACE FUNCTION calc_depo_value(
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

        -- Вычисляем стоимость бумаги в её собственной валюте
        paper_value := paper_value * paper_price;

        -- Если валюта бумаги совпадает с целевой валютой
        IF paper_currency_id = p_currency_id THEN
            total_value := total_value + paper_value;
        ELSE
            -- Конвертируем в целевую валюту
            -- Предполагаем, что функция get_currency_rate(from_currency_id, to_currency_id) существует
            exchange_rate := get_currency_rate(paper_currency_id, p_currency_id);

            IF exchange_rate IS NOT NULL AND exchange_rate > 0 THEN
                total_value := total_value + (paper_value / exchange_rate);
            END IF;
        END IF;
    END LOOP;

    RETURN COALESCE(total_value, 0);
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
    SELECT COALESCE(SUM(convert_amount(bs."Баланс", p_currency_id, bs."ID валюты")),0)
    INTO bs_sum
    FROM "Брокерский счёт" bs
    WHERE bs."ID пользователя" = p_user_id;

    total := total + COALESCE(bs_sum,0);

    RETURN COALESCE(total,0);
END;
$$ LANGUAGE plpgsql;


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

ALTER FUNCTION public.get_security_value(integer, integer)
OWNER TO postgres;

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

ALTER FUNCTION public.get_security_value_native(integer)
OWNER TO postgres;

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
    v_employee_id INTEGER := 5;                 -- По умолчанию сотрудник 5
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
    v_employee_id INTEGER := 5;       -- Сотрудник по умолчанию
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

    -- 8. Создаём запись в истории операций брокерского счёта с суммой 0
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

    -- 9. Создаём запись в истории операций депозитарного счёта (заморозка)
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

    -- 10. Создаём предложение на продажу (используем RETURNING вместо nextval)
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
    p_employee_id integer,    -- ID сотрудника-админа, который принимает решение
    p_proposal_id integer,    -- ID предложения
    p_verify boolean          -- TRUE = одобрить, FALSE = отклонить
)
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
COST 100
AS $BODY$
DECLARE
    v_brokerage_account_id INTEGER;
    v_security_id INTEGER;
    v_quantity NUMERIC(12,2);          -- количество ценных бумаг
    v_cost NUMERIC(12,2);              -- сумма в валюте

    v_deposit_account_id INTEGER;
    v_user_id INTEGER;

    v_broker_operation_id INTEGER;     -- ID исходной операции списания (для ссылки)
    v_new_broker_operation_id INTEGER; -- ID новой операции при отклонении (не обязателен)
    v_new_deposit_operation_id INTEGER;

    -- Константы (подправьте только если отличаются в вашей базе)
    c_buy_type_id CONSTANT INTEGER := 1;                    -- Тип предложения "Покупка"
    c_active_status_id CONSTANT INTEGER := 3;               -- Статус "Новое/Активное"
    c_approved_status_id CONSTANT INTEGER := 2;             -- Статус "Одобрено"
    c_rejected_status_id CONSTANT INTEGER := 1;             -- Статус "Отклонено"
    c_deposit_operation_type_id CONSTANT INTEGER := 1;      -- Тип операции деп. счёта "Зачисление ценных бумаг"
	c_brokerage_operation_return_type_id CONSTANT INTEGER := 4;
BEGIN
    -- 1. Получаем данные предложения и проверяем его состояние
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

    -- 2. Находим депозитарный счёт пользователя
    SELECT "ID депозитарного счёта"
    INTO v_deposit_account_id
    FROM public."Депозитарный счёт"
    WHERE "ID пользователя" = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'У пользователя с ID % не найден депозитарный счёт', v_user_id;
    END IF;

    IF p_verify THEN
        -- === ОДОБРЕНИЕ ===

        -- Проверяем наличие записи в балансе депозитарного счёта
        PERFORM 1
        FROM public."Баланс депозитарного счёта"
        WHERE "ID депозитарного счёта" = v_deposit_account_id
          AND "ID пользователя" = v_user_id
          AND "ID ценной бумаги" = v_security_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'В балансе депозитарного счёта отсутствует запись для ценной бумаги ID % у пользователя ID %', v_security_id, v_user_id;
        END IF;

        -- Обновляем баланс: добавляем количество ценных бумаг
        UPDATE public."Баланс депозитарного счёта"
        SET "Сумма" = "Сумма" + v_quantity
        WHERE "ID депозитарного счёта" = v_deposit_account_id
          AND "ID пользователя" = v_user_id
          AND "ID ценной бумаги" = v_security_id;

        -- Создаём запись в истории операций депозитарного счёта
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

        -- Меняем статус предложения на "Одобрено"
        UPDATE public."Предложение"
        SET "ID статуса предложения" = c_approved_status_id
        WHERE "ID предложения" = p_proposal_id;

    ELSE
        -- === ОТКЛОНЕНИЕ ===

        -- Возвращаем деньги на брокерский счёт (зачисление)
        SELECT change_brokerage_account_balance(
    p_account_id := v_brokerage_account_id,
    p_amount := v_cost,
    p_brokerage_operation_type := c_brokerage_operation_return_type_id, -- <-- Исправлено
    p_staff_id := p_employee_id
) INTO v_new_broker_operation_id;

        -- Меняем статус предложения на "Отклонено"
        UPDATE public."Предложение"
        SET "ID статуса предложения" = c_rejected_status_id
        WHERE "ID предложения" = p_proposal_id;
    END IF;

    RAISE NOTICE 'Предложение % успешно %', p_proposal_id, CASE WHEN p_verify THEN 'одобрено' ELSE 'отклонено' END;
END;
$BODY$;

ALTER FUNCTION public.process_buy_proposal(integer, integer, boolean)
    OWNER TO postgres;

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

ALTER FUNCTION public.process_sell_proposal(integer, integer, boolean)
    OWNER TO postgres;

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

CREATE OR REPLACE FUNCTION public.add_stock(
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

ALTER FUNCTION public.add_stock(character varying, character varying, numeric, numeric, integer, boolean)
    OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.change_stock_price(
    p_stock_id integer,               -- ID ценной бумаги
    p_new_price numeric(12,2)         -- Новая цена
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


-- FUNCTION: public.verify_user_passport(integer)

-- DROP FUNCTION IF EXISTS public.verify_user_passport(integer);

CREATE OR REPLACE FUNCTION public.verify_user_passport(
    p_passport_id integer)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_user_id integer;
    v_deposit_account_id integer;
    v_securities RECORD;
BEGIN
    -- Находим ID пользователя по паспорту
    SELECT "ID пользователя" INTO v_user_id
    FROM public."Паспорт"
    WHERE "ID паспорта" = p_passport_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Паспорт с ID % не найден', p_passport_id;
    END IF;

    -- Проверяем, есть ли уже депозитарный счёт у пользователя
    SELECT "ID депозитарного счёта" INTO v_deposit_account_id
    FROM public."Депозитарный счёт"
    WHERE "ID пользователя" = v_user_id;

    IF FOUND THEN
        RAISE EXCEPTION 'У пользователя с ID % уже существует депозитарный счёт. Повторная верификация паспорта невозможна.', v_user_id;
    END IF;

    -- Создаём новый депозитарный счёт
    INSERT INTO public."Депозитарный счёт" (
        "Номер депозитарного договора",
        "Дата открытия",
        "ID пользователя"
    )
    VALUES (
        'Договор № ' || to_char(current_date, 'YYYYMMDD') || '-' || v_user_id,  -- пример генерации номера
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

END;
$BODY$;

ALTER FUNCTION public.verify_user_passport(integer)
    OWNER TO postgres;

-- =========================
-- 3) ТЕСТОВЫЕ ДАННЫЕ
-- =========================

DO $$
DECLARE
    uid1 INT;  -- ID первого пользователя
    uid2 INT;  -- ID второго пользователя

    depo_id1 INT;
    depo_id2 INT;

    broker_id1 INT;
    broker_id2 INT;

    bal_id INT;
    offer_id INT;
BEGIN
    RAISE NOTICE 'Начало создания тестовых данных...';

    --------------------------------------------------------
    -- 2. СОЗДАЁМ ВТОРОГО ПОЛЬЗОВАТЕЛЯ: 1@f.com / 1
    --------------------------------------------------------
    INSERT INTO "Пользователь"
    ("Электронная почта", "Дата регистрации", "Логин", "Пароль", "ID статуса верификации", "ID статуса блокировки")
    VALUES (
        '1@f.com',
        '2025-12-13'::DATE,
        '1',
        '$2b$12$SLJKJ4d31q3acOktI7eH7eOynavGTmWUTcU2At/mCYdEPu8KLrayO',
        1,
		1
    )
    RETURNING "ID пользователя" INTO uid2;

    RAISE NOTICE 'Создан пользователь 2 (логин: 1, email: 1@f.com), ID = %', uid2;

    --------------------------------------------------------
    -- 4. ДЕПОЗИТАРНЫЙ СЧЁТ ДЛЯ ВТОРОГО ПОЛЬЗОВАТЕЛЯ
    --------------------------------------------------------
    INSERT INTO "Депозитарный счёт"
    ("Номер депозитарного договора", "Дата открытия", "ID пользователя")
    VALUES ('D200', '2025-12-13', uid2)
    RETURNING "ID депозитарного счёта" INTO depo_id2;

    --------------------------------------------------------
    -- 5. КУРСЫ ВАЛЮТ — теперь в новую таблицу currency_rate
    --------------------------------------------------------
    -- Предполагаем:
    --   "Список валют".ID = 1 → RUB
    --   "Список валют".ID = 2 → USD

    INSERT INTO currency_rate (base_currency_id, target_currency_id, rate, rate_date, rate_time)
    VALUES
        -- RUB всегда базовая, курс RUB → RUB = 1
        (1, 1, 1.00000000, CURRENT_DATE, NOW()),

        -- Основной курс: сколько RUB за 1 USD (например, 95.35)
        (1, 2, 95.35000000, CURRENT_DATE, NOW())

    ON CONFLICT (base_currency_id, target_currency_id, rate_date)
    DO UPDATE SET
        rate = EXCLUDED.rate,
        rate_time = NOW();

    --------------------------------------------------------
    -- 6. БАЛАНС ДЕПОЗИТАРНОГО СЧЁТА
    --------------------------------------------------------
    -- Для второго пользователя
    INSERT INTO "Баланс депозитарного счёта"
    ("Сумма", "ID депозитарного счёта", "ID пользователя", "ID ценной бумаги")
    VALUES
        (5, depo_id2, uid2, 1),
        (20, depo_id2, uid2, 2),
        (52, depo_id2, uid2, 3);

    --------------------------------------------------------
    -- 7. БРОКЕРСКИЙ СЧЁТ
    --------------------------------------------------------

    -- Для второго пользователя
    INSERT INTO "Брокерский счёт"
    ("Баланс", "ИНН", "БИК", "ID банка", "ID пользователя", "ID валюты")
    VALUES (50000.00, '', '044525222', 1, uid2, 1)
    RETURNING "ID брокерского счёта" INTO broker_id2;

    --------------------------------------------------------
    -- 8. ПРЕДЛОЖЕНИЯ НА ПРОДАЖУ/ПОКУПКУ
    --------------------------------------------------------

    RAISE NOTICE 'Тестовые данные успешно созданы!';
    RAISE NOTICE 'Пользователь 2 (1@f.com): ID = %', uid2;

END $$;


INSERT INTO public."История операций бр. счёта" (
    "Сумма операции",
    "Время",
    "ID брокерского счёта",
    "ID сотрудника",
    "ID типа операции бр. счёта"
) VALUES
    -- Счёт 1
    (100000.00, '2025-10-15 09:30:00', 1, 1, 1),  -- Пополнение 100 000 ₽
    (-15000.00, '2025-10-20 14:22:10', 1, 2, 2),  -- Списание 15 000 ₽
    (50000.00,  '2025-11-05 11:15:00', 1, 1, 1),  -- Пополнение 50 000 ₽
    (-8000.50,  '2025-11-12 16:45:30', 1, 3, 2);  -- Списание 8 000.50 ₽


------------------------------------------------------------
-- 4. ВЫВОД РЕЗУЛЬТАТОВ ТЕСТОВ
------------------------------------------------------------

-- Один запрос — все результаты сразу
WITH results AS (
    SELECT 'get_currency_rate_RUB' AS function_name,
           get_currency_rate(1)    AS result
    UNION ALL
    SELECT 'get_currency_rate_USD',
           get_currency_rate(2)
    UNION ALL
    SELECT 'calc_depo_value',
           calc_depo_value(1, 1, 2)
    UNION ALL
    SELECT 'calc_total_account_value',
           calc_total_account_value(1, 1)
    UNION ALL
    SELECT 'calc_offer_value',
           calc_offer_value(1)
    UNION ALL
    SELECT 'calc_depo_growth',
           calc_depo_growth(1, 1, '1 day')
    UNION ALL
    SELECT 'calc_stock_growth',
           calc_stock_growth(1)
)
SELECT function_name, result::text AS result_value      -- приводим к тексту, т.к. типы возврата могут отличаться
FROM results
UNION ALL
SELECT 'Баланс депозитарного счёта' AS function_name,
       to_jsonb(t)::text AS result_value
FROM "Баланс депозитарного счёта" t
ORDER BY function_name;