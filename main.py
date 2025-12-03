from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from db.session import get_db
from db.models.models import (
    DepositoryAccountOperationType, BrokerageAccountOperationType,
    ProposalType, VerificationStatus, Position, Security, Currency, Bank
)

app = FastAPI()

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
    "position": Position,
    "security": Security,
    "currency": Currency,
    "bank": Bank,
}


@app.get("/api/{table_name}")
async def get_table_data(table_name: str, db: AsyncSession = Depends(get_db)):
    model = TABLES.get(table_name)
    if not model:
        return {"error": "Table not found"}
    print(f"before result model={model}")
    result = await db.execute(select(model))
    print(f"after result model={model}")
    rows = result.scalars().all()

    data = [
        {k: v for k, v in row.__dict__.items() if k != "_sa_instance_state"}
        for row in rows
    ]
    return data
