import uvicorn
from datetime import timezone, datetime
from fastapi import FastAPI, Depends, HTTPException, status, Path
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload, joinedload
from db.session import get_db
from core.config import PORT, HOST
from db.auth import authenticate_staff, authenticate_user, create_access_token, get_password_hash, get_current_user
from pydantic import BaseModel, EmailStr, field_validator
from decimal import Decimal
from typing import Optional


from routers.routers import brokerage_accounts_router

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

app = FastAPI()
app.include_router(brokerage_accounts_router)

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
    "brokerage_account": BrokerageAccount,
    "depository_account": DepositoryAccount,
    "dividend": Dividend,
    "passport": Passport,
    "brokerage_account_history": BrokerageAccountHistory,
    "depository_account_history": DepositoryAccountHistory,
    "depository_account_balance": DepositoryAccountBalance,
    "price_history": PriceHistory,
    "currency_rate": CurrencyRate
}

@app.get("/api/{table_name}")
async def get_table_data(table_name: str, db: AsyncSession = Depends(get_db)):
    model = TABLES.get(table_name)
    if not model:
        return {"error": f"Table not found (given={table_name})"}
    print(f"before result model={model}")
    result = await db.execute(select(model))
    print(f"after result model={model}")
    rows = result.scalars().all()

    data = [
        {k: v for k, v in row.__dict__.items() if k != "_sa_instance_state"}
        for row in rows
    ]
    return data

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

class PassportCreateRequest(BaseModel):
    lastName: str
    firstName: str
    middleName: str
    series: str
    number: str
    gender: str
    birthDate: datetime
    birthPlace: str
    registrationPlace: str
    issueDate: datetime
    issuedBy: str

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
    form_data: LoginRequest,  # Исправлено: form_data: LoginRequest
    db: AsyncSession = Depends(get_db)
):
    user = await authenticate_user(db, form_data.login, form_data.password)  # form_data
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный логин или пароль",
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
    access_token = create_access_token(
        data={"sub": staff.login, "role": staff.rights_level, "staff_id": staff.id}
    )
    
    # Возвращаем ВСЕ обязательные поля из модели Token
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": staff.id,  # Добавляем user_id (используем staff.id)
        "role": staff.rights_level       # Добавляем role
    }

@app.post("/api/register/user", status_code=status.HTTP_201_CREATED, summary="Регистрация пользователя")
async def register_user(
    form_data: UserRegisterRequest,  # ИСПРАВЛЕНО: form_data
    db: AsyncSession = Depends(get_db)
):
    # 1. Проверяем, не занят ли логин
    result_login = await db.execute(
        select(User).where(User.login == form_data.login)
    )
    if result_login.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Логин уже занят"
        )

    # 2. Проверяем email
    result_email = await db.execute(
        select(User).where(User.email == form_data.email)
    )
    if result_email.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email уже зарегистрирован"
        )

    # 3. Хэшируем пароль
    hashed_password = get_password_hash(form_data.password)

    # 4. Создаём пользователя
    new_user = User(
        login=form_data.login,
        password=hashed_password,
        email=form_data.email,
        registration_date=datetime.now(timezone.utc).date(),
        verification_status_id=3,  #
    )

    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)

    return {
        "message": "Пользователь успешно зарегистрирован",
        "user_id": new_user.id,
        "login": new_user.login,
        "email": new_user.email,
    }

