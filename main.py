import uvicorn
from datetime import timezone, datetime
from fastapi import FastAPI, Depends, HTTPException, status, Path, Response, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload, joinedload
from db.session import get_db
from core.config import *
from db.auth import authenticate_staff, authenticate_user, create_access_token, get_password_hash, get_current_user
from pydantic import BaseModel, EmailStr, field_validator, ConfigDict, Field
from decimal import Decimal
from typing import Optional, List
from datetime import datetime, date
from pydantic.types import conlist
import re
import logging
import asyncpg
from routers.routers import brokerage_accounts_router, charts_router
from db.models.models import (
    AdminRightsLevel,
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
    EmploymentStatus,
    Passport,
    PriceHistory,
    Proposal,
    ProposalType,
    Security,
    Staff,
    User,
    VerificationStatus,
    UserRestrictionStatus,
    ProposalStatus
)

app = FastAPI()
app.include_router(brokerage_accounts_router)
app.include_router(charts_router)

# Разрешаем React dev сервер
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

TABLES = {
    "depository_account_operation_type": DepositoryAccountOperationType,
    "brokerage_account_operation_type": BrokerageAccountOperationType,
    "proposal_type": ProposalType,
    "verification_status": VerificationStatus,
    "security": Security,
    "currency": Currency,
    "employment_status": EmploymentStatus,
    "bank": Bank,
    "user": User,
    "staff": Staff,
    "proposal": Proposal,
    "proposal_type": ProposalType,
    "proposal_status": ProposalStatus,
    "brokerage_account": BrokerageAccount,
    "depository_account": DepositoryAccount,
    "passport": Passport,
    "brokerage_account_history": BrokerageAccountHistory,
    "depository_account_history": DepositoryAccountHistory,
    "depository_account_balance": DepositoryAccountBalance,
    "price_history": PriceHistory,
    "currency_rate": CurrencyRate,
    "user_restriction_status": UserRestrictionStatus
}

logger = logging.getLogger(__name__)




@app.get("/ping-db")
async def ping_db(db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(text("SELECT 1"))
        return {"connected": True, "result": result.scalar()}
    except Exception as e:
        return {"connected": False, "error": str(e)}


class LoginRequest(BaseModel):
    login: str
    password: str


class Token(BaseModel):
    access_token: str
    token_type: str
    user_id: int
    role: str = "user"


class UserRegisterRequest(BaseModel):
    login: str
    email: EmailStr
    password: str

    class Config:
        from_attributes = True  # для совместимости с SQLAlchemy 2.0

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if len(v.encode("utf-8")) > 72:
            raise ValueError("Пароль слишком длинный (максимум ~70 символов)")
        if len(v) < 6:
            raise ValueError("Пароль должен содержать минимум 6 символов")
        return v


NAME_REGEX = re.compile(r"^[А-Яа-яA-Za-z\- ]+$")


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

    @field_validator("lastName", "firstName", "middleName")
    @classmethod
    def validate_names(cls, v: str):
        if not NAME_REGEX.match(v):
            raise ValueError("ФИО может содержать только буквы, пробелы и дефисы")
        return v.strip()

    @field_validator("series")
    @classmethod
    def validate_series(cls, v: str):
        if not v.isdigit():
            raise ValueError("Серия паспорта должна содержать только цифры")
        return v

    @field_validator("number")
    @classmethod
    def validate_number(cls, v: str):
        if not v.isdigit():
            raise ValueError("Номер паспорта должен содержать только цифры")
        return v

    @field_validator("gender")
    @classmethod
    def validate_gender(cls, v: str):
        if v not in ("м", "ж"):
            raise ValueError("Пол должен быть 'м' или 'ж'")
        return v

    @field_validator("birthDate")
    @classmethod
    def validate_birth_date(cls, v: datetime):
        today = date.today()
        birth = v.date()

        age = today.year - birth.year - (
                (today.month, today.day) < (birth.month, birth.day)
        )

        if birth > today:
            raise ValueError("Дата рождения не может быть в будущем")
        if age < 14:
            raise ValueError("Возраст должен быть не менее 14 лет")

        return v

    @field_validator("issueDate")
    @classmethod
    def validate_issue_date(cls, v: datetime, info):
        today = date.today()

        if v.date() > today:
            raise ValueError("Дата выдачи не может быть в будущем")

        birth_date = info.data.get("birthDate")
        if birth_date and v.date() <= birth_date.date():
            raise ValueError("Дата выдачи должна быть позже даты рождения")

        return v


class ProposalCreateRequest(BaseModel):
    security_id: int
    quantity: int
    proposal_type: int  # теперь это именно ID типа предложения (1 или 2)

    @field_validator("quantity")
    @classmethod
    def validate_quantity(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("Количество должно быть больше 0")
        return v

    @field_validator("proposal_type")
    @classmethod
    def validate_proposal_type(cls, v: int) -> int:
        if v not in (1, 2):
            raise ValueError("Тип предложения должен быть 1 (Купить) или 2 (Продать)")
        return v


@app.post("/api/login/user", response_model=Token, summary="Вход пользователя")
async def login_user(
        form_data: LoginRequest,
        db: AsyncSession = Depends(get_db)
):
    user = await authenticate_user(db, form_data.login, form_data.password)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный логин или пароль",
            headers={"WWW-Authenticate": "Bearer"},
        )
    elif user.block_status_id != 1:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Аккаунт заблокирован",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = create_access_token(
        data={"sub": user.login, "role": "user", "user_id": user.id}
    )
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": user.id,
        "role": "user"
    }


