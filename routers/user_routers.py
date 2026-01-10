import re
from datetime import datetime, date
from decimal import Decimal
from typing import List

from fastapi import APIRouter, HTTPException, Depends, Path
from pydantic import field_validator, Field, BaseModel, ConfigDict
from sqlalchemy import text, select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette import status

from core.config import SYSTEM_STAFF_ID, USER_BAN_STATUS_ID
from db.auth import get_current_user
from db.models import Bank, Currency, Security, BrokerageAccount, User
from db.session import get_db

async def verify_user_role(current_user: dict = Depends(get_current_user)):
    if current_user["type"] != "client":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: endpoint'ы '/api/user/...' доступны только для пользователей"
        )
    return current_user

user_router = APIRouter(
    prefix="/api/user",
    tags=["User API router"],
    dependencies=[Depends(verify_user_role)],
)

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

class VerificationStatusResponse(BaseModel):
    is_verified: bool

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

class SecuritiesResponse(BaseModel):
    security_name: str
    lot_size: float
    isin: str
    amount: float
    currency_code: str
    currency_symbol: str

    class Config:
        from_attributes = True

class OfferCreate(BaseModel):
    account_id: int
    security_id: int
    quantity: Decimal = Field(..., gt=0, decimal_places=2)
    proposal_type_id: int  # 1 = купить, 2 = продать

class OfferResponse(BaseModel):
    id: int
    offer_type: str
    security_name: str
    security_isin: str
    quantity: float
    proposal_status: int

class BrokerageAccountOut(BaseModel):
    account_id: int
    balance: float
    inn: str
    bik: str
    bank_name: str
    currency_symbol: str

    class Config:
        from_attributes = True

class BrokerageAccountCreateRequest(BaseModel):
    bank_id: int
    currency_id: int
    inn: str

class PassportCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lastName: str = Field(..., min_length=2, max_length=50)
    firstName: str = Field(..., min_length=2, max_length=50)
    middleName: str = Field(..., min_length=2, max_length=50)

    series: str = Field(..., min_length=4, max_length=4)
    number: str = Field(..., min_length=6, max_length=6)

    gender: str

    birthDate: datetime
    issueDate: datetime

    birthPlace: str = Field(..., min_length=3, max_length=100)
    registrationPlace: str = Field(..., min_length=5, max_length=150)
    issuedBy: str = Field(..., min_length=5, max_length=150)

    @field_validator("gender")
    @classmethod
    def validate_gender(cls, v: str):
        if v not in ("м", "ж"):
            raise ValueError("Пол должен быть 'м' или 'ж'")
        return v

@user_router.get("/balance/{currency_id}")
async def get_user_balance(
        currency_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]
    try:
        query = text("SELECT get_total_account_value(:user_id, :currency_id) AS total_rub")
        params = {
            "currency_id": int(currency_id),
            "user_id": user_id,
        }
        result = await db.execute(query, params)
        total_rub = result.scalar()

        return {
            "total_balance_rub": round(float(total_rub or 0), 2)
        }

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка сервера: {e}"
        )