@app.get("/api/user/balance")
async def get_user_balance(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user["role"] != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    user_id = current_user["id"]

    try:
        query = text("SELECT calc_total_account_value(:user_id, 1) AS total_rub")
        result = await db.execute(query, {"user_id": user_id})
        total_rub = result.scalar()

        return {
            "total_balance_rub": round(float(total_rub or 0), 2)
        }
    except Exception as e:
        print(f"Ошибка расчёта баланса: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Ошибка сервера")

@app.get("/api/currency/usd-rate")
async def get_usd_rate(
    current_user: dict = Depends(get_current_user),  # защита авторизацией
    db: AsyncSession = Depends(get_db)
):
    # Опционально: можно разрешить только пользователям (не сотрудникам)
    if current_user["role"] != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    try:
        query = text("SELECT get_currency_rate(2) AS usd_rate")
        result = await db.execute(query)
        usd_rate = result.scalar()

        if usd_rate is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Курс USD не найден")

        usd_rate_rounded = round(float(usd_rate), 4)

        return {
            "currency": "USD",
            "rate_to_rub": usd_rate_rounded,
            "source": "get_currency_rate(2)"
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Ошибка получения курса USD: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Ошибка сервера при получении курса")

@app.post("/api/passport", status_code=status.HTTP_201_CREATED)
async def create_passport(
    form_data: PassportCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user["role"] != "user":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    user_id = current_user["id"]

    # Проверка: есть ли уже паспорт
    existing = await db.execute(
        select(Passport).where(Passport.user_id == user_id)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Паспорт уже привязан к пользователю"
        )

    passport = Passport(
        user_id=user_id,
        last_name=form_data.lastName,
        first_name=form_data.firstName,
        patronymic=form_data.middleName,
        series=form_data.series,
        number=form_data.number,
        gender=form_data.gender,
        birth_date=form_data.birthDate.date(),
        birth_place=form_data.birthPlace,
        registration_place=form_data.registrationPlace,
        issue_date=form_data.issueDate.date(),
        issued_by=form_data.issuedBy,
        is_actual = True
    )

    db.add(passport)
    await db.commit()
    await db.refresh(passport)

    return {
        "message": "Паспорт успешно создан",
        "passport_id": passport.id,
        "user_id": passport.user_id
    }

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

@app.get("/api/user/{user_id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Пользователь не найден")
    return {k: v for k, v in user.__dict__.items() if k != "_sa_instance_state"}

@app.get("/api/broker/proposal/{proposal_id}")
async def get_proposal_detail(
    proposal_id: int,
    db: AsyncSession = Depends(get_db)
):
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
    if current_user.get("role") != "broker":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещен")

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
):
    result = await db.execute(
        select(Staff)
        .options(selectinload(Staff.employment_status))
        .where(Staff.id == staff_id)
    )

    staff = result.scalar_one_or_none()

    if not staff:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Сотрудник не найден")

    return {
        "id": staff.id,
        "contract_number": staff.contract_number,
        "employment_status": staff.employment_status_id if staff.employment_status else "Неизвестен",
        "rights_level": staff.rights_level,
        "login": staff.login,
    }

class StaffUpdate(BaseModel):
    login: Optional[str] = None
    password: Optional[str] = None
    contract_number: Optional[str] = None
    rights_level: Optional[int] = None
    employment_status_id: Optional[int] = None

@app.put("/api/staff/{staff_id}")
async def update_staff(
    staff_id: int,
    data: StaffUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Staff).where(Staff.id == staff_id)
    )
    staff = result.scalar_one_or_none()

    if not staff:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Сотрудник не найден")
        
    result_login = await db.execute(
        select(Staff).where(Staff.login == data.login, Staff.id != staff_id)
    )
    if result_login.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Логин уже занят"
        )

    if data.login is not None:
        staff.login = data.login

    if data.password is not None and data.password != "":
        staff.password = get_password_hash(data.password)

    if data.contract_number is not None:
        staff.contract_number = data.contract_number

    if data.rights_level is not None:
        staff.rights_level = data.rights_level

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
    db: AsyncSession = Depends(get_db)
):
    # 1. Проверяем логин
    result_login = await db.execute(
        select(Staff).where(Staff.login == form_data.login)
    )
    if result_login.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Логин уже занят"
        )

    # 2. Хэшируем пароль
    hashed_password = get_password_hash(form_data.password)

    # 3. Создаём сотрудника
    new_staff = Staff(
        login=form_data.login,
        password=hashed_password,
        contract_number=form_data.contract_number,
        rights_level=form_data.rights_level,
        employment_status_id=form_data.employment_status_id,
    )

    db.add(new_staff)
    await db.commit()
    await db.refresh(new_staff)

    # 4. Возвращаем результат
    return {
        "message": "Сотрудник успешно создан",
        "staff_id": new_staff.id,
        "login": new_staff.login,
        "rights_level": new_staff.rights_level,
        "employment_status_id": new_staff.employment_status_id,
    }

