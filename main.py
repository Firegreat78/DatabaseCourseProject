# main.py
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from core.config import *
from routers.admin_router import admin_router
from routers.broker_router import broker_router
from routers.charts_router import charts_router
from routers.public_router import public_router
from routers.staff_router import staff_router
from routers.user_router import user_router
from routers.verifier_router import verifier_router

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