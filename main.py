import uvicorn
from datetime import timezone, datetime
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from db.session import get_db
from core.config import PORT, HOST
from db.auth import authenticate_staff, authenticate_user, create_access_token, get_password_hash, get_current_user
from pydantic import BaseModel, EmailStr, field_validator

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
    staff = await authenticate_staff(db, form_data.login, form_data.password)  # form_data
    if not staff:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный логин или пароль",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token = create_access_token(
        data={"sub": staff.login, "role": "staff", "staff_id": staff.id}
    )
    return {"access_token": access_token, "token_type": "bearer"}


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
        verification_status_id=1,  #
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
        raise HTTPException(status_code=403, detail="Доступ запрещён")

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
        raise HTTPException(status_code=500, detail="Ошибка сервера")


@app.get("/api/currency/usd-rate")
async def get_usd_rate(
    current_user: dict = Depends(get_current_user),  # защита авторизацией
    db: AsyncSession = Depends(get_db)
):
    # Опционально: можно разрешить только пользователям (не сотрудникам)
    if current_user["role"] != "user":
        raise HTTPException(status_code=403, detail="Доступ запрещён")

    try:
        query = text("SELECT get_currency_rate(2) AS usd_rate")
        result = await db.execute(query)
        usd_rate = result.scalar()

        if usd_rate is None:
            raise HTTPException(status_code=404, detail="Курс USD не найден")

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
        raise HTTPException(status_code=500, detail="Ошибка сервера при получении курса")

@app.post("/api/passport", status_code=status.HTTP_201_CREATED)
async def create_passport(
    form_data: PassportCreateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if current_user["role"] != "user":
        raise HTTPException(status_code=403, detail="Доступ запрещён")

    user_id = current_user["id"]

    # Проверка: есть ли уже паспорт
    existing = await db.execute(
        select(Passport).where(Passport.user_id == user_id)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
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





def run():
    # uvicorn.run("main:app", host=settings.HOST, port=settings.PORT, reload=True)
    uvicorn.run("main:app", host=HOST, port=PORT, reload=True)


if __name__ == "__main__":
    run()
