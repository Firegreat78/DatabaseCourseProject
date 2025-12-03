from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session
from core.config import DATABASE_URL

from db.models import (
    DepositAccountOperationType,
    BrokerAccountOperationType,
    OfferType,
    VerificationStatus,
    Position,
    Security,
    Currency,
    Bank,
)

engine = create_engine(DATABASE_URL, echo=False, future=True)


# Список всех справочников для красивого вывода
TABLES = [
    ("Тип операции депозитарного счёта", DepositAccountOperationType),
    ("Тип операции брокерского счёта", BrokerAccountOperationType),
    ("Тип предложения", OfferType),
    ("Статус верификации", VerificationStatus),
    ("Должности", Position),
    ("Список ценных бумаг", Security),
    ("Список валют", Currency),
    ("Банк", Bank),
]


def print_all_data():
    with Session(engine) as session:
        print("=" * 80)
        print("ПРОВЕРКА ДАННЫХ В СПРАВОЧНИКАХ (заполнено через pgAdmin)")
        print("=" * 80)

        for rus_name, model in TABLES:
            records = session.query(model).order_by(model.id).all()

            print(f"\n→ {rus_name}  ({len(records)} записей)")
            print("-" * 60)

            if not records:
                print("    (пусто)")
                continue

            # Выводим только те поля, которые есть и имеют смысл показать
            for rec in records:
                if isinstance(rec, Currency):
                    print(f"    {rec.id:>3} | {rec.name}")
                elif isinstance(rec, Security):
                    print(f"    {rec.id:>3} | {rec.name[:50]:50} | ISIN: {rec.isin} | Дивиденды: {rec.pays_dividends}")
                elif isinstance(rec, Bank):
                    print(f"    {rec.id:>3} | {rec.name[:40]:40} | ИНН: {rec.inn} | до {rec.license_expiry_date}")
                elif isinstance(rec, Position):
                    print(f"    {rec.id:>3} | {rec.name:20} | ЗП: {rec.salary:>10} ₽ | {rec.access_level}")
                else:
                    # Для всех остальных — просто id и название
                    name_field = getattr(rec, "type_name", None) or getattr(rec, "status_name", None) or "?"
                    print(f"    {rec.id:>3} | {name_field}")

        print("\n" + "="*80)
        print("Всё работает! Данные из pgAdmin успешно читаются через SQLAlchemy")
        print("="*80)


if __name__ == "__main__":
    try:
        # Простая проверка подключения
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("Подключение к базе успешно!")
        print_all_data()
    except Exception as e:
        print("ОШИБКА ПОДКЛЮЧЕНИЯ:")
        print(e)