@app.post("/api/login/staff", response_model=Token, summary="Вход сотрудника")
async def login_staff(
        form_data: LoginRequest,  # Исправлено: form_data: LoginRequest
        db: AsyncSession = Depends(get_db)
):
    staff = await authenticate_staff(db, form_data.login, form_data.password)
    if not staff:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный логин или пароль",
            headers={"WWW-Authenticate": "Bearer"},
        )
    elif staff.employment_status_id == EMPLOYMENT_STATUS_ID_BLOCKED:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Аккаунт заблокирован",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = create_access_token(
        data={"sub": staff.login, "role": staff.rights_level_id, "staff_id": staff.id}
    )

    # Возвращаем ВСЕ обязательные поля из модели Token
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": staff.id,  # Добавляем user_id (используем staff.id)
        "role": str(staff.rights_level_id)
    }


@app.post("/api/register/user", status_code=status.HTTP_201_CREATED, summary="Регистрация пользователя")
async def register_user(
    form_data: UserRegisterRequest,
    db: AsyncSession = Depends(get_db)
):
    hashed_password = get_password_hash(form_data.password)
    result = await db.execute(
        text("""
            CALL register_user(:login, :password, :email, :user_id, :error_message)
        """),
        {
            "login": form_data.login,
            "password": hashed_password,
            "email": form_data.email,
            "user_id": None,
            "error_message": None
        }
    )
    row = result.fetchone()
    if row is None:
        raise HTTPException(status_code=500, detail="Ошибка вызова процедуры регистрации")

    user_id = row[0]
    error_message = row[1]

    if error_message is not None:
        if error_message == "Логин уже занят":
            raise HTTPException(status_code=400, detail=error_message)
        elif error_message == "Email уже зарегистрирован":
            raise HTTPException(status_code=400, detail=error_message)
        else:
            raise HTTPException(status_code=500, detail=f"Ошибка регистрации: {error_message}")

    await db.commit()

    return {
        "message": "Пользователь успешно зарегистрирован",
        "user_id": user_id,
        "login": form_data.login,
        "email": form_data.email,
    }


@app.get("/api/user/balance/{currency_id}")
async def get_user_balance(
        currency_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncSession = Depends(get_db)
):
    if current_user["role"] != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

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
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Ошибка сервера")



@app.get("/api/rate_to_ruble/{currency_id}")
async def rate_to_ruble(
        currency_id,
        db: AsyncSession = Depends(get_db)
):
    try:
        query = text("SELECT get_currency_rate(:currency_id) AS currency_rate")
        result = await db.execute(query, params={"currency_id": currency_id})
        currency_rate = result.scalar()

        if currency_rate is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Курс не найден")

        currency_rate_rounded = round(float(currency_rate), 4)

        return {
            "currency": f"id={currency_id}", # todo: return currency code
            "rate_to_rub": currency_rate_rounded,
            "source": f"get_currency_rate({currency_id})"
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка сервера при получении курса: {e}"
        )


