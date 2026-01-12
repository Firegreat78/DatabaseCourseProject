# routers/admin_router.py
from datetime import date
from decimal import Decimal
from typing import Optional, List

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from sqlalchemy import text, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from starlette import status

from core.config import MEGAADMIN_EMPLOYEE_ROLE, ADMIN_EMPLOYEE_ROLE
from db.auth import get_current_user, get_password_hash
from db.models import Staff, UserRestrictionStatus, VerificationStatus, Bank, EmploymentStatus, AdminRightsLevel
from db.session import get_db


async def verify_admin_role(current_user: dict = Depends(get_current_user)):
    if (current_user["type"] == "client") or (current_user["role"] not in {MEGAADMIN_EMPLOYEE_ROLE, ADMIN_EMPLOYEE_ROLE}):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: endpoint'ы '/api/admin/...' доступны только для администраторов"
        )
    return current_user

admin_router = APIRouter(
    prefix="/api/admin",
    tags=["Admin API router"],
    dependencies=[Depends(verify_admin_role)],
)

class StaffCreate(BaseModel):
    login: str
    password: str
    contract_number: str
    rights_level: str
    employment_status_id: int

class StaffUpdate(BaseModel):
    login: Optional[str] = None
    password: Optional[str] = None
    contract_number: Optional[str] = None
    rights_level: Optional[str] = None
    employment_status_id: Optional[int] = None

class BankCreateRequest(BaseModel):
    name: str
    inn: str
    ogrn: str
    bik: str
    license_expiry_date: date

class BankUpdateRequest(BaseModel):
    name: Optional[str] = None
    inn: Optional[str] = None
    ogrn: Optional[str] = None
    bik: Optional[str] = None
    license_expiry_date: Optional[date] = None

class CurrencyResponse(BaseModel):
    id: int
    code: str
    symbol: str
    archived: bool
    rate_to_ruble: float

    class Config:
        from_attributes = True


class StockCreate(BaseModel):
    ticker: str
    isin: str
    lot_size: int
    price: Decimal
    currency_id: int

class StockUpdateRequest(BaseModel):
    ticker: Optional[str] = None
    isin: Optional[str] = None
    lot_size: Optional[int] = None
    price: Optional[float] = None

@admin_router.post("/banks", status_code=status.HTTP_201_CREATED)
async def create_bank(
    bank_data: BankCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(
            text("""
                CALL add_bank(
                    :name, :inn, :ogrn, :bik, :license_expiry_date,
                    :bank_id, :error_message
                )
            """),
            {
                "name": bank_data.name.strip(),
                "inn": bank_data.inn.strip(),
                "ogrn": bank_data.ogrn.strip(),
                "bik": bank_data.bik.strip(),
                "license_expiry_date": bank_data.license_expiry_date,
                "bank_id": None,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        bank_id       = row[0]
        error_message = row[1]

        if error_message is not None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_message)

        await db.commit()

        return {
            "message": "Банк успешно добавлен",
            "bank_id": bank_id,
            "name": bank_data.name.strip()
        }

    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при добавлении банка: {exc}"
        )

@admin_router.put("/banks/{bank_id}")
async def update_bank(
    bank_id: int,
    bank_data: BankUpdateRequest,
    db: AsyncSession = Depends(get_db)
):
    if all(v is None for v in bank_data.model_dump().values()):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Нет данных для обновления"
        )
    try:
        result = await db.execute(
            text("""
                CALL update_bank(
                    :bank_id,
                    :name,
                    :inn,
                    :ogrn,
                    :bik,
                    :license_expiry_date,
                    :error_message
                )
            """),
            {
                "bank_id": bank_id,
                "name": bank_data.name,
                "inn": bank_data.inn,
                "ogrn": bank_data.ogrn,
                "bik": bank_data.bik,
                "license_expiry_date": bank_data.license_expiry_date,
                "error_message": None
            }
        )
        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")
        error_message = row[0]
        if error_message is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

        await db.commit()
        return {
            "message": "Банк успешно обновлён"
        }

    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при обновлении банка: {exc}"
        )

@admin_router.delete("/banks/{bank_id}")
async def delete_bank(
    bank_id: int,
    db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(
            text("CALL delete_bank(:bank_id, :error_message)"),
            {
                "bank_id": bank_id,
                "error_message": None
            }
        )
        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]

        if error_message is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

        await db.commit()

        return {
            "message": f"Банк с ID {bank_id} успешно удалён"
        }

    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при удалении банка: {exc}"
        )

