from fastapi import Depends, HTTPException, APIRouter, status
from typing import List
from sqlalchemy import text, insert, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from db.session import get_db
from db.auth import get_current_user
from pydantic import BaseModel, Field, PositiveFloat, validator, field_validator
from decimal import Decimal
from datetime import datetime, date
from db.models.models import (
    Bank,
    BrokerageAccount,
    BrokerageAccountHistory,
    BrokerageAccountOperationType,
    Currency,
    CurrencyRate,
    DepositoryAccount,
    DepositoryAccountBalance,
    DepositoryAccountHistory,
    DepositoryAccountOperationType,
    Dividend,
    EmploymentStatus,
    Passport,
    PriceHistory,
    Proposal,
    ProposalType,
    Security,
    Staff,
    User,
    VerificationStatus
)

brokerage_accounts_router = APIRouter(
    prefix="/api", tags=["Brokerage Accounts"]
)


class BrokerageAccountOut(BaseModel):
    account_id: int
    balance: float
    inn: str
    bik: str
    bank_name: str
    currency_symbol: str

    class Config:
        from_attributes = True


@brokerage_accounts_router.get(
    "/brokerage-accounts",
    response_model=List[BrokerageAccountOut]
)
async def get_user_brokerage_accounts(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user["role"] != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    user_id = current_user["id"]

    result = await db.execute(
        select(
            BrokerageAccount.id.label("account_id"),
            BrokerageAccount.balance.label("balance"),
            BrokerageAccount.inn.label("inn"),
            BrokerageAccount.bik.label("bik"),
            Bank.name.label("bank_name"),
            Currency.symbol.label("currency_symbol"),
        )
        .join(Bank, Bank.id == BrokerageAccount.bank_id)
        .join(Currency, Currency.id == BrokerageAccount.currency_id)
        .where(BrokerageAccount.user_id == user_id)
        .order_by(BrokerageAccount.id)
    )

    return result.mappings().all()

class SecuritiesResponse(BaseModel):
    security_name: str
    lot_size: float
    isin: str
    has_dividends: bool
    amount: float
    currency_code: str
    currency_symbol: str

    class Config:
        from_attributes = True



@brokerage_accounts_router.get("/portfolio/securities", response_model=List[SecuritiesResponse])
async def get_portfolio_securities(
    current_user = Depends(get_current_user),  # ← берём пользователя из токена
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]

    query = text("SELECT * FROM get_user_securities(:user_id) WHERE amount > 0")
    result = await db.execute(query, {"user_id": user_id})
    securities = result.fetchall()

    securities_list = [
        {
            "security_name": row.security_name,
            "lot_size": float(row.lot_size) if row.lot_size is not None else None,
            "isin": row.isin,
            "has_dividends": row.has_dividends,
            "amount": float(row.amount) if row.amount is not None else None,
            "currency_code": row.currency_code,
            "currency_symbol": row.currency_symbol,
        }
        for row in securities
    ]
    return securities_list


class OfferResponse(BaseModel):
    id: int
    offer_type: str
    security_name: str
    quantity: float
    proposal_status: int

@brokerage_accounts_router.get(
    "/offers",
    response_model=list[OfferResponse]
)
async def get_user_offers(
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]

    result = await db.execute(
        text("SELECT * from get_user_offers(:user_id)"),
        {"user_id": user_id}
    )

    return [
        OfferResponse(**row._mapping)
        for row in result.fetchall()
    ]


class OfferCreate(BaseModel):
    account_id: int
    security_id: int
    quantity: Decimal = Field(..., gt=0, decimal_places=2)
    proposal_type_id: int  # 1 = купить, 2 = продать


@brokerage_accounts_router.post(
    "/offers",
    response_model=OfferResponse,
    status_code=status.HTTP_201_CREATED
)
async def create_offer(
    data: OfferCreate,
    db: AsyncSession = Depends(get_db),
    current_user = Depends(get_current_user),
):
    user_id = current_user["id"]

    # 1. Проверка счёта
    account = await db.scalar(
        select(BrokerageAccount)
        .where(
            BrokerageAccount.id == data.account_id,
            BrokerageAccount.user_id == user_id
        )
    )
    if not account:
        raise HTTPException(404, "Брокерский счёт не найден")

    # 2. Проверка бумаги
    security = await db.scalar(
        select(Security).where(Security.id == data.security_id)
    )
    if not security:
        raise HTTPException(404, "Ценная бумага не найдена")

    # 3. Проверка валюты
    if account.currency_id != security.currency_id:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Валюта брокерского счёта не совпадает с валютой бумаги"
        )

    # 4. Проверка типа предложения
    proposal_type = await db.scalar(
        select(ProposalType)
        .where(ProposalType.id == data.proposal_type_id)
    )
    if not proposal_type:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Некорректный тип предложения")

    # 5. Создание предложения (ВНЕ if)
    if data.proposal_type_id == 1:
        sql = text("SELECT add_buy_proposal(:security_id, :account_id, :lot_amount)")
    elif data.proposal_type_id == 2:
        sql = text("SELECT add_sell_proposal(:security_id, :account_id, :lot_amount)")
    else:
        raise HTTPException(400, "Некорректный тип предложения")

    await db.execute(sql, {
        "security_id": data.security_id,
        "account_id": data.account_id,
        "lot_amount": data.quantity
    })

    await db.commit()

    # 6. Возвращаем созданное предложение в формате OfferResponse
    result = await db.execute(
        text("SELECT * from get_user_offers(:user_id) LIMIT 1"),{"user_id": user_id}
    )

    row = result.fetchone()
    if not row:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Предложение создано, но не найдено")

    return OfferResponse(**row._mapping)


