from db.models.models import (
    AdminRightsLevel,
    Bank,
    BrokerageAccount,
    BrokerageAccountHistory,
    BrokerageAccountOperationType,
    Currency,
    CurrencyRate,
    DepositoryAccount,
    DepositoryAccountBalance,
    DepositoryAccountHistory,
    DepositoryAccountOperationType,
    EmploymentStatus,
    Passport,
    PriceHistory,
    Proposal,
    ProposalType,
    Security,
    Staff,
    User,
    VerificationStatus,
    UserRestrictionStatus,
    ProposalStatus
)

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

BALANCE_INCREASE_ID = 1
BALANCE_DECREASE_ID = 2

TABLES = {
    "admin_rights_level": AdminRightsLevel,
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
    "proposal_type": ProposalType,
    "proposal_status": ProposalStatus,
    "brokerage_account": BrokerageAccount,
    "depository_account": DepositoryAccount,
    "passport": Passport,
    "brokerage_account_history": BrokerageAccountHistory,
    "depository_account_history": DepositoryAccountHistory,
    "depository_account_balance": DepositoryAccountBalance,
    "price_history": PriceHistory,
    "currency_rate": CurrencyRate,
    "user_restriction_status": UserRestrictionStatus
}