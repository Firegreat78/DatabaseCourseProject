from fastapi import APIRouter, Path, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import text, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from starlette import status

from core.config import BROKER_EMPLOYEE_ROLE
from db.auth import get_current_user
from db.models import Proposal
from db.session import get_db

async def verify_broker_role(current_user: dict = Depends(get_current_user)):
    if (current_user["type"] == "client") or (current_user["role"] != BROKER_EMPLOYEE_ROLE):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: endpoint'ы '/api/broker/...' доступны только для сотрудников-брокеров"
        )
    return current_user

broker_router = APIRouter(
    prefix="/api/broker",
    tags=["Broker API router"]
)

class ProcessProposalRequest(BaseModel):
    verify: bool

@broker_router.patch("/proposal/{proposal_id}/process")
async def process_proposal(
    proposal_id: int = Path(..., gt=0, description="ID предложения"),
    request_data: ProcessProposalRequest | None = None,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    payload = current_user.get("payload", {})
    staff_id = payload.get("staff_id")
    if not staff_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Не удалось определить ID сотрудника из токена"
        )

    verify = request_data.verify if request_data else False

    try:
        result = await db.execute(
            text("""
                SELECT public.process_proposal(
                    :staff_id,
                    :proposal_id,
                    :verify
                )
            """),
            {
                "staff_id": staff_id,
                "proposal_id": proposal_id,
                "verify": verify
            }
        )
        error_message = result.scalar()
        if error_message:
            msg = error_message.lower()

            if "не найден" in msg:
                status_code = status.HTTP_404_NOT_FOUND
            elif "недопустимый статус" in msg:
                status_code = status.HTTP_400_BAD_REQUEST
            elif "неизвестный тип" in msg:
                status_code = status.HTTP_400_BAD_REQUEST
            else:
                status_code = status.HTTP_500_INTERNAL_SERVER_ERROR

            raise HTTPException(
                status_code=status_code,
                detail=error_message
            )

        await db.commit()

        action = "подтверждена" if verify else "отклонена"
        return {
            "message": f"Заявка №{proposal_id} успешно {action}",
            "proposal_id": proposal_id,
            "action": "approved" if verify else "rejected"
        }

    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера при обработке заявки: {e}"
        )

@broker_router.get("/proposal")
async def get_all_proposals(
        db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Proposal)
        .options(
            selectinload(Proposal.security),
            selectinload(Proposal.proposal_type)
        )
        .order_by(Proposal.id.desc())
    )

    proposals = result.scalars().all()
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

@broker_router.get("/proposal/{proposal_id}")
async def get_proposal_detail(
        proposal_id: int,
        db: AsyncSession = Depends(get_db),
):
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