from datetime import date

import uvicorn
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from core.config import *
from db.models.models import (
    User
)
from db.session import get_db
from routers.admin_routers import admin_router
from routers.broker_routers import broker_router
from routers.charts_routers import charts_router
from routers.public_routers import public_router
from routers.staff_routers import staff_router
from routers.user_routers import user_router
from routers.verifier_routers import verifier_router

app = FastAPI()
app.include_router(user_router)
app.include_router(charts_router)
app.include_router(staff_router)
app.include_router(admin_router)
app.include_router(broker_router)
app.include_router(verifier_router)
app.include_router(public_router)

# Разрешаем React dev сервер
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def run():
    uvicorn.run(
        "main:app",
        host=HOST,
        port=PORT,
        reload=True
    )

if __name__ == "__main__":
    run()