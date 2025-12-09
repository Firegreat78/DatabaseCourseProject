from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession

async def get_all(model, db: AsyncSession):
    result = await db.execute(select(model))
    rows = result.scalars().all()

    return [
        {k: v for k, v in row.__dict__.items() if k != "_sa_instance_state"}
        for row in rows
    ]
