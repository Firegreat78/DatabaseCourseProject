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
    Dividend,
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
    "dividend": Dividend,
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
    if current_user["role"] != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    try:
        result = await db.execute(
            text("SELECT submit_passport(:user_id, :last_name, :first_name, :patronymic, "
                 ":series, :number, :gender, :birth_date, :birth_place, :registration_place, "
                 ":issue_date, :issued_by)"),
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
            }
        )

        passport_id = result.scalar_one()  # Функция возвращает ID созданного паспорта

        await db.commit()

        return {
            "message": "Паспорт успешно создан",
            "passport_id": passport_id,
            "user_id": current_user["id"]
        }

    except IntegrityError as exc:
        # Обрабатываем ошибки, поднятые через RAISE EXCEPTION в submit_passport
        orig_error = exc.orig
        if isinstance(orig_error, asyncpg.exceptions.PostgresError):
            error_message = str(orig_error).strip()
            # Специфическая обработка известных сообщений
            if "Паспорт уже привязан" in error_message:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Паспорт уже привязан к пользователю"
                ) from exc
            # Для остальных ошибок из функции возвращаем само сообщение
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            ) from exc
        raise

    except Exception as exc:
        # Любые другие неожиданные ошибки
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Не удалось создать паспорт"
        ) from exc


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
    if current_user.get("role") != BROKER_ROLE:
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
    if current_user.get("role") != BROKER_ROLE:
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
    if current_user.get("role") not in {MEGAADMIN_ROLE, ADMIN_ROLE}:
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
    if current_user.get("role") != VERIFIER_ROLE:
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
        # Вызываем серверную функцию
        result = await db.execute(
            text("SELECT add_brokerage_account(:user_id, :bank_id, :currency_id)"),
            {
                "user_id": current_user["id"],
                "bank_id": account_data.bank_id,
                "currency_id": account_data.currency_id
            }
        )

        account_id = result.scalar_one()  # ID нового счёта

        # Получаем данные для ответа (банк и валюта)
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

    except IntegrityError as exc:
        await db.rollback()
        orig_msg = str(exc.orig).strip() if exc.orig else ""
        if "Банк с ID" in orig_msg:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Банк не найден")
        if "Валюта с ID" in orig_msg:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Валюта не найдена или архивирована")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=orig_msg or "Ошибка при создании счёта")

    except Exception as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Внутренняя ошибка сервера: {exc}")