@brokerage_accounts_router.get("/exchange/stocks")
async def get_exchange_stocks(
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(text("SELECT * FROM get_exchange_stocks()"))
    rows = result.fetchall()

    return [dict(row._mapping) for row in rows]


@brokerage_accounts_router.get("/brokerage-accounts/{account_id}/operations")
async def get_brokerage_account_operations(
    account_id: int,
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # (опционально) проверка прав — счёт принадлежит пользователю
    user_id = current_user["id"]

    check_query = text("""
        SELECT 1
        FROM "Брокерский счёт"
        WHERE "ID брокерского счёта" = :account_id
          AND "ID пользователя" = :user_id
    """)

    check = await db.execute(
        check_query,
        {"account_id": account_id, "user_id": user_id}
    )

    if check.first() is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Счёт не найден")

    # Основной запрос
    query = text("""
        SELECT * 
        FROM get_brokerage_account_operations(:account_id)
        WHERE "Тип операции" != 'Empty'
    """)

    result = await db.execute(query, {"account_id": account_id})
    rows = result.fetchall()
    return [dict(row._mapping) for row in rows]


@brokerage_accounts_router.get("/brokerage-accounts/{account_id}")
async def get_brokerage_account(
    account_id: int,
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]

    query = text("""
        SELECT
            b."ID брокерского счёта" AS id,
            b."Баланс" AS balance,
            c."Символ" AS currency
        FROM "Брокерский счёт" b
        JOIN "Список валют" c
            ON c."ID валюты" = b."ID валюты"
        WHERE b."ID брокерского счёта" = :account_id
          AND b."ID пользователя" = :user_id
    """)

    result = await db.execute(
        query,
        {"account_id": account_id, "user_id": user_id}
    )

    row = result.first()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Счёт не найден")

    return {
        "id": row.id,
        "balance": float(row.balance),
        "currency": row.currency
    }



class BalanceChangeRequestCreate(BaseModel):
    amount: Decimal = Field(
        ...,
        decimal_places=2,
        description="Сумма изменения баланса. Положительная — пополнение, отрицательная — списание"
    )

    @field_validator("amount")
    @classmethod
    def amount_not_zero_and_two_decimals(cls, v: Decimal) -> Decimal:
        if v == 0:
            raise ValueError("Сумма не может быть равна нулю")
        return v.quantize(Decimal("0.01"))

    model_config = {
        "json_schema_extra": {
            "example": {
                "amount": "15000.00"
            }
        }
    }

class VerificationStatusResponse(BaseModel):
    is_verified: bool


@brokerage_accounts_router.get(
    "/user_verification_status/{user_id}",
    response_model=VerificationStatusResponse
)
async def get_verification_status(
    user_id: int,
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Проверяет статус верификации пользователя по ID.
    Доступно только авторизованным пользователям.
    """
    if current_user["id"] != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Вы можете проверять только свой статус верификации"
        )

    try:
        query = text("SELECT public.check_user_verification_status(:user_id)")
        result = await db.execute(query, {"user_id": user_id})
        is_verified_raw = result.scalar()

        if is_verified_raw is None:
            raise ValueError("Функция вернула NULL")

        return VerificationStatusResponse(is_verified=bool(is_verified_raw))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка при проверке статуса верификации: {str(e)}"
        )


@brokerage_accounts_router.post("/brokerage-accounts/{account_id}/balance-change-requests")
async def create_balance_change_request(
    account_id: int,
    data: BalanceChangeRequestCreate,
    db: AsyncSession = Depends(get_db),
    current_user = Depends(get_current_user),
):
    # 1. Находим счёт и проверяем принадлежность
    account = await db.scalar(
        select(BrokerageAccount)
        .where(
            BrokerageAccount.id == account_id,
            BrokerageAccount.user_id == current_user["id"]
        )
    )
    if not account:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Счёт не найден или не принадлежит вам")

    # 2. Предварительная проверка на недостаток средств (на случай, если кто-то обошёл фронт)
    if data.amount < 0 and account.balance + data.amount < 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Недостаточно средств на счёте")

    # 3. Выполняем изменение баланса и запись в историю одной атомарной функцией в БД

    query = text(
        f"SELECT change_brokerage_account_balance(:account_id, :amount, :brokerage_operation_id, :staff_id);"
    )
    try:
        await db.execute(query, {
            "account_id": account_id,
            "amount": data.amount,
            "staff_id": 5,
            "brokerage_operation_id": 1 if data.amount > 0 else 2
        })
        await db.commit()
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    await db.refresh(account)
    return {
        "status": "ok",
        "message": "Баланс успешно изменён",
        "new_balance": float(account.balance)
    }


class CurrencyResponse(BaseModel):
    id: int
    code: str
    symbol: str

    class Config:
        from_attributes = True


@brokerage_accounts_router.get("/currencies", response_model=list[CurrencyResponse])
async def get_currencies(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Currency))
    currencies = result.scalars().all()

    if not currencies:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="В базе данных отсутствуют записи о валютах. Добавьте хотя бы одну валюту в таблицу \"Список валют\"."
        )

    return [CurrencyResponse(id=c.id, code=c.code, symbol=c.symbol) for c in currencies]


class StockCreate(BaseModel):
    ticker: str
    isin: str
    lot_size: Decimal = Decimal("1.00")
    price: Decimal
    currency_id: int
    has_dividends: bool = False

@brokerage_accounts_router.post("/exchange/stocks", status_code=status.HTTP_201_CREATED)
async def create_stock(
    data: StockCreate,
    db: AsyncSession = Depends(get_db),
):
    try:
        # Вызываем нашу PL/pgSQL функцию add_stock, которая делает все проверки и вставки
        result = await db.execute(
            text("""
                SELECT public.add_stock(
                    :ticker,
                    :isin,
                    :lot_size,
                    :price,
                    :currency_id,
                    :has_dividends
                )
            """),
            {
                "ticker": data.ticker,
                "isin": data.isin,
                "lot_size": data.lot_size,
                "price": data.price,
                "currency_id": data.currency_id,
                "has_dividends": data.has_dividends,
            }
        )
        await db.commit()
        new_security_id = result.scalar_one()

        return {
            "message": "Акция успешно добавлена",
            "id": new_security_id,
        }

    except Exception as e:
        # Перехватываем ошибки из функции (RAISE EXCEPTION в PL/pgSQL)
        if "RAISE" in str(e) or "Exception" in str(e):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e.orig))
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Ошибка при добавлении акции")


class CheckBannedStatus(BaseModel):
    is_banned: bool

    class Config:
        from_attributes = True


@brokerage_accounts_router.get(
    "/user_ban_status/{user_id}",
    response_model=CheckBannedStatus,
    status_code=status.HTTP_200_OK
)
async def get_banned_status(
    user_id: int,
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(
        select(User.block_status_id)
        .where(User.id == user_id)
    )
    row = result.first()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )
    ban_status_id = row[0]
    return CheckBannedStatus(is_banned=(ban_status_id == 2))


# Схема для одной операции
class DepositaryOperation(BaseModel):
    id: int
    amount: Decimal  # "Сумма операции"
    time: datetime   # "Время"
    security_name: str  # "Наименование ценной бумаги" (получаем из JOIN с "Список ценных бумаг")
    operation_type: str  # "Тип операции" (из "Тип операции депозитарного счёта")

    class Config:
        from_attributes = True  # Позволяет использовать объекты ORM (альясы, если нужно)

# Схема для депозитарного счёта
class DepositaryAccount(BaseModel):
    id: int
    contract_number: str  # "Номер депозитарного договора"
    opening_date: date     # "Дата открытия" (в формате строки, например, "2025-01-01")

    class Config:
        from_attributes = True


class DepositaryBalance(BaseModel):
    security_name: str
    amount: Decimal

# Схема для ответа от эндпоинта
class DepositaryAccountResponse(BaseModel):
    account: DepositaryAccount
    balance: List[DepositaryBalance]
    operations: List[DepositaryOperation]


@brokerage_accounts_router.get(
    "/users/me/depositary-account",
    response_model=DepositaryAccountResponse
)
async def get_depositary_account(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]

    # ------------------------------------------------------------------
    # 1. Получаем депозитарный счёт пользователя
    # ------------------------------------------------------------------
    account_query = text("""
        SELECT
            "ID депозитарного счёта"        AS id,
            "Номер депозитарного договора" AS contract_number,
            "Дата открытия"                AS opening_date
        FROM public."Депозитарный счёт"
        WHERE "ID пользователя" = :user_id
    """)

    result = await db.execute(account_query, {"user_id": user_id})
    account_row = result.mappings().first()

    if not account_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Депозитарный счёт не найден"
        )

    account = DepositaryAccount(**account_row)

    # ------------------------------------------------------------------
    # 2. Баланс депозитарного счёта
    # ------------------------------------------------------------------
    balance_query = text("""
        SELECT
            ss."Наименование" AS security_name,
            b."Сумма"         AS amount
        FROM public."Баланс депозитарного счёта" b
        JOIN public."Список ценных бумаг" ss
            ON b."ID ценной бумаги" = ss."ID ценной бумаги"
        WHERE
            b."ID депозитарного счёта" = :account_id
            AND b."ID пользователя" = :user_id
        ORDER BY ss."Наименование"
    """)

    result_balance = await db.execute(
        balance_query,
        {
            "account_id": account.id,
            "user_id": user_id
        }
    )

    balance = [
        DepositaryBalance(**row)
        for row in result_balance.mappings().all()
    ]

    # ------------------------------------------------------------------
    # 3. История операций депозитарного счёта
    # ------------------------------------------------------------------
    operations_query = text("""
        SELECT
            ho."ID операции деп. счёта" AS id,
            ho."Сумма операции"         AS amount,
            ho."Время"                  AS time,
            ss."Наименование"           AS security_name,
            tot."Тип"                   AS operation_type
        FROM public."История операций деп. счёта" ho
        JOIN public."Список ценных бумаг" ss
            ON ho."ID ценной бумаги" = ss."ID ценной бумаги"
        JOIN public."Тип операции депозитарного счёта" tot
            ON ho."ID типа операции деп. счёта" = tot."ID типа операции деп. счёта"
        WHERE
            ho."ID депозитарного счёта" = :account_id
            AND ho."ID пользователя" = :user_id
        ORDER BY ho."Время" DESC
    """)

    result_ops = await db.execute(
        operations_query,
        {
            "account_id": account.id,
            "user_id": user_id
        }
    )

    operations = [
        DepositaryOperation(**row)
        for row in result_ops.mappings().all()
    ]

    # ------------------------------------------------------------------
    # 4. Ответ
    # ------------------------------------------------------------------
    return DepositaryAccountResponse(
        account=account,
        balance=balance,
        operations=operations
    )
