from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timezone

from db.models.models import User
from db.auth import authenticate_user, create_access_token, get_password_hash


async def login_user(db: AsyncSession, login: str, password: str):
    user = await authenticate_user(db, login, password)
    if not user:
        return None

    token = create_access_token({
        "sub": user.login,
        "role": "user",
        "user_id": user.id
    })

    return token


async def register_user(db: AsyncSession, login: str, email: str, password: str):
    # проверка логина
    if (await db.execute(select(User).where(User.login == login))).scalar_one_or_none():
        return "login_taken"

    # проверка email
    if (await db.execute(select(User).where(User.email == email))).scalar_one_or_none():
        return "email_taken"

    hashed = get_password_hash(password)

    new_user = User(
        login=login,
        email=email,
        password=hashed,
        registration_date=datetime.now(timezone.utc).date(),
        verification_status_id=1
    )

    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)

    return new_user
