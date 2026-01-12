from decimal import Decimal
from typing import List

from fastapi import Depends, HTTPException, APIRouter
from pydantic import BaseModel, EmailStr, field_validator
from sqlalchemy import text, select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette import status

from core.config import EMPLOYMENT_STATUS_ID_BLOCKED, USER_BAN_STATUS_ID, TABLES
from db.auth import get_password_hash, authenticate_staff, create_access_token, authenticate_user, get_current_user
from db.session import get_db

public_router = APIRouter(
    prefix="/api/public",
    tags=["Public API router"]
)

class UserRegisterRequest(BaseModel):
    login: str
    email: EmailStr
    password: str

    class Config:
        from_attributes = True

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if len(v.encode("utf-8")) > 72:
            raise ValueError("Пароль слишком длинный (максимум ~70 символов)")
        if len(v) < 6:
            raise ValueError("Пароль должен содержать минимум 6 символов")
        return v


@public_router.post(
    "/register/user",
    status_code=status.HTTP_201_CREATED,
    summary="Регистрация пользователя"
)

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
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Ошибка вызова процедуры регистрации"
        )

    user_id = row[0]
    error_message = row[1]

    if error_message is not None:
        if error_message == "Логин уже занят":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )
        elif error_message == "Email уже зарегистрирован":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Ошибка регистрации: {error_message}"
            )

    await db.commit()

    return {
        "message": "Пользователь успешно зарегистрирован",
        "user_id": user_id,
        "login": form_data.login,
        "email": form_data.email,
    }

class Token(BaseModel):
    access_token: str
    token_type: str
    user_id: int
    role: str = "user"

class LoginRequest(BaseModel):
    login: str
    password: str

@public_router.post(
    "/login/user",
    response_model=Token,
    summary="Вход пользователя"
)
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
    elif user.block_status_id == USER_BAN_STATUS_ID:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Аккаунт заблокирован",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = create_access_token(
        data={
            "sub": user.login,
            "role": "user",
            "user_id": user.id
        }
    )
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": user.id,
        "role": "user"
    }


@public_router.post(
    "/login/staff",
    response_model=Token,
    summary="Вход сотрудника"
)
async def login_staff(
        form_data: LoginRequest,
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
        data={
            "sub": staff.login,
            "role": staff.rights_level_id,
            "staff_id": staff.id
        }
    )
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user_id": staff.id,
        "role": str(staff.rights_level_id)
    }

class StockInfoOut(BaseModel):
    id: int
    ticker: str
    isin: str
    lot_size: Decimal
    price: Decimal
    currency: str
    change: Decimal
    is_archived: bool

    class Config:
        from_attributes = True
        json_encoders = {
            Decimal: lambda v: float(v) if v is not None else None
        }


@public_router.get(
    "/exchange/stocks",
    response_model=List[StockInfoOut]
)
async def get_stocks(
        db: AsyncSession = Depends(get_db),
        current_user: dict = Depends(get_current_user),
):
    user_type = current_user.get("type")
    if user_type == "staff":
        query = text("SELECT * FROM get_exchange_stocks()")
    elif user_type == "client":
        query = text("SELECT * FROM get_exchange_stocks() WHERE NOT is_archived")
    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён"
        )
    result = await db.execute(query)
    rows = result.fetchall()
    return [dict(row._mapping) for row in rows]


@public_router.get("/{table_name}")
async def get_table_data(table_name: str, db: AsyncSession = Depends(get_db)):
    model = TABLES.get(table_name)
    if not model:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Table '{table_name}' not found in tables: {TABLES}"
        )
    result = await db.execute(select(model).order_by(model.id))
    rows = result.scalars().all()

    data = [
        {k: v for k, v in row.__dict__.items() if k != "_sa_instance_state"}
        for row in rows
    ]
    return data