@app.get("/api/user/{user_id}/passport")
async def get_user_passport(
    user_id: int,
    db: AsyncSession = Depends(get_db),
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


class UserVerificationUpdate(BaseModel):
    verification_status_id: int

@app.put("/api/user/{user_id}")
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
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Доступ запрещён")

    # Проверяем банк
    result = await db.execute(select(Bank).where(Bank.id == account_data.bank_id))
    bank = result.scalar_one_or_none()
    if not bank:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Банк не найден")

    # Проверяем валюту
    result = await db.execute(select(Currency).where(Currency.id == account_data.currency_id))
    currency = result.scalar_one_or_none()
    if not currency:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Валюта не найдена")

    # Создаём счёт с балансом 0
    new_account = BrokerageAccount(
        balance=Decimal("0.00"),
        bank_id=bank.id,
        bik=bank.bik,
        inn = " ",
        currency_id=currency.id,
        user_id=current_user["id"]
    )

    db.add(new_account)
    await db.commit()
    await db.refresh(new_account)

    return {
        "account_id": new_account.id,
        "balance": float(new_account.balance),
        "bank_id": bank.id,
        "bank_name": bank.name,
        "bik": bank.bik,
        "currency_id": currency.id,
        "currency_symbol": currency.symbol,
        "user_id": new_account.user_id
    }

class StockOut(BaseModel):
    id: int
    ticker: str
    price: Decimal
    currency: str
    change: float

    class Config:
        from_attributes = True


class StockCreate(BaseModel):
    ticker: str
    price: Decimal
    currency: str

@app.post("/api/exchange/stocks", status_code=status.HTTP_201_CREATED)
async def create_stock(
    data: StockCreate,
    db: AsyncSession = Depends(get_db),
):
    # Проверяем валюту
    result = await db.execute(
        select(Currency).where(Currency.code == data.currency)
    )
    currency = result.scalar_one_or_none()

    if not currency:
        raise HTTPException(
            status_code=400,
            detail="Валюта не найдена",
        )

    # Проверяем, существует ли акция
    result = await db.execute(
        select(Security).where(Security.isin == data.ticker)
    )
    exists = result.scalar_one_or_none()

    if exists:
        raise HTTPException(
            status_code=400,
            detail="Акция с таким тикером уже существует",
        )

    # Создаём акцию
    security = Security(
        name=data.ticker,
        isin=data.ticker,
        lot_size=Decimal("1.00"),
        dividend_payment=False,
        currency_id=currency.id,
    )
    db.add(security)
    await db.commit()
    await db.refresh(security)

    return {
        "message": "Акция добавлена",
        "id": security.id,
    }

class ProcessProposalRequest(BaseModel):
    verify: bool

@app.patch("/api/proposal/{proposal_id}/process")
async def process_proposal(
    proposal_id: int = Path(..., gt=0, description="ID предложения"),
    request_data: ProcessProposalRequest = None,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    print(f"DEBUG: current_user = {current_user}")  # Отладочная информация
    
    payload = current_user.get("payload")
    staff_id = payload.get("staff_id")
    
    if not staff_id:
        print(f"DEBUG: No staff_id found in token: {current_user}")
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
        print(f"DEBUG: Calling process_proposal with staff_id={staff_id}, proposal_id={proposal_id}, verify={verify}")
        
        # Вызов функции process_proposal из PostgreSQL
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
        print(f"ERROR in process_proposal: {error_msg}")
        
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
            detail=error_msg if status_code != 500 else "Внутренняя ошибка сервера при обработке заявки"
        )

def run():
    # uvicorn.run("main:app", host=settings.HOST, port=settings.PORT, reload=True)
    uvicorn.run("main:app", host=HOST, port=PORT, reload=True)


if __name__ == "__main__":
    run()