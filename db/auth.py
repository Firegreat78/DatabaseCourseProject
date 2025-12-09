# db/auth.py
import bcrypt
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict
from jose import jwt, JWTError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from db.models.models import User, Staff

# Настройки
SECRET_KEY = "your-secret-key-change-in-production-12345"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

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
    # ✅ Исправлено: timezone-aware now
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=15))
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


def decode_access_token(token: str) -> Optional[Dict]:
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[ALGORITHM]
        )
        # ✅ Также можно проверить, что exp — timezone-aware, но jwt.decode возвращает int/unixtime
        # Поэтому дополнительной обработки не нужно
        return payload
    except JWTError:
        return None