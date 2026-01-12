# db/auth.py
import bcrypt
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict
from jose import jwt, JWTError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from core.config import MEGAADMIN_EMPLOYEE_ROLE, ADMIN_EMPLOYEE_ROLE, BROKER_EMPLOYEE_ROLE, VERIFIER_EMPLOYEE_ROLE
from db.models.models import User, Staff
from fastapi import HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from .session import get_db

bearer_scheme = HTTPBearer()

SECRET_KEY = "your-secret-key-change-in-production-12345"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 1000


def verify_password(plain_password: str, hashed_password: str) -> bool:
    password_bytes = plain_password.encode("utf-8")[:72]
    hashed_bytes = hashed_password.encode("utf-8")
    return bcrypt.checkpw(password_bytes, hashed_bytes)


def get_password_hash(password: str) -> str:
    password_bytes = password.encode("utf-8")[:72]
    hashed = bcrypt.hashpw(password_bytes, bcrypt.gensalt())
    return hashed.decode("utf-8")


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
        role = payload.get("role")
        staff_id = payload.get("staff_id")
        user_id = payload.get("user_id")

        if staff_id is not None:
            if not isinstance(role, int) or role not in [
                MEGAADMIN_EMPLOYEE_ROLE,
                ADMIN_EMPLOYEE_ROLE,
                BROKER_EMPLOYEE_ROLE,
                VERIFIER_EMPLOYEE_ROLE
            ]:
                raise credentials_exception

            user_type = "staff"
            id_to_check = staff_id
        elif user_id is not None and role == "user":
            user_type = "client"
            id_to_check = user_id
        else:
            raise credentials_exception

    except JWTError:
        raise credentials_exception

    if user_type == "staff":
        exists = await db.scalar(select(Staff.id).where(Staff.id == id_to_check))
        if exists is None:
            raise credentials_exception
    else:
        exists = await db.scalar(select(User.id).where(User.id == id_to_check))
        if exists is None:
            raise credentials_exception

    return {
        "id": id_to_check,
        "role": role,  # для staff — число, для клиента — "user"
        "type": user_type,  # "staff" или "client"
        "staff_id": staff_id if user_type == "staff" else None,
        "user_id": user_id if user_type == "client" else None,
        "payload": payload
    }