@app.delete("/api/brokerage-accounts/{brokerage_account_id}")
async def delete_brokerage_account(
        brokerage_account_id,
        current_user: dict = Depends(get_current_user),
        db: AsyncSession = Depends(get_db)
):
    if current_user["role"] != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    try:
        # Вызываем серверную функцию — она сделает все проверки и удаление
        result = await db.execute(
            text("SELECT delete_brokerage_account(:account_id, :user_id)"),
            {
                "account_id": int(brokerage_account_id),
                "user_id": current_user["id"]
            }
        )

        # Функция возвращает VOID, поэтому scalar_one() вернёт None при успехе
        result.scalar_one()

        await db.commit()

        return {
            "detail": "Брокерский счёт успешно удалён"
        }

    except IntegrityError as exc:
        await db.rollback()
        orig_msg = str(exc.orig).strip() if exc.orig else ""

        if "не найден" in orig_msg or "не принадлежит" in orig_msg:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Брокерский счёт не найден или не принадлежит вам")
        if "ненулевым балансом" in orig_msg:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Нельзя удалить брокерский счёт с ненулевым балансом")
        # Любая другая ошибка из функции
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=orig_msg or "Ошибка при удалении счёта")

    except Exception as exc:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Внутренняя ошибка сервера: {exc}")



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
    has_dividends: bool = False

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
):
    try:
        result = await db.execute(
            text("""
                SELECT add_security(
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
                "lot_size": Decimal(data.lot_size),
                "price": data.price,
                "currency_id": data.currency_id,
                "has_dividends": data.has_dividends,
            }
        )

        security_id = result.scalar_one()  # add_security возвращает ID ценной бумаги

        await db.commit()

        return {
            "id": security_id,
            "ticker": data.ticker,
            "isin": data.isin,
        }

    except IntegrityError as exc:
        await db.rollback()
        orig_msg = str(exc.orig).strip() if exc.orig else ""

        logger.warning("Ошибка при добавлении ценной бумаги: %s", orig_msg)

        # Все проверки теперь в триггере и функции — сообщения из RAISE EXCEPTION
        if "Размер лота" in orig_msg:
            raise HTTPException(400, "Размер лота должен быть больше нуля")
        if "Валюта с ID" in orig_msg:
            raise HTTPException(404, "Валюта не найдена")
        if "ISIN" in orig_msg and "уже существует" in orig_msg:
            raise HTTPException(400, "ISIN уже существует")
        if "тикером" in orig_msg and "уже существует" in orig_msg:
            raise HTTPException(400, "Тикер уже существует")

        # На всякий случай — общее сообщение
        raise HTTPException(400, orig_msg or "Нарушение ограничений данных")

    except Exception as exc:
        await db.rollback()
        logger.exception("Неожиданная ошибка при создании ценной бумаги")
        raise HTTPException(500, "Внутренняя ошибка сервера")

class ProcessProposalRequest(BaseModel):
    verify: bool


@app.patch("/api/proposal/{proposal_id}/process")
async def process_proposal(
        proposal_id: int = Path(..., gt=0, description="ID предложения"),
        request_data: ProcessProposalRequest = None,
        current_user: dict = Depends(get_current_user),
        db: AsyncSession = Depends(get_db)
):
    payload = current_user.get("payload")
    staff_id = payload.get("staff_id")

    if not staff_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Не удалось определить ID сотрудника из токена"
        )

    # Проверяем, что сотрудник существует
    result = await db.execute(
        select(Staff).where(Staff.id == staff_id)
    )
    staff = result.scalar_one_or_none()

    if not staff:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Сотрудник с ID {staff_id} не найден"
        )

    verify = request_data.verify if request_data else False

    try:
        query = text("SELECT process_proposal(:staff_id, :proposal_id, :verify)")
        await db.execute(
            query,
            {
                "staff_id": staff_id,
                "proposal_id": proposal_id,
                "verify": verify
            }
        )
        await db.commit()

        action = "подтверждена" if verify else "отклонена"
        return {
            "message": f"Заявка №{proposal_id} успешно {action}",
            "proposal_id": proposal_id,
            "action": "approved" if verify else "rejected"
        }

    except Exception as e:
        await db.rollback()
        error_msg = str(e)

        # Парсинг сообщения об ошибке из PostgreSQL
        if "не найден" in error_msg.lower():
            status_code = status.HTTP_404_NOT_FOUND
        elif "уже обработана" in error_msg.lower() or "недопустимый статус" in error_msg.lower():
            status_code = status.HTTP_400_BAD_REQUEST
        elif "неизвестный тип предложения" in error_msg.lower():
            status_code = status.HTTP_400_BAD_REQUEST
        else:
            status_code = status.HTTP_500_INTERNAL_SERVER_ERROR

        raise HTTPException(
            status_code=status_code,
            detail=error_msg if status_code != status.HTTP_500_INTERNAL_SERVER_ERROR else "Внутренняя ошибка сервера при обработке заявки"
        )
    
@app.patch("/api/proposal/{proposal_id}/cancel")
async def cancel_proposal(
    proposal_id: int = Path(..., gt=0, description="ID предложения"),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user["role"] != "user":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Только клиенты могут отменять свои заявки"
        )
    user_id = current_user["id"]
    try:
        # 1. Проверяем, что заявка существует и принадлежит пользователю
        result = await db.execute(
            select(Proposal)
            .join(Proposal.brokerage_account)
            .options(joinedload(Proposal.status))
            .where(
                Proposal.id == proposal_id,
                BrokerageAccount.user_id == user_id
            )
        )
        proposal = result.scalar_one_or_none()
        if not proposal:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Заявка не найдена или у вас нет прав для её отмены"
            )
        query = text("SELECT process_proposal(:staff_id, :proposal_id, :verify)")
        await db.execute(
            query,
            {
                "staff_id": SYSTEM_STAFF_ID,
                "proposal_id": proposal_id,
                "verify": False
            }
        )
        await db.commit()
        result = await db.execute(
            select(Proposal)
            .options(joinedload(Proposal.status))
            .where(Proposal.id == proposal_id)
        )
        updated_proposal = result.scalar_one_or_none()
        
        return {
            "message": f"Заявка №{proposal_id} успешно отменена",
            "proposal_id": proposal_id,
            "new_status": updated_proposal.status.status if updated_proposal.status else "отменено",
            "status_id": updated_proposal.status_id
        }
        
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        error_msg = str(e)
        if "не найден" in error_msg.lower():
            status_code = status.HTTP_404_NOT_FOUND
        elif "уже обработана" in error_msg.lower() or "недопустимый статус" in error_msg.lower():
            status_code = status.HTTP_400_BAD_REQUEST
        elif "неизвестный тип предложения" in error_msg.lower():
            status_code = status.HTTP_400_BAD_REQUEST
        else:
            status_code = status.HTTP_500_INTERNAL_SERVER_ERROR
        raise HTTPException(
            status_code=status_code,
            detail=error_msg if status_code != 500 else "Внутренняя ошибка сервера при отмене заявки"
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
    result = await db.execute(
        select(
            Security.id,
            Security.name,
            Security.isin,
            PriceHistory.price,
            Currency.code
        )
        .join(PriceHistory, PriceHistory.security_id == Security.id)
        .join(Currency, Currency.id == Security.currency_id)
        .order_by(Security.name)
    )

    return [
        {
            "id": row.id,
            "ticker": row.name,
            "isin": row.isin,
            "price": float(row.price),
            "currency": row.code,
            "change": 0.0,  # placeholder
        }
        for row in result
    ]

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

# ==================== CRUD эндпоинты для EmploymentStatus ====================

@app.post("/api/employment_status", status_code=status.HTTP_201_CREATED)
async def create_employment_status(
    data: EmploymentStatusCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    try:
        new_status = EmploymentStatus(
            status=data.status
        )
        db.add(new_status)
        await db.commit()
        await db.refresh(new_status)
        
        return {
            "id": new_status.id,
            "status": new_status.status
        }
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/employment_status/{item_id}")
async def update_employment_status(
    item_id: int,
    data: EmploymentStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(EmploymentStatus).where(EmploymentStatus.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Статус трудоустройства не найден"
        )
    
    if data.status is not None:
        item.status = data.status
    
    await db.commit()
    await db.refresh(item)
    
    return {
        "id": item.id,
        "status": item.status
    }

@app.delete("/api/employment_status/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_employment_status(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(EmploymentStatus).where(EmploymentStatus.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Статус трудоустройства не найден"
        )
    
    # Проверка на использование в других таблицах
    staff_check = await db.execute(
        select(Staff).where(Staff.employment_status_id == item_id).limit(1)
    )
    if staff_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить статус, так как он используется в записях персонала"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# ==================== CRUD эндпоинты для VerificationStatus ====================

@app.post("/api/verification_status", status_code=status.HTTP_201_CREATED)
async def create_verification_status(
    data: VerificationStatusCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: delete
):
    try:
        new_status = VerificationStatus(
            status=data.status
        )
        db.add(new_status)
        await db.commit()
        await db.refresh(new_status)
        
        return {
            "id": new_status.id,
            "status": new_status.status
        }
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/verification_status/{item_id}")
async def update_verification_status(
    item_id: int,
    data: VerificationStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: delete
):
    result = await db.execute(
        select(VerificationStatus).where(VerificationStatus.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Статус верификации не найден"
        )
    
    if data.status is not None:
        item.status = data.status
    
    await db.commit()
    await db.refresh(item)
    
    return {
        "id": item.id,
        "status": item.status
    }

@app.delete("/api/verification_status/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_verification_status(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(VerificationStatus).where(VerificationStatus.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Статус верификации не найден"
        )
    
    # Проверка на использование в таблице пользователей
    user_check = await db.execute(
        select(User).where(User.verification_status_id == item_id).limit(1)
    )
    if user_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить статус, так как он используется в записях пользователей"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# ==================== CRUD эндпоинты для UserRestrictionStatus ====================

@app.post("/api/user_restriction_status", status_code=status.HTTP_201_CREATED)
async def create_user_restriction_status(
    data: UserRestrictionStatusCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    try:
        new_status = UserRestrictionStatus(
            status=data.status
        )
        db.add(new_status)
        await db.commit()
        await db.refresh(new_status)
        
        return {
            "id": new_status.id,
            "status": new_status.status
        }
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/user_restriction_status/{item_id}")
async def update_user_restriction_status(
    item_id: int,
    data: UserRestrictionStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(UserRestrictionStatus).where(UserRestrictionStatus.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Статус блокировки не найден"
        )
    
    if data.status is not None:
        item.status = data.status
    
    await db.commit()
    await db.refresh(item)
    
    return {
        "id": item.id,
        "status": item.status
    }

@app.delete("/api/user_restriction_status/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user_restriction_status(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(UserRestrictionStatus).where(UserRestrictionStatus.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Статус блокировки не найден"
        )
    
    # Проверка на использование в таблице пользователей
    user_check = await db.execute(
        select(User).where(User.block_status_id == item_id).limit(1)
    )
    if user_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить статус, так как он используется в записях пользователей"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# ==================== CRUD эндпоинты для ProposalStatus ====================

@app.post("/api/proposal_status", status_code=status.HTTP_201_CREATED)
async def create_proposal_status(
    data: ProposalStatusCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    try:
        new_status = ProposalStatus(
            status=data.status
        )
        db.add(new_status)
        await db.commit()
        await db.refresh(new_status)
        
        return {
            "id": new_status.id,
            "status": new_status.status
        }
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/proposal_status/{item_id}")
async def update_proposal_status(
    item_id: int,
    data: ProposalStatusUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(ProposalStatus).where(ProposalStatus.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Статус предложения не найден"
        )
    
    if data.status is not None:
        item.status = data.status
    
    await db.commit()
    await db.refresh(item)
    
    return {
        "id": item.id,
        "status": item.status
    }

@app.delete("/api/proposal_status/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_proposal_status(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(ProposalStatus).where(ProposalStatus.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Статус предложения не найден"
        )
    
    # Проверка на использование в таблице предложений
    proposal_check = await db.execute(
        select(Proposal).where(Proposal.status_id == item_id).limit(1)
    )
    if proposal_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить статус, так как он используется в записях предложений"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# ==================== CRUD эндпоинты для ProposalType ====================

@app.post("/api/proposal_type", status_code=status.HTTP_201_CREATED)
async def create_proposal_type(
    data: ProposalTypeCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    try:
        new_type = ProposalType(
            type=data.type
        )
        db.add(new_type)
        await db.commit()
        await db.refresh(new_type)
        
        return {
            "id": new_type.id,
            "type": new_type.type
        }
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/proposal_type/{item_id}")
async def update_proposal_type(
    item_id: int,
    data: ProposalTypeUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(ProposalType).where(ProposalType.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Тип предложения не найден"
        )
    
    if data.type is not None:
        item.type = data.type
    
    await db.commit()
    await db.refresh(item)
    
    return {
        "id": item.id,
        "type": item.type
    }

@app.delete("/api/proposal_type/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_proposal_type(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(ProposalType).where(ProposalType.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Тип предложения не найден"
        )
    
    # Проверка на использование в таблице предложений
    proposal_check = await db.execute(
        select(Proposal).where(Proposal.proposal_type_id == item_id).limit(1)
    )
    if proposal_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить тип, так как он используется в записях предложений"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# ==================== CRUD эндпоинты для DepositoryAccountOperationType ====================

@app.post("/api/depository_account_operation_type", status_code=status.HTTP_201_CREATED)
async def create_depository_account_operation_type(
    data: DepositoryAccountOperationTypeCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    try:
        new_type = DepositoryAccountOperationType(
            type=data.type
        )
        db.add(new_type)
        await db.commit()
        await db.refresh(new_type)
        
        return {
            "id": new_type.id,
            "type": new_type.type
        }
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/depository_account_operation_type/{item_id}")
async def update_depository_account_operation_type(
    item_id: int,
    data: DepositoryAccountOperationTypeUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    result = await db.execute(
        select(DepositoryAccountOperationType).where(DepositoryAccountOperationType.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Тип операции депозитарного счета не найден"
        )
    
    if data.type is not None:
        item.type = data.type
    
    await db.commit()
    await db.refresh(item)
    
    return {
        "id": item.id,
        "type": item.type
    }

@app.delete("/api/depository_account_operation_type/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_depository_account_operation_type(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user) # todo: apply unauth
):
    result = await db.execute(
        select(DepositoryAccountOperationType).where(DepositoryAccountOperationType.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Тип операции депозитарного счета не найден"
        )
    
    # Проверка на использование в истории операций
    history_check = await db.execute(
        select(DepositoryAccountHistory).where(DepositoryAccountHistory.operation_type_id == item_id).limit(1)
    )
    if history_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить тип, так как он используется в истории операций"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# ==================== CRUD эндпоинты для BrokerageAccountOperationType ====================

@app.post("/api/brokerage_account_operation_type", status_code=status.HTTP_201_CREATED)
async def create_brokerage_account_operation_type(
    data: BrokerageAccountOperationTypeCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user) # todo: apply unauth
):
    try:
        new_type = BrokerageAccountOperationType(
            type_name=data.type_name
        )
        db.add(new_type)
        await db.commit()
        await db.refresh(new_type)
        
        return {
            "id": new_type.id,
            "type": new_type.type_name
        }
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/brokerage_account_operation_type/{item_id}")
async def update_brokerage_account_operation_type(
    item_id: int,
    data: BrokerageAccountOperationTypeUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user) # todo: apply unauth
):
    result = await db.execute(
        select(BrokerageAccountOperationType).where(BrokerageAccountOperationType.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Тип операции брокерского счета не найден"
        )
    
    if data.type_name is not None:
        item.type_name = data.type_name
    
    await db.commit()
    await db.refresh(item)
    
    return {
        "id": item.id,
        "type": item.type_name
    }

@app.delete("/api/brokerage_account_operation_type/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_brokerage_account_operation_type(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    result = await db.execute(
        select(BrokerageAccountOperationType).where(BrokerageAccountOperationType.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Тип операции брокерского счета не найден"
        )
    
    # Проверка на использование в истории операций
    history_check = await db.execute(
        select(BrokerageAccountHistory).where(BrokerageAccountHistory.operation_type_id == item_id).limit(1)
    )
    if history_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить тип, так как он используется в истории операций"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# ==================== CRUD эндпоинты для Currency ====================

@app.post("/api/currency", status_code=status.HTTP_201_CREATED)
async def create_currency(
    data: CurrencyCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user) # todo: apply unauth
):
    try:
        new_currency = Currency(
            code=data.code,
            symbol=data.symbol
        )
        db.add(new_currency)
        await db.commit()
        await db.refresh(new_currency)
        
        return {
            "id": new_currency.id,
            "code": new_currency.code,
            "symbol": new_currency.symbol
        }
    except IntegrityError as e:
        await db.rollback()
        if "unique constraint" in str(e).lower() and "code" in str(e).lower():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Код валюты должен быть уникальным"
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/currency/{item_id}")
async def update_currency(
    item_id: int,
    data: CurrencyUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user) # todo: apply unauth
):
    result = await db.execute(
        select(Currency).where(Currency.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Валюта не найдена"
        )

    if data.code is not None:
        # Проверка уникальности кода валюты
        if data.code != item.code:
            code_check = await db.execute(
                select(Currency).where(Currency.code == data.code, Currency.id != item_id)
            )
            if code_check.scalar_one_or_none():
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Код валюты должен быть уникальным"
                )
        item.code = data.code
    
    if data.symbol is not None:
        item.symbol = data.symbol
    
    await db.commit()
    await db.refresh(item)

    return {
        "id": item.id,
        "code": item.code,
        "symbol": item.symbol
    }

@app.delete("/api/currency/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_currency(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)  # todo: add unauth
):
    result = await db.execute(
        select(Currency).where(Currency.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Валюта не найдена"
        )
    
    # Проверка на использование в ценных бумагах
    security_check = await db.execute(
        select(Security).where(Security.currency_id == item_id).limit(1)
    )
    if security_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить валюту, так как она используется в ценных бумагах"
        )
    
    # Проверка на использование в брокерских счетах
    account_check = await db.execute(
        select(BrokerageAccount).where(BrokerageAccount.currency_id == item_id).limit(1)
    )
    if account_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить валюту, так как она используется в брокерских счетах"
        )
    
    # Проверка на использование в курсах валют
    rate_check = await db.execute(
        select(CurrencyRate).where(CurrencyRate.currency_id == item_id).limit(1)
    )
    if rate_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить валюту, так как она используется в курсах валют"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)

# ==================== CRUD эндпоинты для Bank ====================

@app.post("/api/bank", status_code=status.HTTP_201_CREATED)
async def create_bank(
    data: BankCreate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user) # todo: apply unauth
):
    try:
        # Проверка даты лицензии
        if data.license_expiry < date.today():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Срок действия лицензии не может быть в прошлом"
            )
        
        new_bank = Bank(
            name=data.name,
            inn=data.inn,
            ogrn=data.ogrn,
            bik=data.bik,
            license_expiry=data.license_expiry
        )
        db.add(new_bank)
        await db.commit()
        await db.refresh(new_bank)
        
        return {
            "id": new_bank.id,
            "name": new_bank.name,
            "inn": new_bank.inn,
            "ogrn": new_bank.ogrn,
            "bik": new_bank.bik,
            "license_expiry": new_bank.license_expiry
        }
    except IntegrityError as e:
        await db.rollback()
        error_msg = str(e).lower()
        if "unique constraint" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Банк с такими реквизитами уже существует"
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ошибка уникальности данных"
        )

@app.put("/api/bank/{item_id}")
async def update_bank(
    item_id: int,
    data: BankUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user)
):
    result = await db.execute(
        select(Bank).where(Bank.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Банк не найден"
        )
    
    if data.name is not None:
        item.name = data.name
    
    if data.inn is not None:
        item.inn = data.inn
    
    if data.ogrn is not None:
        item.ogrn = data.ogrn
    
    if data.bik is not None:
        item.bik = data.bik
    
    if data.license_expiry is not None:
        if data.license_expiry < date.today():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Срок действия лицензии не может быть в прошлом"
            )
        item.license_expiry = data.license_expiry
    
    await db.commit()
    await db.refresh(item)
    
    return {
        "id": item.id,
        "name": item.name,
        "inn": item.inn,
        "ogrn": item.ogrn,
        "bik": item.bik,
        "license_expiry": item.license_expiry
    }

@app.delete("/api/bank/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_bank(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: dict = Depends(get_current_user) # todo: apply unauth
):
    result = await db.execute(
        select(Bank).where(Bank.id == item_id)
    )
    item = result.scalar_one_or_none()
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Банк не найден"
        )
    
    # Проверка на использование в брокерских счетах
    account_check = await db.execute(
        select(BrokerageAccount).where(BrokerageAccount.bank_id == item_id).limit(1)
    )
    if account_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Невозможно удалить банк, так как он используется в брокерских счетах"
        )
    
    await db.delete(item)
    await db.commit()
    
    return Response(status_code=status.HTTP_204_NO_CONTENT)


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