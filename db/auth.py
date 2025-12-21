# db/auth.py
import bcrypt
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict
from jose import jwt, JWTError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from db.models.models import User, Staff
from fastapi import HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from .session import get_db

bearer_scheme = HTTPBearer()

# Настройки
SECRET_KEY = "your-secret-key-change-in-production-12345"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 1000


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Проверяет пароль.
    """
    password_bytes = plain_password.encode("utf-8")[:72]
    hashed_bytes = hashed_password.encode("utf-8")
    return bcrypt.checkpw(password_bytes, hashed_bytes)


def get_password_hash(password: str) -> str:
    """
    Хэширует пароль с bcrypt + обрезкой до 72 байт (стандарт bcrypt).
    """
    # Обрезаем до 72 байт для безопасности
    password_bytes = password.encode("utf-8")[:72]
    # salt автоматически генерируется
    hashed = bcrypt.hashpw(password_bytes, bcrypt.gensalt())
    return hashed.decode("utf-8")  # возвращаем str для SQLAlchemy


def create_access_token(data: Dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


async def authenticate_user(db: AsyncSession, login: str, password: str) -> Optional[User]:
    result = await db.execute(select(User).where(User.login == login))
    user = result.scalar_one_or_none()
    if not user or not verify_password(password, user.password):
        return None
    return user


async def authenticate_staff(db: AsyncSession, login: str, password: str) -> Optional[Staff]:
    result = await db.execute(select(Staff).where(Staff.login == login))
    staff = result.scalar_one_or_none()
    if not staff or not verify_password(password, staff.password):
        return None
    return staff


async def get_current_user(
    token: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db)
) -> Dict:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Не удалось проверить учетные данные",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = jwt.decode(token.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: int = payload.get("user_id")
        role: str = payload.get("role")
        if user_id is None and role not in ["1", "2", "3", "4", "5"]:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    # Опционально: проверяем, существует ли пользователь в БД (защита от поддельных токенов)
    if role == "user" and user_id:
        result = await db.execute(select(User.id).where(User.id == user_id))
        if not result.scalar_one_or_none():
            raise credentials_exception
    elif role == "staff":
        staff_id = payload.get("staff_id")
        if not staff_id:
            raise credentials_exception

        # Проверяем существование сотрудника по ID
        exists = await db.scalar(select(Staff.id).where(Staff.id == staff_id))  # type: ignore[arg-type]
        if exists is None:
            raise credentials_exception

    return {"id": user_id, "role": role, "payload": payload}