@user_router.delete("/brokerage-accounts/{brokerage_account_id}")
async def delete_brokerage_account(
        brokerage_account_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(
            text("""
                CALL delete_brokerage_account(:account_id, :user_id, :error_message)
            """),
            {
                "account_id": brokerage_account_id,
                "user_id": current_user["id"],
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]  # OUT p_error_message

        if error_message is not None:
            if "не найден" in error_message or "не принадлежит" in error_message:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Брокерский счёт не найден или не принадлежит вам")
            if "ненулевым балансом" in error_message:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Нельзя удалить брокерский счёт с ненулевым балансом")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_message)

        await db.commit()

        return {
            "detail": "Брокерский счёт успешно удалён"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при удалении счёта: {e}"
        )

@user_router.post("/brokerage-accounts")
async def create_brokerage_account(
    account_data: BrokerageAccountCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    inn = account_data.inn.strip()
    try:
        result = await db.execute(
            text("""
                CALL add_brokerage_account(
                    :user_id, :bank_id, :currency_id, :inn,
                    :account_id, :error_message
                )
            """),
            {
                "user_id": current_user["id"],
                "bank_id": account_data.bank_id,
                "currency_id": account_data.currency_id,
                "inn": inn,
                "account_id": None,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        account_id = row[0]        # OUT p_account_id
        error_message = row[1]    # OUT p_error_message

        if error_message is not None:
            if "Банк с ID" in error_message:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Банк не найден"
                )
            if "Валюта с ID" in error_message:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Валюта не найдена или архивирована"
                )
            if 'нарушает ограничение уникальности "Брокерский счёт_ИНН_key"' in error_message:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"ИНН брокерского счёта {inn} уже занят"
                )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

        # Получаем данные банка и валюты для ответа
        bank_result = await db.execute(select(Bank).where(Bank.id == account_data.bank_id))
        bank = bank_result.scalar_one()

        currency_result = await db.execute(select(Currency).where(Currency.id == account_data.currency_id))
        currency = currency_result.scalar_one()

        await db.commit()

        return {
            "account_id": account_id,
            "balance": 0.0,
            "bank_id": bank.id,
            "bank_name": bank.name,
            "bik": bank.bik,
            "currency_id": currency.id,
            "currency_symbol": currency.symbol,
            "user_id": current_user["id"]
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при создании счёта: {e}"
        )

@user_router.patch("/proposal/{proposal_id}/cancel")
async def cancel_proposal(
    proposal_id: int = Path(..., gt=0, description="ID предложения"),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user.get("id")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Не удалось определить ID пользователя"
        )

    try:
        result = await db.execute(
            text("""
                SELECT public.process_proposal(
                    :staff_id,
                    :proposal_id,
                    false
                )
            """),
            {
                "staff_id": SYSTEM_STAFF_ID,
                "proposal_id": proposal_id
            }
        )

        error_message = result.scalar()

        if error_message:
            msg = error_message.lower()

            if "не найден" in msg:
                status_code = status.HTTP_404_NOT_FOUND
            elif "недопустимый статус" in msg:
                status_code = status.HTTP_400_BAD_REQUEST
            else:
                status_code = status.HTTP_500_INTERNAL_SERVER_ERROR

            raise HTTPException(status_code=status_code, detail=error_message)

        await db.commit()

        return {
            "message": f"Заявка #{proposal_id} успешно отменена",
            "proposal_id": proposal_id,
            "action": "cancelled"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка сервера при отмене заявки: {e}"
        )

@user_router.post("/passport", status_code=status.HTTP_201_CREATED)
async def create_passport(
    form_data: PassportCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(
            text("""
                CALL submit_passport(
                    :user_id, :last_name, :first_name, :patronymic,
                    :series, :number, :gender, :birth_date,
                    :birth_place, :registration_place,
                    :issue_date, :issued_by,
                    :passport_id, :error_message
                )
            """),
            {
                "user_id": current_user["id"],
                "last_name": form_data.lastName,
                "first_name": form_data.firstName,
                "patronymic": form_data.middleName,
                "series": form_data.series,
                "number": form_data.number,
                "gender": form_data.gender,
                "birth_date": form_data.birthDate.date(),
                "birth_place": form_data.birthPlace,
                "registration_place": form_data.registrationPlace,
                "issue_date": form_data.issueDate.date(),
                "issued_by": form_data.issuedBy,
                "passport_id": None,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        passport_id = row[0]      # OUT p_passport_id
        error_message = row[1]    # OUT p_error_message

        if error_message is not None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_message)

        await db.commit()

        return {
            "message": "Паспорт успешно создан",
            "passport_id": passport_id,
            "user_id": current_user["id"]
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Не удалось создать паспорт: {e}"
        ) from e

@user_router.get("/securities")
async def get_securities(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Security).where(Security.is_archived == False).order_by(Security.name)
    )
    securities = result.scalars().all()

    return [
        {
            "id": s.id,
            "name": s.name,
            "isin": s.isin,
            "lot_size": float(s.lot_size)
        }
        for s in securities
    ]

@user_router.get(
    "/brokerage-accounts",
    response_model=List[BrokerageAccountOut]
)
async def get_user_brokerage_accounts(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
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
        .where(BrokerageAccount.user_id == current_user["id"])
        .order_by(BrokerageAccount.id)
    )
    return result.mappings().all()

@user_router.post(
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
    result = await db.execute(
        text("""
            CALL add_proposal(
                :user_id,
                :security_id,
                :account_id,
                :proposal_type_id,
                :lot_amount,
                :error_message
            )
        """),
        {
            "user_id": user_id,
            "security_id": data.security_id,
            "account_id": data.account_id,
            "proposal_type_id": data.proposal_type_id,
            "lot_amount": data.quantity,
            "error_message": None
        }
    )

    row = result.fetchone()
    if row is None:
        raise Exception("Процедура не вернула результат")

    error_message = row[0]

    if error_message is not None:
        if "не найдена" in error_message:
            raise HTTPException(
                status_code=404,
                detail=error_message
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

    await db.commit()

    # 6. Возвращаем созданное предложение в формате OfferResponse
    result = await db.execute(
        text("SELECT * from get_user_offers(:user_id) LIMIT 1"),
        {"user_id": user_id}
    )

    row = result.fetchone()
    if not row:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Предложение создано, но не найдено"
        )

    return OfferResponse(**row._mapping)

@user_router.get(
    "/offers",
    response_model=List[OfferResponse]
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

@user_router.get(
    "/portfolio/securities",
    response_model=List[SecuritiesResponse]
)
async def get_portfolio_securities(
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]

    query = text("SELECT * FROM get_user_securities(:user_id) WHERE amount > 0")
    result = await db.execute(query, {"user_id": user_id})
    securities = result.fetchall()

    return [
        {
            "security_name": row.security_name,
            "lot_size": float(row.lot_size) if row.lot_size is not None else None,
            "isin": row.isin,
            "amount": float(row.amount) if row.amount is not None else None,
            "currency_code": row.currency_code,
            "currency_symbol": row.currency_symbol,
        }
        for row in securities
    ]


@user_router.post("/brokerage-accounts/{account_id}/balance-change-requests")
async def create_balance_change_request(
        account_id: int,
        data: BalanceChangeRequestCreate,
        db: AsyncSession = Depends(get_db),
        current_user=Depends(get_current_user),
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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Счёт не найден или не принадлежит вам"
        )

    # Определяем тип операции: пополнение (1) или списание (2)
    system_staff_id = 2  # ID системного сотрудника
    balance_increase_id = 1  # ID типа операции "пополнение"
    balance_decrease_id = 2  # ID типа операции "списание"

    operation_type = balance_increase_id if data.amount > 0 else balance_decrease_id

    try:
        # Вызываем функцию через SELECT (функция возвращает record)
        result = await db.execute(
            text("""
                SELECT * FROM public.change_brokerage_account_balance(
                    :account_id,
                    :amount,
                    :brokerage_operation_type,
                    :staff_id
                )
            """),
            {
                "account_id": account_id,
                "amount": data.amount,
                "brokerage_operation_type": operation_type,
                "staff_id": system_staff_id
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Функция не вернула результат")

        # Получаем результаты функции
        operation_id = row[0]  # p_operation_id (первый OUT параметр)
        error_message = row[1]  # p_error_message (второй OUT параметр)

        if error_message:
            # Обрабатываем различные типы ошибок
            error_lower = error_message.lower()

            if "недостаточно" in error_lower:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Недостаточно средств на счёте"
                )
            elif "тип операции" in error_lower and "не найден" in error_lower:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Некорректный тип операции"
                )
            elif "счёт" in error_lower and "не найден" in error_lower:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Счёт не найден"
                )
            else:
                # Общая ошибка
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=error_message
                )

        await db.commit()

        # Обновляем объект аккаунта для получения нового баланса
        await db.refresh(account)

        return {
            "status": "ok",
            "message": "Баланс успешно изменён",
            "new_balance": float(account.balance),
            "operation_id": operation_id
        }

    except HTTPException:
        await db.rollback()
        raise

    except Exception as e:
        await db.rollback()

        # Проверяем, не связана ли ошибка с конкурентным доступом
        if "could not serialize access" in str(e).lower():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Произошла конфликтная операция. Попробуйте позже."
            )

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при изменении баланса"
        )

@user_router.get(
    "/user_verification_status/{user_id}",
    response_model=VerificationStatusResponse
)
async def get_verification_status(
    user_id: int,
    current_user = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user["id"] != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Вы можете проверять только свой статус верификации"
        )

    try:
        query = text("SELECT public.get_user_verification_status(:user_id)")
        result = await db.execute(query, {"user_id": user_id})
        is_verified_raw = result.scalar()

        if is_verified_raw is None:
            raise ValueError("Функция вернула NULL")
        return VerificationStatusResponse(is_verified=(not not is_verified_raw))

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка при проверке статуса верификации: {str(e)}"
        )

class DepositaryAccountResponse(BaseModel):
    account: DepositaryAccount
    balance: List[DepositaryBalance]
    operations: List[DepositaryOperation]


@user_router.get(
    "/depositary_account",
    response_model=DepositaryAccountResponse
)
async def get_depositary_account(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]
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
            AND b."Сумма" > 0
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
            AND ho."Сумма операции" > 0
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
    return DepositaryAccountResponse(
        account=account,
        balance=balance,
        operations=operations
    )

class BanStatusOut(BaseModel):
    is_banned: bool

    class Config:
        from_attributes = True


@user_router.get(
    "/user_ban_status/{user_id}",
    response_model=BanStatusOut,
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
    return BanStatusOut(
        is_banned=(ban_status_id == USER_BAN_STATUS_ID)
    )

@user_router.get("/brokerage-accounts/{account_id}/operations")
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


@user_router.get("/brokerage-accounts/{account_id}")
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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Счёт не найден"
        )

    return {
        "id": row.id,
        "balance": float(row.balance),
        "currency": row.currency
    }
