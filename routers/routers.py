from fastapi import Depends, HTTPException, APIRouter, status
from typing import List
from sqlalchemy import text, insert, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from db.session import get_db
from db.auth import get_current_user
from pydantic import BaseModel, Field, PositiveFloat, validator, field_validator
from decimal import Decimal
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


@brokerage_accounts_router.post("/{account_id}/balance-change-requests")
async def create_balance_change_request(
    account_id: int,
    data: BalanceChangeRequestCreate,
    db: AsyncSession = Depends(get_db),
    user = Depends(get_current_user),
):
    # 1. Находим счёт и проверяем, что он принадлежит пользователю
    account = await db.scalar(
        select(BrokerageAccount)
        .where(
            BrokerageAccount.id == account_id,
            BrokerageAccount.user_id == user["id"]
        )
    )

    if not account:
        raise HTTPException(status_code=404, detail="Счёт не найден или не принадлежит вам")

    # 2. Проверяем сумму для вывода (если amount < 0)
    if data.amount < 0:
        if account.balance + data.amount < 0:  # balance + (-amount) < 0
            raise HTTPException(status_code=400, detail="Недостаточно средств на счёте")

    # 3. Изменяем баланс счёта сразу (без транзакции запроса)
    new_balance = account.balance + data.amount
    await db.execute(
        update(BrokerageAccount)
        .where(BrokerageAccount.id == account_id)
        .values(balance=new_balance)
    )

    # 4. Создаём запись в таблице запросов (для истории и аудита)
    request = BrockerageBalanceChangeRequest(
        brokerage_account_id=account_id,
        status_id=1,  # 1 = На рассмотрении (или "Успешно выполнен", если сразу применяем)
        amount=data.amount,
    )

    db.add(request)
    await db.commit()
    await db.refresh(account)  # обновляем объект счёта

    return {
        "status": "ok",
        "new_balance": float(account.balance),  # возвращаем новый баланс
        "message": "Баланс успешно изменён"
    }


@brokerage_accounts_router.get("/user_verification_status/{user_id}")
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

        is_verified = bool(is_verified_raw)

        return {"is_verified": is_verified}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка при проверке статуса верификации: {e}"
        )


@brokerage_accounts_router.patch("/brokerage-accounts/{account_id}/balance-change-requests/{request_id}")
async def cancel_request(
    account_id: int,
    request_id: int,
    db: AsyncSession = Depends(get_db),
    current_user = Depends(get_current_user)
):
    request = await db.get(BrockerageBalanceChangeRequest, request_id)
    if not request or request.brokerage_account_id != account_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Запрос не найден")

    request_cancelled = 2
    request.status_id = request_cancelled

    await db.commit()
    return {"success": True}


@brokerage_accounts_router.post("/brokerage-accounts/{account_id}/balance-change-requests")
async def create_balance_change_request(
    account_id: int,
    data: BalanceChangeRequestCreate,  # ожидает { "amount": float }
    db: AsyncSession = Depends(get_db),
    current_user = Depends(get_current_user),
):
    # 1. Находим счёт и проверяем принадлежность пользователю
    account = await db.scalar(
        select(BrokerageAccount)
        .where(
            BrokerageAccount.id == account_id,
            BrokerageAccount.user_id == current_user["id"]
        )
    )

    if not account:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Счёт не найден или не принадлежит вам")

    # 2. Проверка баланса при выводе (amount < 0)
    if data.amount < 0 and account.balance + data.amount < 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Недостаточно средств на счёте")

    # 3. Создаём запись в таблице запросов
    request = BrockerageBalanceChangeRequest(
        brokerage_account_id=account_id,
        status_id=1,  # "На рассмотрении"
        amount=data.amount,
    )

    db.add(request)
    await db.commit()
    await db.refresh(request)

    return {
        "status": "ok",
        "request_id": request.id,  # возвращаем ID нового запроса
        "message": "Запрос на изменение баланса создан"
    }