@admin_router.get("/currencies", response_model=List[CurrencyResponse])
async def get_currencies(
    db: AsyncSession = Depends(get_db),
):
    query = text('SELECT * FROM get_currencies_info()')
    result = await db.execute(query)
    rows = result.fetchall()

    currencies = [CurrencyResponse(
        id=row[0],
        code=row[1],
        symbol=row[2],
        archived=row[3],
        rate_to_ruble=float(row[4]))
        for row in rows
    ]
    return currencies

@admin_router.post("/currencies")
async def add_currency(
    body: dict,
    db: AsyncSession = Depends(get_db),
):
    code = body.get("code")
    symbol = body.get("symbol")
    rate_to_ruble = body.get("rate_to_ruble")
    code = code.upper().strip()
    try:
        result = await db.execute(
            text("""
                CALL add_currency(:code, :symbol, :rate_to_ruble, :currency_id, :error_message)
            """),
            {
                "code": code,
                "symbol": symbol.strip(),
                "rate_to_ruble": rate_to_ruble,
                "currency_id": None,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        currency_id   = row[0]
        error_message = row[1]

        if error_message is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

        await db.commit()

        return {
            "message": "Валюта успешно добавлена",
            "id": currency_id,
            "code": code,
            "symbol": symbol.strip()
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка добавления валюты: {e}"
        )


@admin_router.put("/currencies/{currency_id}")
async def update_currency(
    currency_id: int,
    body: dict,
    db: AsyncSession = Depends(get_db),
):
    new_code = body.get("code")
    new_symbol = body.get("symbol")
    new_rate = body.get("rate_to_ruble")

    if all(v is None for v in [new_code, new_symbol, new_rate]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Нет данных для обновления"
        )

    try:
        result = await db.execute(
            text("""
                CALL change_currency_info(:currency_id, :new_code, :new_symbol, :new_rate, :error_message)
            """),
            {
                "currency_id": currency_id,
                "new_code": new_code,
                "new_symbol": new_symbol,
                "new_rate": new_rate,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]

        if error_message is not None:
            if "значение не умещается в тип character varying(10)" in error_message:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Слишком длинный символ валюты: '{new_symbol}'"
                )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Bad request: {error_message}"
            )

        await db.commit()
        return {"message": "Валюта успешно обновлена"}

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка обновления валюты: {e}"
        )


