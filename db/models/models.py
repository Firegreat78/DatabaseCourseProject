# db/models/models.py
from __future__ import annotations

from sqlalchemy import String, Integer, Numeric, Boolean, Date, ForeignKey, Column, ForeignKeyConstraint, TIMESTAMP
from sqlalchemy.orm import DeclarativeBase, registry, Mapped, relationship

# Создаём реестр (можно и без него, но с ним типы работают лучше)
reg = registry()


class Base(DeclarativeBase):
    registry = reg


class DepositoryAccountOperationType(Base):
    __tablename__ = "Тип операции депозитарного счёта"

    id = Column("ID типа операции деп. счёта", Integer, primary_key=True, nullable=False)
    type = Column("Тип", String(15), nullable=False)

    def __repr__(self):
        return f"<DepositoryAccountOperationType(id={self.id}, type='{self.type}')>"


class BrokerageAccountOperationType(Base):
    __tablename__ = "Тип операции брокерского счёта"

    id = Column("ID типа операции бр. счёта", Integer, primary_key=True, nullable=False)
    type_name = Column("Тип", String(15), nullable=False)

    def __repr__(self):
        return f"<BrokerageAccountOperationType(id={self.id}, type='{self.type_name}')>"


class ProposalType(Base):
    __tablename__ = "Тип предложения"

    id = Column("ID типа предложения", Integer, primary_key=True, nullable=False)
    type = Column("Тип", String(15), nullable=False)

    def __repr__(self):
        return f"<ProposalType(id={self.id}, type='{self.type}')>"


class VerificationStatus(Base):
    __tablename__ = "Статус верификации"

    id = Column("ID статуса верификации", Integer, primary_key=True, nullable=False)
    status = Column("Статус верификации", String(20), nullable=False)

    def __repr__(self):
        return f"<VerificationStatus(id={self.id}, status='{self.status}')>"


