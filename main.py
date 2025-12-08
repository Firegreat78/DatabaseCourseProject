from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from db.session import get_db
from db.models.models import (
    Bank,
    BrokerageAccount,
    BrokerageAccountHistory,
    BrokerageAccountOperationType,
    Currency,
    CurrencyRates,
    DepositoryAccount,
    DepositoryAccountBalance,
    DepositoryAccountHistory,
    DepositoryAccountOperationType,
    Dividend,
    EmploymentStatus,
    Passport,
    PriceHistory,
    Proposal,
    ProposalType,
    Security,
    Staff,
    User,
    VerificationStatus
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
    "security": Security,
    "currency": Currency,
    "employment_status": EmploymentStatus,
    "bank": Bank,
    "user": User,
    "staff": Staff,
    "proposal": Proposal,
    "brokerage_account": BrokerageAccount,
    "depository_account": DepositoryAccount,
    "dividend": Dividend,
    "passport": Passport,
    "brokerage_account_history": BrokerageAccountHistory,
    "depository_account_history": DepositoryAccountHistory,
    "depository_account_balance": DepositoryAccountBalance,
    "price_history": PriceHistory,
    "currency_rates": CurrencyRates
}


@app.get("/api/{table_name}")
async def get_table_data(table_name: str, db: AsyncSession = Depends(get_db)):
    model = TABLES.get(table_name)
    if not model:
        return {"error": f"Table not found (given={table_name})"}
    print(f"before result model={model}")
    result = await db.execute(select(model))
    print(f"after result model={model}")
    rows = result.scalars().all()

    data = [
        {k: v for k, v in row.__dict__.items() if k != "_sa_instance_state"}
        for row in rows
    ]
    return data

@app.get("/ping-db")
async def ping_db(db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(text("SELECT 1"))
        return {"connected": True, "result": result.scalar()}
    except Exception as e:
        return {"connected": False, "error": str(e)}
    
