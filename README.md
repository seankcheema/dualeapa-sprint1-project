# Trading Season

A comprehensive trading platform built with a modern tech stack featuring Angular frontends, Spring Boot services, and PostgreSQL.

---

## Team: DuaLEAPa

| Name | Role |
|:-----|:-----|
| Sean Cheema | Team Lead / Frontend Developer |
| Chris Chang | Full Stack Engineer |
| Soli Ateefa | Data Engineer |
| Prisca Olose | Full Stack / Security |
| Mohammed Shaoib | Full Stack Engineer |

---

## Project Overview

**Platform:** Trading Platform  
**Status:** Sprint 4 
**Last Updated:** 9/9/26

---

## Project Architecture

```
dualeapa-sprint1-project/
│
├── README.md                                  ← Navigation Hub
├── .agent.md                                  ← AI Guidance
│
├── apps/                                      ← Deployable Applications
│   │
│   ├── business-logic-ui/                     ← Angular 22.1 Business UI
│   │   ├── README.md
│   │   ├── .agent.md
│   │   ├── package.json
│   │   ├── angular.json
│   │   ├── src/
│   │   └── Dockerfile
│   │
│   ├── reporting-ui/                          ← Angular 22.1 Reporting UI
│   │   ├── README.md
│   │   ├── .agent.md
│   │   ├── package.json
│   │   ├── angular.json
│   │   ├── src/
│   │   └── Dockerfile
│   │
│   ├── business-backend/                      ← Spring Boot API + Database
│   │   ├── README.md
│   │   ├── .agent.md
│   │   ├── pom.xml
│   │   ├── src/
│   │   ├── db/
│   │   │   └── migrations/                    ← Flyway (V001, V002, V003...)
│   │   └── Dockerfile
│   │
│   ├── reporting-service/                     ← Spring Boot Reporting Service
│   │   ├── README.md
│   │   ├── .agent.md
│   │   ├── pom.xml
│   │   ├── src/
│   │   └── Dockerfile
│   │
│   └── auth-service/                          ← Next.js Authentication Service
│       ├── README.md
│       ├── .agent.md
│       ├── src/
│       │   └── app/api/auth/
│       │       ├── login/
│       │       ├── register/
│       │       ├── refresh/
│       │       └── verify/
│       └── Dockerfile
│
├── packages/                                  ← Shared Libraries
│   │
│   ├── shared-ui-components/                  ← Reusable Angular Components
│   └── api-contracts/                         ← OpenAPI Schemas & DTOs
│
├── scripts/                                   ← Python Analytics & Backtesting
│   ├── README.md
│   ├── .agent.md
│   ├── requirements.txt
│   ├── backtesting/
│   │   └── run_backtest.py + strategies
│   └── analytics/
│       └── report_generator.py
│
├── infrastructure/                            ← DevOps & Deployment
│   ├── README.md
│   ├── .agent.md
│   ├── docker/
│   ├── docker-compose/
│   │   ├── docker-compose.local.yml
│   │   └── docker-compose.prod.yml
│   ├── nginx/
│   └── jenkins/
│       ├── Jenkinsfile
│       └── pipeline-scripts/
│
├── docs/                                      ← Centralized Documentation
│   ├── ARCHITECTURE.md
│   ├── API_REFERENCE.md
│   ├── DATABASE.md
│   ├── DEVELOPMENT_WORKFLOW.md
│   ├── DEPLOYMENT.md
│   └── JAVA_DOCS.md
│
├── .github/
│   └── workflows/                             ← GitHub Actions
│
├── package.json                               ← Monorepo Configuration
└── turbo.json                                 ← Turborepo Task Runner


## Our Entity-Relationships (ER) Diagram

```mermaid
erDiagram
    USERS ||--o{ SESSIONS : "has"
    USERS ||--o{ ACCOUNTS : "owns"
    ACCOUNTS ||--o{ ORDERS : "places"
    ACCOUNTS ||--o{ HOLDINGS : "holds"
    ACCOUNTS ||--o{ CASH_TRANSACTIONS : "records"
    ACCOUNTS ||--o{ HOLDING_MOVEMENTS : "records"
    INSTRUMENTS ||--o| STOCKS : "has sim data"
    INSTRUMENTS ||--o{ PRICE_POINTS : "generates"
    INSTRUMENTS ||--o{ MARKET_TICKS : "generates"
    INSTRUMENTS ||--o{ QUOTES : "generates"
    INSTRUMENTS ||--o{ CANDLES : "generates"
    INSTRUMENTS ||--o{ MARKET_STATE : "has"
    INSTRUMENTS ||--o{ HOLDINGS : "held as"
    INSTRUMENTS ||--o{ ORDERS : "traded in"
    INSTRUMENTS ||--o{ HOLDING_MOVEMENTS : "moves"
    ORDERS ||--o| FILLS : "executes as"
    ORDERS ||--o{ AUDIT_TRAIL : "logs"
    FILLS ||--o| CASH_TRANSACTIONS : "produces"
    FILLS ||--|| HOLDING_MOVEMENTS : "produces"

    USERS {
        uuid user_id PK
        text username UK
        text password_hash "secret"
        text email UK
        text ssn "PII"
        date date_of_birth "PII"
        text trader_level "BEGINNER/INTERMEDIATE/ADVANCED"
        numeric available_funds "financial"
        text user_role "ADMIN/TRADER"
        text account_status "ACTIVE/DEACTIVATED"
        int session_timeout_minutes
        numeric execution_buffer_percent
        int failed_login_attempts "internal"
        timestamptz locked_until "internal"
        text reset_token "secret"
        timestamptz reset_token_expires_at "internal"
        timestamptz last_login_at
        timestamptz last_activity_at
        timestamptz created_at
    }

    SESSIONS {
        uuid session_id PK
        uuid user_id FK
        timestamptz issued_at
        timestamptz expires_at
        timestamptz revoked_at "internal"
        timestamptz last_seen_at
    }

    INSTRUMENTS {
        int instrument_id PK
        text ticker UK
        text name
        text asset_class "Equity/FX/Crypto"
        text market "UK/US/IN, equities only"
        text currency
        bool is_tradable
    }

    STOCKS {
        int instrument_id PK_FK
        text company_name
        numeric starting_price
        text sector
        bigint average_volume
        numeric base_volatility
    }

    ACCOUNTS {
        int account_id PK
        uuid user_id FK
        numeric cash_balance "financial, cache of cash_transactions"
        date opened_date
        text currency
    }

    PRICE_POINTS {
        int price_point_id PK
        int instrument_id FK
        numeric price
        bigint sequence_number UK "per-instrument, monotonic"
        timestamptz observed_at
    }

    MARKET_TICKS {
        int tick_id PK
        int instrument_id FK
        numeric price
        numeric bid
        numeric ask
        int bid_size
        int ask_size
        int trade_volume
        bigint sequence_number UK
        timestamptz observed_at
    }

    QUOTES {
        int quote_id PK
        int instrument_id FK
        numeric bid
        numeric ask
        int bid_size
        int ask_size
        timestamptz observed_at
    }

    CANDLES {
        int candle_id PK
        int instrument_id FK
        text interval UK "e.g. 1m, 5m, 1h, 1d"
        timestamptz period_start UK
        numeric open
        numeric high
        numeric low
        numeric close
        int volume
        int trade_count
    }

    MARKET_STATE {
        int market_state_id PK
        int instrument_id FK
        text trend "normal/uptrend/downtrend/sideways"
        numeric volatility "internal"
        double liquidity "internal, 0.0-1.0"
        double momentum "internal, -1.0-1.0"
        timestamptz as_of
    }

    HOLDINGS {
        int holding_id PK
        int account_id FK
        int instrument_id FK
        numeric quantity "financial, cache of holding_movements"
        timestamptz updated_at
    }

    ORDERS {
        int order_id PK
        int account_id FK
        int instrument_id FK
        uuid client_reference UK "idempotency key"
        text order_type "BUY/SELL"
        text status "SUBMITTED/ACCEPTED/REJECTED/FILLED/EXECUTION_FAILED"
        numeric quantity
        numeric indicative_price
        numeric buffer_percent
        text rejection_reason
        timestamptz submitted_at
        timestamptz accepted_at
        timestamptz resolved_at
    }

    FILLS {
        int fill_id PK
        int order_id FK_UK "1:1 with orders"
        numeric quote_price
        numeric quantity
        timestamptz filled_at
    }

    CASH_TRANSACTIONS {
        int cash_transaction_id PK
        int account_id FK
        int fill_id FK_UK "null for deposit/withdrawal"
        numeric amount "financial, signed"
        text reason "ORDER_FILL/DEPOSIT/WITHDRAWAL"
        timestamptz created_at
    }

    HOLDING_MOVEMENTS {
        int holding_movement_id PK
        int account_id FK
        int instrument_id FK
        int fill_id FK_UK "1:1 with fills"
        numeric quantity_delta "financial, signed"
        timestamptz created_at
    }

    AUDIT_TRAIL {
        int audit_id PK
        int order_id FK
        text event_type "SUBMITTED/ACCEPTED/REJECTED/FILLED/EXECUTION_FAILED"
        text detail
        timestamptz recorded_at "insert-only, never updated/deleted"
    }
```

## Our Branching Strategy
Our branching strategy is trunking

## External Frameworks 
SpartanNG UI - accessible, customizable components for Angular application.
PrimeNG UI -  comprehensive UI component library specifically designed for Angular applications.
Figma - UI design mockups and prototypes 
Claude Design 
