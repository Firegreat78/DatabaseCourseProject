from typing import Optional

from fastapi import Depends, HTTPException, APIRouter
from pydantic import field_validator, BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette import status

from db.auth import get_current_user, get_password_hash
from db.models import Staff, UserRestrictionStatus, VerificationStatus, User
from db.session import get_db

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

async def verify_staff_role(current_user: dict = Depends(get_current_user)):
    if current_user["type"] != "staff":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: endpoint'ы '/api/staff/...' доступны только для сотрудников"
        )
    return current_user

staff_router = APIRouter(
    prefix="/api/staff",
    tags=["Staff API router"],
    dependencies=[Depends(verify_staff_role)],
)

@staff_router.get("/{staff_id}")
async def get_staff_profile(
        staff_id: int,
        db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Staff).where(Staff.id == staff_id))
    staff = result.scalar_one_or_none()

    if not staff:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Сотрудник не найден"
        )

    return {
        "id": staff.id,
        "contract_number": staff.contract_number,
        "employment_status": staff.employment_status_id,
        "rights_level": staff.rights_level_id,
        "login": staff.login,
    }

@staff_router.put("/user/{user_id}")
async def update_user(
        user_id: int,
        data: UserUpdate,
        db: AsyncSession = Depends(get_db),
):
    # Получаем пользователя
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Пользователь не найден"
        )

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
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Неверный статус верификации"
            )

    if data.block_status_id is not None:
        result = await db.execute(select(UserRestrictionStatus).where(UserRestrictionStatus.id == data.block_status_id))
        if not result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Неверный статус блокировки"
            )

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