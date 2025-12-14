from sqlalchemy.ext.asyncio import AsyncSession
from db.auth import authenticate_staff, create_access_token


async def login_staff(db: AsyncSession, login: str, password: str):
    staff = await authenticate_staff(db, login, password)
    if not staff:
        return None

    token = create_access_token({
        "sub": staff.login,
        "role": "staff",
        "staff_id": staff.id,
    })

    return token
