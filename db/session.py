from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from core.config import DATABASE_URL


engine = create_engine(DATABASE_URL, echo=True)  # echo=True для логов SQL
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


# зависимость для FastAPI
def get_db():
    db = SessionLocal()
    try: yield db
    finally: db.close()