class Security(Base):
    __tablename__ = "Список ценных бумаг"

    id = Column("ID ценной бумаги", Integer, primary_key=True, nullable=False)
    name = Column("Наименование", String(120), nullable=False)
    lot_size = Column("Размер лота", Numeric(12, 2), nullable=False)
    isin = Column("ISIN", String(40), nullable=False)
    dividend_payment = Column("Выплата дивидендов", Boolean, nullable=False)
    currency_id = Column("ID валюты", Integer, ForeignKey("Список валют.ID валюты", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)

    currency = relationship("Currency", backref="securities")

    def __repr__(self):
        return f"<Security(id={self.id}, name='{self.name}', lot_size={self.lot_size}, isin='{self.isin}', dividend_payment={self.dividend_payment}, currency_id={self.currency_id})>"


class Currency(Base):
    __tablename__ = "Список валют"

    id = Column("ID валюты", Integer, primary_key=True, nullable=False)
    name = Column("Наименование валюты", String(30), nullable=False)

    def __repr__(self):
        return f"<Currency(id={self.id}, name='{self.name}')>"


class EmploymentStatus(Base):
    __tablename__ = "Статус трудоустройства"

    id = Column("ID статуса трудоустройства", Integer, primary_key=True, nullable=False)
    status = Column("Статус трудоустройства", String(120), nullable=False)

    def __repr__(self):
        return f"<EmploymentStatus(id={self.id}, status='{self.status}')>"


class Bank(Base):
    __tablename__ = "Банк"

    id = Column("ID банка", Integer, primary_key=True, nullable=False)
    name = Column("Наименование", String(120), nullable=False)
    inn = Column("ИНН", String(40), nullable=False)
    ogrn = Column("ОГРН", String(40), nullable=False)
    bik = Column("БИК", String(40), nullable=False)
    license_expiry = Column("Срок действия лицензии", Date, nullable=False)

    def __repr__(self):
        return f"<Bank(id={self.id}, name='{self.name}', inn='{self.inn}', ogrn='{self.ogrn}', bik='{self.bik}', license_expiry={self.license_expiry})>"


class User(Base):
    __tablename__ = "Пользователь"

    id = Column("ID пользователя", Integer, primary_key=True, nullable=False)
    email = Column("Электронная почта", String(40), nullable=False)
    registration_date = Column("Дата регистрации", Date, nullable=False)
    login = Column("Логин", String(30), nullable=False)
    password = Column("Пароль", String(60), nullable=False)
    verification_status_id = Column("ID статуса верификации", Integer, ForeignKey("Статус верификации.ID статуса верификации", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)

    verification_status = relationship("VerificationStatus", backref="users")

    def __repr__(self):
        return f"<User(id={self.id}, email='{self.email}', login='{self.login}', verification_status_id={self.verification_status_id})>"


class Staff(Base):
    __tablename__ = "Персонал"

    id = Column("ID сотрудника", Integer, primary_key=True, nullable=False)
    contract_number = Column("Номер трудового договора", String(40), nullable=False)
    login = Column("Логин", String(30), nullable=False)
    password = Column("Пароль", String(60), nullable=False)
    rights_level = Column("Уровень прав", String(30), nullable=False)
    employment_status_id = Column("ID статуса трудоустройства", Integer, ForeignKey("Статус трудоустройства.ID статуса трудоустройства", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)

    employment_status = relationship("EmploymentStatus", backref="staff_members")

    def __repr__(self):
        return f"<Staff(id={self.id}, contract_number='{self.contract_number}', login='{self.login}', rights_level='{self.rights_level}', employment_status_id={self.employment_status_id})>"


class Proposal(Base):
    __tablename__ = "Предложение"

    id = Column("ID предложения", Integer, primary_key=True, nullable=False)
    amount = Column("Сумма", Numeric(12,2), nullable=False)
    security_id = Column("ID ценной бумаги", Integer, ForeignKey("Список ценных бумаг.ID ценной бумаги", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)
    user_id = Column("ID пользователя", Integer, ForeignKey("Пользователь.ID пользователя", ondelete="CASCADE", onupdate="CASCADE"), nullable=False)
    proposal_type_id = Column("ID типа предложения", Integer, ForeignKey("Тип предложения.ID типа предложения", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)

    security = relationship("Security", backref="proposals")
    user = relationship("User", backref="proposals")
    proposal_type = relationship("ProposalType", backref="proposals")

    def __repr__(self):
        return f"<Proposal(id={self.id}, amount={self.amount}, security_id={self.security_id}, user_id={self.user_id}, proposal_type_id={self.proposal_type_id})>"


class BrokerageAccount(Base):
    __tablename__ = "Брокерский счёт"

    id = Column("ID брокерского счёта", Integer, primary_key=True, nullable=False)
    balance = Column("Баланс", Numeric(12,2), nullable=False)
    inn = Column("ИНН", String(30), nullable=False)
    bik = Column("БИК", String(30), nullable=False)
    bank_id = Column("ID банка", Integer, ForeignKey("Банк.ID банка", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)
    currency_id = Column("ID валюты", Integer, ForeignKey("Список валют.ID валюты", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)

    bank = relationship("Bank", backref="brokerage_accounts")
    currency = relationship("Currency", backref="brokerage_accounts")

    def __repr__(self):
        return f"<BrokerageAccount(id={self.id}, balance={self.balance}, inn='{self.inn}', bik='{self.bik}', bank_id={self.bank_id}, currency_id={self.currency_id})>"


class DepositoryAccount(Base):
    __tablename__ = "Депозитарный счёт"

    id = Column("ID депозитарного счёта", Integer, primary_key=True, nullable=False)
    contract_number = Column("Номер депозитарного договора", String(120), nullable=False)
    opening_date = Column("Дата открытия", Date, nullable=False)
    user_id = Column("ID пользователя", Integer, ForeignKey("Пользователь.ID пользователя", ondelete="CASCADE", onupdate="CASCADE"), nullable=False)

    user = relationship("User", backref="depository_accounts")

    def __repr__(self):
        return f"<DepositoryAccount(id={self.id}, contract_number='{self.contract_number}', opening_date={self.opening_date}, user_id={self.user_id})>"


class Dividend(Base):
    __tablename__ = "Дивиденды"

    id = Column("ID дивидинда", Integer, primary_key=True, nullable=False)
    date = Column("Дата", Date, nullable=False)
    amount = Column("Сумма", Numeric(12,2), nullable=False)
    security_id = Column("ID ценной бумаги", Integer, ForeignKey("Список ценных бумаг.ID ценной бумаги", ondelete="CASCADE", onupdate="CASCADE"), nullable=False)

    security = relationship("Security", backref="dividends")

    def __repr__(self):
        return f"<Dividend(id={self.id}, date={self.date}, amount={self.amount}, security_id={self.security_id})>"


class Passport(Base):
    __tablename__ = "Паспорт"

    id = Column("ID паспорта", Integer, primary_key=True, nullable=False)
    last_name = Column("Фамилия", String(40), nullable=False)
    first_name = Column("Имя", String(40), nullable=False)
    patronymic = Column("Отчество", String(40), nullable=False)
    series = Column("Серия", String(4), nullable=False)
    number = Column("Номер", String(6), nullable=False)
    gender = Column("Пол", String(1), nullable=False)
    registration_place = Column("Место прописки", String(30), nullable=False)
    birth_date = Column("Дата рождения", Date, nullable=False)
    birth_place = Column("Место рождения", String(30), nullable=False)
    issue_date = Column("Дата выдачи", Date, nullable=False)
    issued_by = Column("Кем выдан", String(50), nullable=False)
    is_actual = Column("Актуальность", Boolean, nullable=False)
    user_id = Column("ID пользователя", Integer, ForeignKey("Пользователь.ID пользователя", ondelete="CASCADE", onupdate="CASCADE"), nullable=False)

    user = relationship("User", backref="passports")

    def __repr__(self):
        return f"<Passport(id={self.id}, last_name='{self.last_name}', first_name='{self.first_name}', user_id={self.user_id})>"


class BrokerageAccountHistory(Base):
    __tablename__ = "История операций бр. счёта"

    id = Column("ID операции бр. счёта", Integer, primary_key=True, nullable=False)
    amount = Column("Сумма операции", Numeric(12, 2), nullable=False)
    time = Column("Время", TIMESTAMP(6), nullable=False)
    brokerage_account_id = Column("ID брокерского счёта", Integer, nullable=False)
    staff_id = Column(
        "ID сотрудника",
        Integer,
        ForeignKey("Персонал.ID сотрудника", ondelete="RESTRICT", onupdate="RESTRICT"),
        nullable=False,
    )
    operation_type_id = Column(
        "ID типа операции бр. счёта",
        Integer,
        ForeignKey("Тип операции брокерского счёта.ID типа операции бр. счёта",
                   ondelete="RESTRICT", onupdate="RESTRICT"),
        nullable=False,
    )

    __table_args__ = (
        ForeignKeyConstraint(
            ["ID брокерского счёта"],
            ["Брокерский счёт.ID брокерского счёта"],
            ondelete="CASCADE",
            onupdate="CASCADE",
            name="Relationship23",
        ),
    )

    brokerage_account = relationship("BrokerageAccount", backref="history")
    staff = relationship("Staff", backref="brokerage_operations")
    operation_type = relationship(
        "BrokerageAccountOperationType",
        backref="operations",
        primaryjoin=(
                operation_type_id ==
                BrokerageAccountOperationType.__table__.c["ID типа операции бр. счёта"]
        ),
        foreign_keys=[operation_type_id],
    )

    def __repr__(self):
        return f"<BrokerageAccountHistory(id={self.id}, amount={self.amount}, brokerage_account_id={self.brokerage_account_id}, time={self.time})>"


class DepositoryAccountHistory(Base):
    __tablename__ = "История операций деп. счёта"

    id = Column("ID операции деп. счёта", Integer, primary_key=True, nullable=False)
    amount = Column("Сумма операции", Numeric(12, 2), nullable=False)
    time = Column("Время", TIMESTAMP(6), nullable=False)
    depository_account_id = Column("ID депозитарного счёта", Integer, nullable=False)
    user_id = Column("ID пользователя", Integer, nullable=False)
    security_id = Column(
        "ID ценной бумаги",
        Integer,
        ForeignKey("Список ценных бумаг.ID ценной бумаги", ondelete="RESTRICT", onupdate="RESTRICT"),
        nullable=False,
    )
    staff_id = Column(
        "ID сотрудника",
        Integer,
        ForeignKey("Персонал.ID сотрудника", ondelete="RESTRICT", onupdate="RESTRICT"),
        nullable=False,
    )
    brokerage_operation_id = Column("ID операции бр. счёта", Integer, nullable=False)
    brokerage_account_id = Column("ID брокерского счёта", Integer, nullable=False)
    operation_type_id = Column(
        "ID типа операции деп. счёта",
        Integer,
        ForeignKey("Тип операции депозитарного счёта.ID типа операции деп. счёта",
                   ondelete="RESTRICT", onupdate="RESTRICT"),
        nullable=False,
    )

    __table_args__ = (
        # FK: (ID депозитарного счёта, ID пользователя)
        ForeignKeyConstraint(
            ["ID депозитарного счёта", "ID пользователя"],
            ["Депозитарный счёт.ID депозитарного счёта", "Депозитарный счёт.ID пользователя"],
            ondelete="CASCADE",
            onupdate="CASCADE",
            name="Relationship15"
        ),
        # FK: (ID операции бр. счёта, ID брокерского счёта)
        ForeignKeyConstraint(
            ["ID операции бр. счёта", "ID брокерского счёта"],
            [
                BrokerageAccountHistory.__table__.c["ID операции бр. счёта"],
                BrokerageAccountHistory.__table__.c["ID брокерского счёта"]
            ],
            ondelete="CASCADE",
            onupdate="CASCADE",
            name="Relationship31"
        ),
    )

    security = relationship("Security", backref="depository_operations")
    staff = relationship("Staff", backref="depository_operations")
    operation_type = relationship(
        "DepositoryAccountOperationType",
        backref="operations",
        primaryjoin=(
                operation_type_id ==
                DepositoryAccountOperationType.__table__.c["ID типа операции деп. счёта"]
        ),
        foreign_keys=[operation_type_id],
    )
    depository_account = relationship("DepositoryAccount", backref="operations")
    brokerage_operation = relationship("BrokerageAccountHistory", backref="linked_depository_operations")

    def __repr__(self):
        return (
            f"<DepositoryAccountHistory(id={self.id}, amount={self.amount}, "
            f"da_id={self.depository_account_id}, user_id={self.user_id}, time={self.time})>"
        )


class DepositoryAccountBalance(Base):
    __tablename__ = "Баланс депозитарного счёта"

    id = Column("ID баланса депозитарного счёта", Integer, primary_key=True, nullable=False)
    amount = Column("Сумма", Numeric(12,2), nullable=False)
    depository_account_id = Column("ID депозитарного счёта", Integer, nullable=False)
    user_id = Column("ID пользователя", Integer, nullable=False)
    security_id = Column("ID ценной бумаги", Integer, ForeignKey("Список ценных бумаг.ID ценной бумаги", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)

    __table_args__ = (
        ForeignKeyConstraint(
            ["ID депозитарного счёта", "ID пользователя"],
            ["Депозитарный счёт.ID депозитарного счёта", "Депозитарный счёт.ID пользователя"],
            ondelete="CASCADE",
            onupdate="CASCADE",
            name="Relationship14"
        ),
    )

    security = relationship("Security", backref="depository_balances")
    depository_account = relationship("DepositoryAccount", backref="balances")

    def __repr__(self):
        return f"<DepositoryAccountBalance(id={self.id}, amount={self.amount}, da_id={self.depository_account_id}, user_id={self.user_id}, security_id={self.security_id})>"


class PriceHistory(Base):
    __tablename__ = "История цены"

    id = Column("ID зап. ист. цены", Integer, primary_key=True, nullable=False)
    time = Column("Время", TIMESTAMP(6), nullable=False)
    open_price = Column("Цена открытия", Numeric(12,2), nullable=False)
    close_price = Column("Цена закрытия", Numeric(12,2), nullable=False)
    min_price = Column("Цена минимальная", Numeric(12,2), nullable=False)
    max_price = Column("Цена максимальная", Numeric(12,2), nullable=False)
    security_id = Column("ID ценной бумаги", Integer, ForeignKey("Список ценных бумаг.ID ценной бумаги", ondelete="RESTRICT", onupdate="RESTRICT"), nullable=False)

    security = relationship("Security", backref="price_history")

    def __repr__(self):
        return f"<PriceHistory(id={self.id}, time={self.time}, open={self.open_price}, close={self.close_price}, security_id={self.security_id})>"


class CurrencyRates(Base):
    __tablename__ = "currency_rates"

    id = Column("id", Integer, primary_key=True, nullable=False, autoincrement=True)
    currency_code = Column("Код валюты", String(30), nullable=False)
    rate = Column("Курс", Numeric(12,4), nullable=False)
    time = Column("Время", TIMESTAMP(6), nullable=False)

    def __repr__(self):
        return f"<CurrencyRates(id={self.id}, currency_code='{self.currency_code}', rate={self.rate}, time={self.time})>"