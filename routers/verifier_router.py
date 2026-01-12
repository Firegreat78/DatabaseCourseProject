# routers/verifier_router.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text, select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette import status
from starlette.responses import Response

from core.config import VERIFIER_EMPLOYEE_ROLE
from db.auth import get_current_user
from db.models import Passport, User
from db.session import get_db

async def verify_verifier_role(current_user: dict = Depends(get_current_user)):
    if (current_user["type"] == "client") or (current_user["role"] != VERIFIER_EMPLOYEE_ROLE):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: endpoint'ы '/api/verifier/...' доступны только для сотрудников-верификаторов"
        )
    return current_user

verifier_router = APIRouter(
    prefix="/api/verifier",
    tags=["Verifier API router"],
    dependencies=[Depends(verify_verifier_role)],
)

@verifier_router.post("/{user_id}/verify_passport")
async def call_verify_user_passport(
    user_id: int,
    db: AsyncSession = Depends(get_db),
):
    passport_result = await db.execute(
        text('SELECT "ID паспорта" FROM public."Паспорт" WHERE "ID пользователя" = :user_id'),
        {"user_id": user_id}
    )
    passport_row = passport_result.fetchone()
    if not passport_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Паспорт пользователя не найден"
        )
    passport_id = passport_row[0]
    try:
        result = await db.execute(
            text("SELECT public.verify_user_passport(:passport_id)"),
            {"passport_id": passport_id}
        )

        error_message = result.scalar()

        if error_message:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message
            )

        await db.commit()

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Ошибка сервера при верификации паспорта: {e}"
        )

    return {
        "message": "Верификация паспорта успешно завершена",
        "user_id": user_id,
        "passport_id": passport_id
    }

@verifier_router.delete(
    "/user/{user_id}/passport",
    status_code=status.HTTP_204_NO_CONTENT
)
async def delete_user_passport(
        user_id: int,
        db: AsyncSession = Depends(get_db),
):
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

@verifier_router.get("/user/{user_id}/passport")
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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Паспорт пользователя с ID={user_id} не найден"
        )

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