@admin_router.post("/archive_currency/{currency_id}")
async def archive_currency(
    currency_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    try:
        result = await db.execute(
            text("""
                CALL archive_currency(:currency_id, :error_message)
            """),
            {
                "currency_id": currency_id,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]

        if error_message is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

        await db.commit()
        return {
            "message": f"Валюта с ID {currency_id} успешно архивирована"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка архивации валюты: {e}"
        )

@admin_router.post("/exchange/stocks", status_code=status.HTTP_201_CREATED)
async def create_stock(
    data: StockCreate,
    db: AsyncSession = Depends(get_db),
):
    try:
        result = await db.execute(
            text("""
                CALL add_security(
                    :ticker,
                    :isin,
                    :lot_size,
                    :price,
                    :currency_id,
                    :security_id,
                    :error_message
                )
            """),
            {
                "ticker": data.ticker,
                "isin": data.isin,
                "lot_size": Decimal(data.lot_size),
                "price": data.price,
                "currency_id": data.currency_id,
                "security_id": None,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        security_id   = row[0]
        error_message = row[1]

        if error_message is not None:
            if "Размер лота" in error_message:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Размер лота должен быть больше нуля")
            if "Валюта с ID" in error_message:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Валюта не найдена")
            if "ISIN" in error_message and "уже существует" in error_message:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ISIN уже существует")
            if "тикером" in error_message and "уже существует" in error_message:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Ценная бумага с тикером {data.ticker} уже существует")
            if "chk_isin_valid" in error_message:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Некорректный формат ISIN: {data.isin}")

            # Любая другая ошибка из процедуры
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_message)

        await db.commit()

        return {
            "id": security_id,
            "ticker": data.ticker,
            "isin": data.isin,
        }

    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Внутренняя ошибка сервера: {exc}")

@admin_router.put("/exchange/stocks/{stock_id}")
async def update_stock(
    stock_id: int,
    stock_data: StockUpdateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if all(v is None for v in stock_data.model_dump().values()):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Нет данных для обновления")

    try:
        result = await db.execute(
            text("""
                CALL update_security(
                    :stock_id,
                    :ticker,
                    :isin,
                    :lot_size,
                    :price,
                    :error_message
                )
            """),
            {
                "stock_id": stock_id,
                "ticker": stock_data.ticker,
                "isin": stock_data.isin,
                "lot_size": stock_data.lot_size,
                "price": stock_data.price,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]

        if error_message is not None:
            if "chk_isin_valid" in error_message:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Некорректный ISIN: {stock_data.isin}"
                )

            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

        await db.commit()

        return {"message": "Ценная бумага успешно обновлена"}

    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при обновлении ценной бумаги: {exc}"
        )

@admin_router.post("/exchange/stocks/{stock_id}/archive")
async def archive_stock(
    stock_id: int,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(
            text("SELECT archive_security(:stock_id, :employee_id)"),
            {
                "stock_id": stock_id,
                "employee_id": current_user["id"]
            }
        )
        error_message = result.scalar()

        if error_message is not None and error_message != "":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )
        await db.commit()
        return {"message": "Ценная бумага успешно архивирована"}
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка сервера при архивации: {e}"
        )


@admin_router.put("/staff/{staff_id}")
async def update_staff(
        staff_id: int,
        data: StaffUpdate,
        db: AsyncSession = Depends(get_db)
):
    # Получаем сотрудника
    result = await db.execute(
        select(Staff).where(Staff.id == staff_id)
    )
    staff = result.scalar_one_or_none()

    if not staff:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сотрудник не найден"
        )
    if data.login is not None and data.login != staff.login:
        result_login = await db.execute(
            select(Staff).where(Staff.login == data.login, Staff.id != staff_id)
        )
        if result_login.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Логин уже занят"
            )
    if data.contract_number is not None and data.contract_number != staff.contract_number:
        result_contract = await db.execute(
            select(Staff).where(
                Staff.contract_number == data.contract_number,
                Staff.id != staff_id
            )
        )
        if result_contract.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Номер трудового договора '{data.contract_number}' уже используется другим сотрудником"
            )

    try:
        if data.login is not None:
            staff.login = data.login

        if data.password is not None and data.password != "":
            staff.password = get_password_hash(data.password)

        if data.contract_number is not None:
            staff.contract_number = data.contract_number

        if data.rights_level is not None:
            # Обновляем ID уровня прав (целое число)
            staff.rights_level_id = int(data.rights_level)

        if data.employment_status_id is not None:
            staff.employment_status_id = data.employment_status_id

        await db.commit()
        await db.refresh(staff)

        return {
            "id": staff.id,
            "message": "Сотрудник успешно обновлён"
        }

    except IntegrityError as e:
        await db.rollback()

        error_msg = str(e).lower()

        if "номер трудового договора" in error_msg or "персонал_номер трудового догово_key" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Номер трудового договора '{data.contract_number}' уже используется другим сотрудником"
            )
        elif "логин" in error_msg or "персонал_логин_key" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Логин '{data.login}' уже используется другим сотрудником"
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Ошибка сохранения данных. Проверьте уникальность вводимых значений."
            )

    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при обновлении данных сотрудника: {e}"
        )

@admin_router.post(
    "/staff/new",
    status_code=status.HTTP_201_CREATED,
    summary="Создание сотрудника"
)
async def register_staff(
    form_data: StaffCreate,
    db: AsyncSession = Depends(get_db)
):
    hashed_password = get_password_hash(form_data.password)
    try:
        result = await db.execute(
            text("""
                SELECT staff_id, error_message
                FROM public.register_staff(
                    :login,
                    :password,
                    :contract_number,
                    :rights_level_id,
                    :employment_status_id
                )
            """),
            {
                "login": form_data.login,
                "password": hashed_password,
                "contract_number": form_data.contract_number,
                "rights_level_id": int(form_data.rights_level),
                "employment_status_id": form_data.employment_status_id,
            }
        )

        row = result.fetchone()
        if not row:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Функция создания сотрудника не вернула результат"
            )

        staff_id, error_message = row

        if error_message:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

        await db.commit()

        return {
            "message": "Сотрудник успешно создан",
            "staff_id": staff_id,
            "login": form_data.login,
            "rights_level": int(form_data.rights_level),
            "employment_status_id": form_data.employment_status_id,
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка сервера при создании сотрудника: {e}"
        )

@admin_router.get("/rights_levels")
async def get_rights_levels(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(AdminRightsLevel).order_by(AdminRightsLevel.id))
    levels = result.scalars().all()
    return levels


@admin_router.get("/employment_statuses")
async def get_employment_statuses(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(EmploymentStatus).order_by(EmploymentStatus.id))
    statuses = result.scalars().all()
    return statuses

@admin_router.get("/verification_statuses")
async def get_verification_statuses(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(VerificationStatus).order_by(VerificationStatus.id))
    statuses = result.scalars().all()
    return statuses

@admin_router.get("/user_block_statuses")
async def get_user_block_statuses(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(UserRestrictionStatus).order_by(UserRestrictionStatus.id))
    statuses = result.scalars().all()
    return statuses

@admin_router.get("/banks")
async def get_banks(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Bank).order_by(Bank.id))
    banks = result.scalars().all()
    return banks