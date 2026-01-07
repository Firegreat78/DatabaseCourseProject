import os

# postgresql+asyncpg://<username>:<password>@<host>:<port>/<database_name>
DATABASE_URL = "postgresql+asyncpg://postgres:12345@localhost:5432/DB_Course"
HOST = "localhost"
PORT = 8000

# USERS
USER_BAN_STATUS_ID = 2

# EMPLOYEES
MEGAADMIN_EMPLOYEE_ROLE = 1
ADMIN_EMPLOYEE_ROLE = 2
BROKER_EMPLOYEE_ROLE = 3
VERIFIER_EMPLOYEE_ROLE = 4
SYSTEM_STAFF_ID = 2
EMPLOYMENT_STATUS_ID_BLOCKED = 2
