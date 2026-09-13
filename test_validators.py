# test_validators.py
# Проверка чек-сумм ISIN и ИНН, реализованных в PL/pgSQL.
# Запуск: DATABASE_URL=... python test_validators.py
import asyncio
import os

import asyncpg

# (значение, ожидаемый результат)
ISIN = [
    ("US0378331005", True),   # Apple
    ("RU0009029540", True),   # Сбербанк
    ("US0378331006", False),  # испорчена контрольная цифра
    ("US037833100", False),   # короче 12 символов
    (None, False),
]
INN_LEGAL = [
    ("7707083893", True),     # Сбербанк
    ("7707083890", False),    # испорчена контрольная цифра
    ("500100732259", False),  # ИНН физлица, не подходит
]
INN_INDIVIDUAL = [
    ("500100732259", True),
    ("500100732250", False),  # испорчена вторая контрольная цифра
    ("7707083893", False),    # ИНН юрлица, не подходит
]


async def main():
    dsn = os.environ["DATABASE_URL"].replace("+asyncpg", "")
    conn = await asyncpg.connect(dsn)
    try:
        for fn, cases in [
            ("is_valid_isin", ISIN),
            ("validate_russian_inn_legal", INN_LEGAL),
            ("is_valid_rus_inn_individual", INN_INDIVIDUAL),
        ]:
            for value, expected in cases:
                actual = await conn.fetchval(f"SELECT public.{fn}($1)", value)
                assert actual == expected, f"{fn}({value!r}) = {actual}, ожидалось {expected}"
    finally:
        await conn.close()
    print("OK")


if __name__ == "__main__":
    asyncio.run(main())
