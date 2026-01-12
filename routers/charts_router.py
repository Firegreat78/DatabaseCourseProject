from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from db.auth import get_current_user
from db.session import get_db

charts_router = APIRouter(
    prefix='/charts',
    tags=['Charts API router']
)

class DepositaryBalanceChartItem(BaseModel):
    security_name: str
    quantity: Decimal

    class Config:
        from_attributes = True

@charts_router.get(
    "/depositary-balance",
    response_model=list[DepositaryBalanceChartItem]
)
async def get_depositary_balance_chart(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    user_id = current_user["id"]

    query = text("""
        SELECT
            ss."Наименование" AS security_name,
            b."Сумма"         AS quantity
        FROM public."Баланс депозитарного счёта" b
        JOIN public."Список ценных бумаг" ss
            ON ss."ID ценной бумаги" = b."ID ценной бумаги"
        WHERE
            b."ID пользователя" = :user_id
            AND b."Сумма" > 0
        ORDER BY ss."Наименование"
    """)

    result = await db.execute(query, {"user_id": user_id})

    return [
        DepositaryBalanceChartItem(**row)
        for row in result.mappings().all()
    ]


class DepositaryOperationsChartItem(BaseModel):
    operation_type: str
    security_name: str
    total_amount: Decimal
    operations_count: int

    class Config:
        from_attributes = True


@charts_router.get(
    "/depositary-operations",
    response_model=list[DepositaryOperationsChartItem]
)
async def get_depositary_operations_chart(
    db: AsyncSession = Depends(get_db)
):
    query = text("""
        SELECT 
            t."Тип"               AS operation_type,
            s."Наименование"      AS security_name,
            SUM(h."Сумма операции") AS total_amount,
            COUNT(*)              AS operations_count
        FROM public."История операций деп. счёта" h
        JOIN public."Тип операции депозитарного счёта" t 
            ON h."ID типа операции деп. счёта" = t."ID типа операции деп. счёта"
        JOIN public."Список ценных бумаг" s 
            ON h."ID ценной бумаги" = s."ID ценной бумаги"
        GROUP BY 
            t."Тип",
            s."Наименование"
        ORDER BY 
            t."Тип",
            s."Наименование"
    """)

    result = await db.execute(query)

    return [
        dict(row._mapping)
        for row in result.all()
    ]