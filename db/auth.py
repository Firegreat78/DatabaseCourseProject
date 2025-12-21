# db/auth.py
import bcrypt
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict
from jose import jwt, JWTError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from fastapi import HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

# ИЗМЕНЕНИЕ: используем абсолютный импорт вместо относительного
from db.session import get_db
from db.models.models import User, Staff

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
        staff_id: int = payload.get("staff_id")
        role: str = payload.get("role")

        # Проверяем, есть ли у нас нужные поля
        if role is None:
            raise credentials_exception

    except JWTError:
        raise credentials_exception

    # Если есть staff_id, значит это сотрудник
    if staff_id is not None:
        # Проверяем существование сотрудника
        result = await db.execute(select(Staff).where(Staff.id == staff_id))
        staff = result.scalar_one_or_none()
        if not staff:
            raise credentials_exception

        # Для сотрудника role - это rights_level, возвращаем его как роль
        return {
            "id": staff_id,
            "user_id": user_id,  # user_id может быть None для сотрудников
            "staff_id": staff_id,
            "role": role,  # это rights_level: "1", "2", "3", "4", "5"
            "rights_level": role,  # дублируем для совместимости
            "payload": payload
        }

    # Если нет staff_id, но есть user_id, значит это пользователь
    elif user_id is not None:
        # Проверяем существование пользователя
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user:
            raise credentials_exception

        return {
            "id": user_id,
            "user_id": user_id,
            "role": role,  # должно быть "user"
            "payload": payload
        }

    # Если ни одного ID нет
    else:
        raise credentials_exception