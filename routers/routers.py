from fastapi import Depends, HTTPException, APIRouter
from typing import List
from sqlalchemy import text, insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from db.session import get_db
from db.auth import get_current_user
from pydantic import BaseModel, Field, PositiveFloat, validator, field_validator
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
        raise HTTPException(status_code=403, detail="Доступ запрещён")

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


@brokerage_accounts_router.get("/portfolio/securities")
async def get_portfolio_securities(
    current_user = Depends(get_current_user),  # ← берём пользователя из токена
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]  # или current_user.user_id — как у тебя в модели

    query = text("SELECT * FROM get_user_securities(:user_id)")
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


@brokerage_accounts_router.get("/offers")
async def get_user_offers(
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]

    query = text("SELECT * FROM get_user_offers(:user_id)")
    result = await db.execute(query, {"user_id": user_id})
    rows = result.fetchall()

    return [dict(row._mapping) for row in rows]


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
        raise HTTPException(status_code=404, detail="Счёт не найден")

    # Основной запрос
    query = text("""
        SELECT * 
        FROM get_brokerage_account_operations(:account_id)
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
        raise HTTPException(status_code=404, detail="Счёт не найден")

    return {
        "id": row.id,
        "balance": float(row.balance),
        "currency": row.currency
    }


from pydantic import BaseModel, Field, PositiveFloat, validator
from decimal import Decimal
from typing import Literal


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


@brokerage_accounts_router.post("/brokerage-accounts/{account_id}/balance-change-requests")
async def create_balance_change_request(
    account_id: int,
    data: BalanceChangeRequestCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    # (опционально) проверка, что счёт принадлежит пользователю
    account = await db.scalar(
        select(BrokerageAccount)
        .where(
            BrokerageAccount.id == account_id,
            BrokerageAccount.user_id == user["id"]
        )
    )

    if not account:
        raise HTTPException(status_code=404, detail="Счёт не найден")

    request = BrockerageBalanceChangeRequest(
        brokerage_account_id=account_id,
        status_id=1,  # ⬅️ PENDING
        amount=data.amount,
    )

    db.add(request)
    await db.commit()

    return {"status": "ok"}