@app.post("/api/passport", status_code=status.HTTP_201_CREATED)
async def create_passport(
    form_data: PassportCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user.get("type") != "client":  # Предполагаю, что роль пользователя — "client"
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    try:
        # Вызов процедуры submit_passport с OUT-параметрами
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
            raise HTTPException(status_code=400, detail=error_message)

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


@app.get("/api/proposal/{proposal_id}")
async def get_proposal_detail(
        proposal_id: int,
        db: AsyncSession = Depends(get_db),
        current_user: dict = Depends(get_current_user)  # проверка токена
):
    result = await db.execute(select(Proposal).where(Proposal.id == proposal_id))
    proposal = result.scalar_one_or_none()
    if not proposal:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Предложение не найдено")

    # Проверка прав доступа
    if current_user["role"] != "admin" and proposal.user.id != current_user.get("id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    passports = [
        {k: v for k, v in p.__dict__.items() if k != "_sa_instance_state"}
        for p in proposal.user.passports
    ]

    return {
        "id": proposal.id,
        "amount": float(proposal.amount),
        "proposal_type": {
            "id": proposal.proposal_type.id,
            "type": proposal.proposal_type.type
        },
        "security": {
            "id": proposal.security.id,
            "name": proposal.security.name
        },
        "user": {
            "id": proposal.user.id,
            "login": proposal.user.login,
            "email": proposal.user.email,
            "verification_status_id": proposal.user.verification_status_id,
            "passports": passports
        },
        "created_at": getattr(proposal, "created_at", None)
    }


@app.get("/api/securities")
async def get_securities(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Security).order_by(Security.name)
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


@app.get("/api/proposal-types")
async def get_proposal_types(db: AsyncSession = Depends(get_db)):
    """
    Возвращает список типов предложений для пользователя.
    Пример ответа:
    [
        {"id": 1, "type": "Купить"},
        {"id": 2, "type": "Продать"}
    ]
    """
    result = await db.execute(select(ProposalType))
    types = result.scalars().all()

    return [
        {"id": t.id, "type": t.type}
        for t in types
    ]


class UserResponse(BaseModel):
    id: int
    email: str
    registration_date: date
    verification_status_id: int
    block_status_id: int

    class Config:
        from_attributes = True

@app.get("/api/user/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

    return user


@app.get("/api/broker/proposal/{proposal_id}")
async def get_proposal_detail(
        proposal_id: int,
        db: AsyncSession = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    if current_user.get("role") != BROKER_EMPLOYEE_ROLE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещен: вы не являетесь брокером"
        )
    # Явно загружаем все необходимые связи
    result = await db.execute(
        select(Proposal)
        .where(Proposal.id == proposal_id)
        .options(
            selectinload(Proposal.proposal_type),
            selectinload(Proposal.security)
        )
    )

    proposal = result.scalar_one_or_none()
    if not proposal:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Предложение не найдено")

    return {
        "id": proposal.id,
        "amount": float(proposal.amount),
        "proposal_type": {
            "id": proposal.proposal_type.id,
            "type": proposal.proposal_type.type
        },
        "status": proposal.status_id,
        "security": {
            "id": proposal.security.id,
            "name": proposal.security.name
        },
        "account": proposal.brokerage_account_id,
    }


@app.get("/api/proposal")
async def get_all_proposals(
        db: AsyncSession = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    if current_user.get("role") != BROKER_EMPLOYEE_ROLE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Доступ запрещен: вы не являетесь брокером {current_user}"
        )

    result = await db.execute(
        select(Proposal)
        .options(
            selectinload(Proposal.security),
            selectinload(Proposal.proposal_type)
        )
        .order_by(Proposal.id.desc())
    )

    proposals = result.scalars().all()

    # Возвращаем пустой список, если заявок нет
    if not proposals:
        return []

    return [
        {
            "id": proposal.id,
            "amount": float(proposal.amount),
            "proposal_type": {
                "id": proposal.proposal_type.id,
                "type": proposal.proposal_type.type
            },

            "security": {
                "id": proposal.security.id,
                "name": proposal.security.name
            },
            "account": proposal.brokerage_account_id,
        }
        for proposal in proposals
    ]


@app.get("/api/staff/{staff_id}")
async def get_staff_profile(
        staff_id: int,
        db: AsyncSession = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    if current_user.get("type") != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещен: вы не являетесь сотрудником"
        )
    result = await db.execute(select(Staff).where(Staff.id == staff_id))
    staff = result.scalar_one_or_none()

    if not staff:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Сотрудник не найден")

    return {
        "id": staff.id,
        "contract_number": staff.contract_number,
        "employment_status": staff.employment_status_id, # todo: rename dict key to employment_status_id
        "rights_level": staff.rights_level_id,
        "login": staff.login,
    }


class StaffUpdate(BaseModel):
    login: Optional[str] = None
    password: Optional[str] = None
    contract_number: Optional[str] = None
    rights_level: Optional[str] = None
    employment_status_id: Optional[int] = None

@app.put("/api/staff/{staff_id}")
async def update_staff(
        staff_id: int,
        data: StaffUpdate,
        db: AsyncSession = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    if current_user.get("type") != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещен: вы не являетесь сотрудником"
        )
    result = await db.execute(
        select(Staff).where(Staff.id == staff_id)
    )
    staff = result.scalar_one_or_none()

    if not staff:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Сотрудник не найден")

    if data.login is not None and data.login != staff.login:
        result_login = await db.execute(
            select(Staff).where(Staff.login == data.login, Staff.id != staff_id)
        )
        if result_login.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Логин уже занят"
            )

    # Обновляем только те поля, которые переданы в запросе
    if data.login is not None:
        staff.login = data.login

    if data.password is not None and data.password != "":
        staff.password = get_password_hash(data.password)

    if data.contract_number is not None:
        staff.contract_number = data.contract_number

    if data.rights_level is not None:
        # Обновляем ID уровня прав (целое число)
        staff.rights_level_id = int(data.rights_level)  # Приводим к int, т.к. колонка Integer

    if data.employment_status_id is not None:
        staff.employment_status_id = data.employment_status_id

    await db.commit()
    await db.refresh(staff)

    return {
        "id": staff.id,
        "message": "Сотрудник успешно обновлён"
    }

class StaffCreate(BaseModel):
    login: str
    password: str
    contract_number: str
    rights_level: str
    employment_status_id: int


@app.post(
    "/api/staff/new",
    status_code=status.HTTP_201_CREATED,
    summary="Создание сотрудника"
)
async def register_staff(
    form_data: StaffCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    # Проверка прав доступа остаётся на Python-стороне
    if current_user.get("role") not in {MEGAADMIN_EMPLOYEE_ROLE, ADMIN_EMPLOYEE_ROLE}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещен: вы не являетесь администратором"
        )

    # Хэшируем пароль на Python (безопасно)
    hashed_password = get_password_hash(form_data.password)

    # Вызываем процедуру
    result = await db.execute(
        text("""
            CALL register_staff(
                :login,
                :password,
                :contract_number,
                :rights_level_id,
                :employment_status_id,
                :staff_id OUTPUT,
                :error_message OUTPUT
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
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Ошибка вызова процедуры создания сотрудника"
        )

    staff_id      = row[0]
    error_message = row[1]

    if error_message is not None:
        if error_message == "Логин уже занят" or error_message == "Номер договора уже занят":
            raise HTTPException(status_code=400, detail=error_message)
        else:
            raise HTTPException(status_code=500, detail=f"Ошибка создания сотрудника: {error_message}")

    # Коммит (на всякий случай, хотя INSERT внутри процедуры уже должен быть закоммичен)
    await db.commit()

    return {
        "message": "Сотрудник успешно создан",
        "staff_id": staff_id,
        "login": form_data.login,
        "rights_level": int(form_data.rights_level),
        "employment_status_id": form_data.employment_status_id,
    }


@app.get("/api/user/{user_id}/passport")
async def get_user_passport(
        user_id: int,
        db: AsyncSession = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    result = await db.execute(
        select(Passport, User.verification_status_id)
        .join(User, User.id == Passport.user_id)
        .where(Passport.user_id == user_id)
        .where(Passport.is_actual == True)
    )

    row = result.first()

    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Паспорт не найден")

    passport, verification_status_id = row

    return {
        "id": passport.id,
        "user_id": passport.user_id,
        "verification_status_id": verification_status_id,

        "last_name": passport.last_name,
        "first_name": passport.first_name,
        "patronymic": passport.patronymic,
        "gender": passport.gender,
        "birth_date": passport.birth_date,
        "birth_place": passport.birth_place,
        "series": passport.series,
        "number": passport.number,
        "issued_by": passport.issued_by,
        "issue_date": passport.issue_date,
        "registration_place": passport.registration_place,
    }


@app.delete("/api/user/{user_id}/passport", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user_passport(
        user_id: int,
        db: AsyncSession = Depends(get_db),
        current_user: dict = Depends(get_current_user)
):
    if current_user.get("role") != VERIFIER_EMPLOYEE_ROLE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещен: вы не являетесь верификатором"
        )
    result = await db.execute(
        select(Passport).where(Passport.user_id == user_id, Passport.is_actual == True)
    )
    passport = result.scalar_one_or_none()

    if not passport:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Паспорт не найден"
        )

    await db.delete(passport)
    await db.commit()

    return Response(status_code=status.HTTP_204_NO_CONTENT)


class UserVerificationUpdate(BaseModel):
    verification_status_id: int


@app.put("/api/user/verify/{user_id}")
async def update_user_verification_status(
        user_id: int,
        data: UserVerificationUpdate,
        db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

    user.verification_status_id = data.verification_status_id

    await db.commit()
    await db.refresh(user)

    return {
        "id": user.id,
        "verification_status_id": user.verification_status_id,
        "message": "Статус пользователя обновлён"
    }


class BrokerageAccountCreateRequest(BaseModel):
    bank_id: int
    currency_id: int
    inn: str  # ИНН теперь обязательное поле (строка, без пробелов)


@app.post("/api/brokerage-accounts/")
async def create_brokerage_account(
    account_data: BrokerageAccountCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user["role"] != "user":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён"
        )
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
                "inn": account_data.inn.strip(),
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
                raise HTTPException(status_code=404, detail="Банк не найден")
            if "Валюта с ID" in error_message:
                raise HTTPException(status_code=404, detail="Валюта не найдена или архивирована")
            raise HTTPException(status_code=400, detail=error_message)

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
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Внутренняя ошибка сервера при создании счёта"
        )

@app.delete("/api/brokerage-accounts/{brokerage_account_id}")
async def delete_brokerage_account(
        brokerage_account_id: int,
        current_user: dict = Depends(get_current_user),
        db: AsyncSession = Depends(get_db)
):
    if current_user.get("type") != "client":  # или "user" — в зависимости от вашей схемы
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    try:
        # Вызов процедуры delete_brokerage_account с OUT p_error_message
        result = await db.execute(
            text("""
                CALL delete_brokerage_account(:account_id, :user_id, :error_message)
            """),
            {
                "account_id": brokerage_account_id,
                "user_id": current_user["id"],
                "error_message": None  # placeholder для OUT-параметра
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]  # OUT p_error_message

        if error_message is not None:
            if "не найден" in error_message or "не принадлежит" in error_message:
                raise HTTPException(status_code=404, detail="Брокерский счёт не найден или не принадлежит вам")
            if "ненулевым балансом" in error_message:
                raise HTTPException(status_code=400, detail="Нельзя удалить брокерский счёт с ненулевым балансом")
            raise HTTPException(status_code=400, detail=error_message)

        await db.commit()

        return {
            "detail": "Брокерский счёт успешно удалён"
        }

    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Внутренняя ошибка сервера при удалении счёта"
        )


class StockOut(BaseModel):
    id: int
    ticker: str
    price: Decimal
    currency: str
    change: float

    class Config:
        from_attributes = True


# todo: move validation to postgres triggers
class StockCreate(BaseModel):
    ticker: str
    isin: str
    lot_size: int
    price: Decimal
    currency_id: int

    @field_validator("ticker")
    @classmethod
    def validate_ticker(cls, v: str):
        v = v.strip()
        if not v:
            raise ValueError("Тикер не может быть пустым")
        return v

    @field_validator("isin")
    @classmethod
    def validate_isin(cls, v: str):
        v = v.strip().upper()
        if not re.fullmatch(r"[A-Z]{2}[A-Z0-9]{9}[0-9]", v):
            raise ValueError("Некорректный формат ISIN")
        return v

    @field_validator("lot_size")
    @classmethod
    def validate_lot_size(cls, v: int):
        if v <= 0:
            raise ValueError("Размер лота должен быть больше 0")
        return v

    @field_validator("price")
    @classmethod
    def validate_price(cls, v: Decimal):
        if v <= 0:
            raise ValueError("Цена должна быть положительной")
        return v


@app.post("/api/exchange/stocks", status_code=status.HTTP_201_CREATED)
async def create_stock(
    data: StockCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    if current_user.get("type") != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: требуется роль сотрудника"
        )

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

        security_id = row[0]          # OUT p_security_id
        error_message = row[1]        # OUT p_error_message

        if error_message is not None:
            # Общие сообщения из процедуры
            if "Размер лота" in error_message:
                raise HTTPException(status_code=400, detail="Размер лота должен быть больше нуля")
            if "Валюта с ID" in error_message:
                raise HTTPException(status_code=404, detail="Валюта не найдена")
            if "ISIN" in error_message and "уже существует" in error_message:
                raise HTTPException(status_code=400, detail="ISIN уже существует")
            if "тикером" in error_message and "уже существует" in error_message:
                raise HTTPException(status_code=400, detail="Тикер уже существует")

            # Любая другая ошибка из процедуры
            raise HTTPException(status_code=400, detail=error_message)

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
        logger.exception("Неожиданная ошибка при создании ценной бумаги")
        raise HTTPException(status_code=500, detail="Внутренняя ошибка сервера")

class ProcessProposalRequest(BaseModel):
    verify: bool


@app.patch("/api/proposal/{proposal_id}/process")
async def process_proposal(
    proposal_id: int = Path(..., gt=0, description="ID предложения"),
    request_data: ProcessProposalRequest = None,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user.get("type") != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: требуется роль сотрудника"
        )

    payload = current_user.get("payload", {})
    staff_id = payload.get("staff_id")

    if not staff_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Не удалось определить ID сотрудника из токена"
        )

    verify = request_data.verify if request_data else False

    try:
        # Вызов процедуры process_proposal с OUT p_error_message
        result = await db.execute(
            text("""
                CALL process_proposal(:staff_id, :proposal_id, :verify, :error_message)
            """),
            {
                "staff_id": staff_id,
                "proposal_id": proposal_id,
                "verify": verify,
                "error_message": None  # placeholder для OUT-параметра
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]  # p_error_message

        if error_message is not None:
            # Определяем подходящий статус-код по содержанию ошибки
            if "не найден" in error_message.lower():
                status_code = status.HTTP_404_NOT_FOUND
            elif "уже обработана" in error_message.lower() or "недопустимый статус" in error_message.lower():
                status_code = status.HTTP_400_BAD_REQUEST
            elif "неизвестный тип предложения" in error_message.lower():
                status_code = status.HTTP_400_BAD_REQUEST
            else:
                status_code = status.HTTP_500_INTERNAL_SERVER_ERROR
            raise HTTPException(status_code=status_code, detail=error_message)

        await db.commit()

        action = "подтверждена" if verify else "отклонена"
        return {
            "message": f"Заявка №{proposal_id} успешно {action}",
            "proposal_id": proposal_id,
            "action": "approved" if verify else "rejected"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Внутренняя ошибка сервера при обработке заявки"
        )


@app.patch("/api/proposal/{proposal_id}/cancel")
async def cancel_proposal(
    proposal_id: int = Path(..., gt=0, description="ID предложения"),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user.get("type") != "client":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Только клиенты могут отменять свои заявки"
        )

    user_id = current_user.get("id")
    if not user_id:
        raise HTTPException(status_code=400, detail="Не удалось определить ID пользователя")

    try:
        # Вызов процедуры process_proposal для отмены (verify = FALSE) от имени системного сотрудника
        result = await db.execute(
            text("""
                CALL process_proposal(:staff_id, :proposal_id, :verify, :error_message)
            """),
            {
                "staff_id": SYSTEM_STAFF_ID,  # Константа с ID системного сотрудника
                "proposal_id": proposal_id,
                "verify": False,
                "error_message": None
            }
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]

        if error_message is not None:
            if "не найден" in error_message.lower():
                status_code = status.HTTP_404_NOT_FOUND
            elif "уже обработана" in error_message.lower() or "недопустимый статус" in error_message.lower():
                status_code = status.HTTP_400_BAD_REQUEST
            elif "неизвестный тип предложения" in error_message.lower():
                status_code = status.HTTP_400_BAD_REQUEST
            else:
                status_code = status.HTTP_500_INTERNAL_SERVER_ERROR
            raise HTTPException(status_code=status_code, detail=error_message)

        await db.commit()

        return {
            "message": f"Заявка №{proposal_id} успешно отменена",
            "proposal_id": proposal_id,
            "action": "cancelled"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Внутренняя ошибка сервера при отмене заявки"
        )


class UserUpdate(BaseModel):
    login: Optional[str] = None
    email: Optional[EmailStr] = None
    password: Optional[str] = None
    verification_status_id: Optional[int] = None
    block_status_id: Optional[int] = None

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            if len(v) < 6:
                raise ValueError("Пароль должен содержать минимум 6 символов")
        return v


@app.put("/api/user/{user_id}")
async def update_user(
        user_id: int,
        data: UserUpdate,
        db: AsyncSession = Depends(get_db),
):
    # Получаем пользователя
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")

    # Проверка логина, если передан, не пустой и изменился
    if data.login is not None and data.login.strip() != "" and data.login != user.login:
        existing_login = await db.execute(
            select(User).where(User.login == data.login, User.id != user_id)
        )
        if existing_login.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Логин уже занят"
            )

    # Проверка email, если передан, не пустой и изменился
    if data.email is not None and data.email.strip() != "" and data.email != user.email:
        existing_email = await db.execute(
            select(User).where(User.email == data.email, User.id != user_id)
        )
        if existing_email.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email уже зарегистрирован"
            )

    # Проверяем статусы, если переданы
    if data.verification_status_id is not None:
        # Проверяем существование статуса
        result = await db.execute(
            select(VerificationStatus).where(VerificationStatus.id == data.verification_status_id))
        if not result.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Неверный статус верификации")

    if data.block_status_id is not None:
        result = await db.execute(select(UserRestrictionStatus).where(UserRestrictionStatus.id == data.block_status_id))
        if not result.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Неверный статус блокировки")

    # Обновляем поля, которые переданы (не None)
    # Логин обновляем только если передан и не пустой
    if data.login is not None and data.login.strip() != "":
        user.login = data.login

    # Email обновляем только если передан и не пустой
    if data.email is not None and data.email.strip() != "":
        user.email = data.email

    if data.password is not None and data.password.strip() != "":
        user.password = get_password_hash(data.password)

    if data.verification_status_id is not None:
        user.verification_status_id = data.verification_status_id

    if data.block_status_id is not None:
        user.block_status_id = data.block_status_id

    await db.commit()
    await db.refresh(user)

    return {
        "id": user.id,
        "login": user.login,
        "email": user.email,
        "verification_status_id": user.verification_status_id,
        "block_status_id": user.block_status_id,
        "registration_date": user.registration_date,
        "message": "Пользователь успешно обновлён"
    }



@app.post("/api/user/{user_id}/verify_passport")
async def call_verify_user_passport(
    user_id: int,
    db: AsyncSession = Depends(get_db),
):
    """
    Вызывает PostgreSQL процедуру verify_user_passport.
    Создаёт депозитарный счёт и балансы при успешной верификации паспорта.
    """
    # Найдём ID паспорта пользователя
    passport_result = await db.execute(
        text('SELECT "ID паспорта" FROM public."Паспорт" WHERE "ID пользователя" = :user_id'),
        {"user_id": user_id}
    )
    passport_row = passport_result.fetchone()

    if not passport_row:
        raise HTTPException(status_code=404, detail="Паспорт пользователя не найден")

    passport_id = passport_row[0]

    try:
        result = await db.execute(
            text("""
                CALL public.verify_user_passport(
                    :passport_id,
                    :success OUTPUT,
                    :error_message OUTPUT
                )
            """),
            {"passport_id": passport_id}
        )

        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        success       = row[0]
        error_message = row[1]

        if not success:
            raise Exception(error_message or "Ошибка верификации")

        await db.commit()

    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    return {
        "message": "Верификация паспорта успешно завершена",
        "user_id": user_id,
        "passport_id": passport_id
    }
    
@app.get("/api/exchange/stocks")
async def get_stocks(db: AsyncSession = Depends(get_db)):
    result = await db.execute(text("SELECT * FROM get_exchange_stocks()"))
    rows = result.fetchall()
    return [dict(row._mapping) for row in rows]

class DictionaryItemCreate(BaseModel):
    """Общая модель для создания элемента справочника"""
    pass

class EmploymentStatusCreate(DictionaryItemCreate):
    status: str

class VerificationStatusCreate(DictionaryItemCreate):
    status: str

class UserRestrictionStatusCreate(DictionaryItemCreate):
    status: str

class ProposalStatusCreate(DictionaryItemCreate):
    status: str

class ProposalTypeCreate(DictionaryItemCreate):
    type: str

class DepositoryAccountOperationTypeCreate(DictionaryItemCreate):
    type: str

class BrokerageAccountOperationTypeCreate(DictionaryItemCreate):
    type_name: str

class CurrencyCreate(DictionaryItemCreate):
    code: str
    symbol: str

class BankCreate(DictionaryItemCreate):
    name: str
    inn: str
    ogrn: str
    bik: str
    license_expiry: date

# Модели для обновления
class EmploymentStatusUpdate(BaseModel):
    status: Optional[str] = None

class VerificationStatusUpdate(BaseModel):
    status: Optional[str] = None

class UserRestrictionStatusUpdate(BaseModel):
    status: Optional[str] = None

class ProposalStatusUpdate(BaseModel):
    status: Optional[str] = None

class ProposalTypeUpdate(BaseModel):
    type: Optional[str] = None

class DepositoryAccountOperationTypeUpdate(BaseModel):
    type: Optional[str] = None

class BrokerageAccountOperationTypeUpdate(BaseModel):
    type_name: Optional[str] = None

class CurrencyUpdate(BaseModel):
    code: Optional[str] = None
    symbol: Optional[str] = None

class BankUpdate(BaseModel):
    name: Optional[str] = None
    inn: Optional[str] = None
    ogrn: Optional[str] = None
    bik: Optional[str] = None
    license_expiry: Optional[date] = None


class TotalSumFromLotSizeResponse(BaseModel):
    total_sum: float
    currency_symbol: str

@app.get(
    "/api/get_lot_price/{security_id}/{lot_amount}",
    response_model=TotalSumFromLotSizeResponse
)
async def get_lot_price(
    security_id: int,
    lot_amount: int,
    db: AsyncSession = Depends(get_db)
):
    if lot_amount <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Количество лотов должно быть положительным")

    # 1. Получаем общую стоимость через функцию PostgreSQL
    price_query = text(
        "SELECT public.get_lot_price(:security_id, :lot_amount) AS total_sum"
    )
    price_result = await db.execute(
        price_query,
        {"security_id": security_id, "lot_amount": lot_amount}
    )
    price_row = price_result.fetchone()

    if price_row is None or price_row.total_sum is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Цена не найдена или бумага недоступна")

    total_sum_value = price_row.total_sum

    # 2. Получаем символ валюты отдельным запросом
    currency_query = text(
        """
        SELECT c."Символ" AS currency_symbol
        FROM public."Список ценных бумаг" s
        JOIN public."Список валют" c ON s."ID валюты" = c."ID валюты"
        WHERE s."ID ценной бумаги" = :security_id
        """
    )
    currency_result = await db.execute(
        currency_query,
        {"security_id": security_id}
    )
    currency_row = currency_result.fetchone()

    if currency_row is None or currency_row.currency_symbol is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Валюта ценной бумаги не найдена")

    return TotalSumFromLotSizeResponse(
        total_sum=float(total_sum_value),
        currency_symbol=currency_row.currency_symbol
    )

class CurrencyBase(BaseModel):
    code: str = Field(..., min_length=3, max_length=3)
    symbol: str = Field(..., min_length=1, max_length=10)

    @field_validator("code")
    @classmethod
    def validate_code(cls, v: str) -> str:
        v = v.upper()
        if not re.fullmatch(r"[A-Z]{3}", v):
            raise ValueError("Код валюты должен состоять из 3 латинских букв")
        return v


class CurrencyResponse(BaseModel):
    id: int
    code: str
    symbol: str
    archived: bool
    rate_to_ruble: float

    class Config:
        from_attributes = True

@app.get("/api/currencies", response_model=List[CurrencyResponse])
async def get_currencies(
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    if current_user.get("type") != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: требуется роль сотрудника"
        )

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

@app.post("/api/currencies")
async def add_currency(
    body: dict,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    if current_user.get("type") != "staff":
        raise HTTPException(status_code=403, detail="Доступ запрещён: требуется роль сотрудника")

    code = body.get("code")
    symbol = body.get("symbol")
    rate_to_ruble = body.get("rate_to_ruble")

    if not code or not symbol or not rate_to_ruble:
        raise HTTPException(status_code=400, detail="Код, символ валюты и курс к рублю обязательны")

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
            raise HTTPException(status_code=400, detail=error_message)

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
        raise HTTPException(status_code=500, detail=f"Ошибка добавления валюты: {e}")


@app.put("/api/currencies/{currency_id}")
async def update_currency(
    currency_id: int,
    body: dict,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    if current_user.get("type") != "staff":
        raise HTTPException(status_code=403, detail="Доступ запрещён: требуется роль сотрудника")

    new_code = body.get("code")
    new_symbol = body.get("symbol")
    new_rate = body.get("rate_to_ruble")

    if all(v is None for v in [new_code, new_symbol, new_rate]):
        raise HTTPException(status_code=400, detail="Нет данных для обновления")

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
            raise HTTPException(status_code=400, detail=f"Bad request: {error_message}")

        await db.commit()
        return {"message": "Валюта успешно обновлена"}

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка обновления валюты: {str(e)}")


@app.post("/api/archive_currency/{currency_id}")
async def archive_currency(
    currency_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    if current_user.get("type") != "staff":
        raise HTTPException(status_code=403, detail="Доступ запрещён: требуется роль сотрудника")

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
            raise HTTPException(status_code=400, detail=error_message)

        await db.commit()
        return {
            "message": f"Валюта с ID {currency_id} успешно архивирована"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"Ошибка архивации валюты: {str(e)}")


class RightsLevelOut(BaseModel):
    id: int
    name: str

    class Config:
        from_attributes = True


class EmploymentStatusOut(BaseModel):
    id: int
    status: str

    class Config:
        from_attributes = True


class RightsLevelsResponse(BaseModel):
    data: List[RightsLevelOut]

    @field_validator('data')
    @classmethod
    def check_not_empty(cls, v: List[RightsLevelOut]) -> List[RightsLevelOut]:
        if len(v) == 0:
            raise ValueError('Список уровней прав пуст')
        return v


class EmploymentStatusResponse(BaseModel):
    data: List[EmploymentStatusOut]

    @field_validator('data')
    @classmethod
    def check_not_empty(cls, v: List[EmploymentStatusOut]) -> List[EmploymentStatusOut]:
        if len(v) == 0:
            raise ValueError('Список статусов трудоустройства пуст')
        return v

@app.get("/api/rights_levels")
async def get_rights_levels(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(AdminRightsLevel).order_by(AdminRightsLevel.id))
    levels = result.scalars().all()
    return levels


@app.get("/api/employment_statuses")
async def get_employment_statuses(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(EmploymentStatus).order_by(EmploymentStatus.id))
    statuses = result.scalars().all()
    return statuses

@app.get("/api/verification_statuses")
async def get_verification_statuses(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(VerificationStatus).order_by(VerificationStatus.id))
    statuses = result.scalars().all()
    return statuses

@app.get("/api/user_block_statuses")
async def get_user_block_statuses(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(UserRestrictionStatus).order_by(UserRestrictionStatus.id))
    statuses = result.scalars().all()
    return statuses

@app.get("/api/banks")
async def get_user_block_statuses(
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Bank).order_by(Bank.id))
    banks = result.scalars().all()
    return banks

class BankCreateRequest(BaseModel):
    name: str
    inn: str
    ogrn: str
    bik: str
    license_expiry_date: date

@app.post("/api/banks", status_code=status.HTTP_201_CREATED)
async def create_bank(
    bank_data: BankCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user.get("type") != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: требуется роль сотрудника"
        )
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
            raise HTTPException(status_code=400, detail=error_message)

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

@app.delete("/api/banks/{bank_id}")
async def delete_bank(
    bank_id: int,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user.get("type") != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: требуется роль сотрудника"
        )

    try:
        result = await db.execute(
            text("CALL delete_bank(:bank_id, :error_message)"),
            {"bank_id": bank_id, "error_message": None}
        )
        row = result.fetchone()
        if row is None:
            raise Exception("Процедура не вернула результат")

        error_message = row[0]

        if error_message is not None:
            raise HTTPException(status_code=400, detail=error_message)

        await db.commit()

        return {
            "message": f"Банк с ID {bank_id} успешно удалён"
        }

    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Внутренняя ошибка сервера при удалении банка: {exc}"
        )
class BankUpdateRequest(BaseModel):
    name: Optional[str] = None
    inn: Optional[str] = None
    ogrn: Optional[str] = None
    bik: Optional[str] = None
    license_expiry_date: Optional[date] = None


@app.put("/api/banks/{bank_id}")
async def update_bank(
    bank_id: int,
    bank_data: BankUpdateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user.get("type") != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: требуется роль сотрудника"
        )

    # Если ничего не передано — ошибка
    if all(v is None for v in bank_data.model_dump().values()):
        raise HTTPException(status_code=400, detail="Нет данных для обновления")

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
            raise HTTPException(status_code=400, detail=error_message)

        await db.commit()

        return {"message": "Банк успешно обновлён"}

    except HTTPException:
        raise
    except Exception as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при обновлении банка: {str(exc)}"
        )

@app.get("/api/{table_name}")
async def get_table_data(table_name: str, db: AsyncSession = Depends(get_db)):
    model = TABLES.get(table_name)
    if not model:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Table '{table_name}' not found in tables: {TABLES}"
        )
    result = await db.execute(select(model))
    rows = result.scalars().all()

    data = [
        {k: v for k, v in row.__dict__.items() if k != "_sa_instance_state"}
        for row in rows
    ]
    return data

def run():
    # uvicorn.run("main:app", host=settings.HOST, port=settings.PORT, reload=True)
    uvicorn.run("main:app", host=HOST, port=PORT, reload=True)


if __name__ == "__main__":
    run()