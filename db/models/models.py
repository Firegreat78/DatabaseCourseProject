# db/models/models.py
from __future__ import annotations

from datetime import date
from typing import List

from sqlalchemy import String, Integer, Numeric, Boolean, Date
from sqlalchemy.orm import DeclarativeBase, mapped_column, registry, Mapped

# Создаём реестр (можно и без него, но с ним типы работают лучше)
reg = registry()


class Base(DeclarativeBase):
    registry = reg

# ===================================================================
#                     СПРАВОЧНЫЕ ТАБЛИЦЫ
# ===================================================================


class DepositAccountOperationType(Base):
    __tablename__ = "Тип операции депозитарного счёта"

    id: Mapped[int] = mapped_column(
        "ID типа операции деп. счёта",
        Integer,
        primary_key=True,
    )
    type_name: Mapped[str] = mapped_column("Тип", String(15), nullable=False)

    def __repr__(self) -> str:
        return f"<DepOpType {self.id}: {self.type_name}>"


class BrokerAccountOperationType(Base):
    __tablename__ = "Тип операции брокерского счёта"

    id: Mapped[int] = mapped_column(
        "ID типа операции бр. счёта",
        Integer,
        primary_key=True,
    )
    type_name: Mapped[str] = mapped_column("Тип", String(15), nullable=False)

    def __repr__(self) -> str:
        return f"<BrokerOpType {self.id}: {self.type_name}>"


class OfferType(Base):
    __tablename__ = "Тип предложения"

    id: Mapped[int] = mapped_column(
        "ID типа предложения",
        Integer,
        primary_key=True,
    )
    type_name: Mapped[str] = mapped_column("Тип", String(15), nullable=False)

    def __repr__(self) -> str:
        return f"<OfferType {self.id}: {self.type_name}>"


class VerificationStatus(Base):
    __tablename__ = "Статус верификации"

    id: Mapped[int] = mapped_column(
        "ID статуса верификации",
        Integer,
        primary_key=True,
    )
    status_name: Mapped[str] = mapped_column("Статус верификации", String(20), nullable=False)

    def __repr__(self) -> str:
        return f"<VerificationStatus {self.id}: {self.status_name}>"


class Position(Base):
    __tablename__ = "Должности"

    id: Mapped[int] = mapped_column("ID должности", Integer, primary_key=True)
    name: Mapped[str] = mapped_column("Наименование", String(20), nullable=False)
    access_level: Mapped[str] = mapped_column("Уровень прав", String(30), nullable=False)
    salary: Mapped[Numeric] = mapped_column("Заработная плата", Numeric(12, 2), nullable=False)

    def __repr__(self) -> str:
        return f"<Position {self.id}: {self.name} ({self.salary} ₽)>"


class Security(Base):
    __tablename__ = "Список ценных бумаг"

    id: Mapped[int] = mapped_column("ID ценной бумаги", Integer, primary_key=True)
    name: Mapped[str] = mapped_column("Наименование", String(120), nullable=False)
    lot_size: Mapped[Numeric] = mapped_column("Размер лота", Numeric(12, 2), nullable=False)
    isin: Mapped[str] = mapped_column("ISIN", String(40), nullable=False)
    pays_dividends: Mapped[bool] = mapped_column("Выплата дивидендов", Boolean, nullable=False)

    def __repr__(self) -> str:
        return f"<Security {self.id}: {self.name} | ISIN: {self.isin}>"


class Currency(Base):
    __tablename__ = "Список валют"

    id: Mapped[int] = mapped_column("ID валюты", Integer, primary_key=True)
    name: Mapped[str] = mapped_column("Наименование валюты", String(30), nullable=False)

    def __repr__(self) -> str:
        return f"<Currency {self.id}: {self.name}>"


class Bank(Base):
    __tablename__ = "Банк"

    id: Mapped[int] = mapped_column("ID банка", Integer, primary_key=True)
    name: Mapped[str] = mapped_column("Наименование", String(120), nullable=False)
    inn: Mapped[str] = mapped_column("ИНН", String(40), nullable=False)
    ogrn: Mapped[str] = mapped_column("ОГРН", String(40), nullable=False)
    bik: Mapped[str] = mapped_column("БИК", String(40), nullable=False)
    license_expiry_date: Mapped[date] = mapped_column("Срок действия лицензии", Date, nullable=False)

    def __repr__(self) -> str:
        return f"<Bank {self.id}: {self.name} (ИНН {self.inn})>"


# Экспортируем всё при импорте пакета
__all__: List[str] = [
    "Base",
    "DepositAccountOperationType",
    "BrokerAccountOperationType",
    "OfferType",
    "VerificationStatus",
    "Position",
    "Security",
    "Currency",
    "Bank",
]