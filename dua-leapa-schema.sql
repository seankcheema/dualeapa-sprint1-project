-- Dua LEAPa — Trading Platform Schema
-- Baseline structure/style borrowed from shared/enterprise-schema.sql.
-- Business rules below are driven by LEAP-BRS-2026-014 "Business Requirements
-- Specification — Direct Trading Platform" (v0.9), each table/column comment
-- references the BR-* or section that requires it. The KAN-* Jira stories
-- add implementation-level detail the BRS leaves to the delivery partner
-- (section 7: "How that outcome is achieved... is for the delivery partner
-- to propose"), those are kept where they don't conflict with the BRS.
--
-- Key BRS decisions this schema encodes:
--   * BR-06: an order (the client's commitment) and its execution are
--     separate, order status can be ACCEPTED with no fill yet.
--   * BR-09: a fill, its cash movement and its holdings movement must all
--     exist together, not-null and updated in one transaction. holdings and
--     accounts.cash_balance are a current-state cache; fills/cash_transactions/
--     holding_movements are the append-only ledger that cache is derived from.
--   * BR-14/BR-15/9.4: trade records must be permanent and unalterable.
--     audit_trail is insert-only by design, grant the application role
--     INSERT/SELECT only on it, never UPDATE/DELETE.
--   * Section 9.1 ("no trade record may be lost or duplicated"): orders carry
--     a client-supplied idempotency key so a retried submission can't create
--     a second order.
--
-- Market data shape (BR-08, BR-12, BR-13) is aligned to github.com/ChrisChang8/FMS
-- (read directly, not just AGENTS.md's summary): a FastAPI market-data
-- simulator whose Pydantic models (app/models/market_data.py) define Stock,
-- Quote, MarketTick, Candle, and MarketState. As of the commit read here,
-- FMS has only implemented through Phase 4 (PriceSimulationEngine, which
-- generates PricePoint: symbol/timestamp/price/sequence_number only).
-- Quote, MarketTick, Candle, and MarketState are defined but not yet
-- produced end-to-end (bid/ask, volume, and OHLCV land in FMS's Phases
-- 6-9), so those tables will stay empty until FMS catches up, columns are
-- still specified now so the storage shape doesn't need revisiting later.
-- FMS also only simulates U.S. stocks (DEFAULT_SIMULATED_STOCKS), so it
-- does not yet cover BR-12's UK/Indian equities, FX or crypto, flag this
-- gap with the Programme Sponsor rather than assuming FMS will grow to fit.
--
-- Assumptions made where a story/BR didn't fully specify a value (flag these
-- with the Product Owner before relying on them):
--   * trader_level is one of BEGINNER / INTERMEDIATE / ADVANCED (KAN-78)
--   * user_role is one of ADMIN / TRADER (KAN-78, KAN-86)
--   * order lifecycle is SUBMITTED -> ACCEPTED/REJECTED -> FILLED/EXECUTION_FAILED (BR-06, BR-07)
--   * no partial fills: one order produces at most one fill (BRS doesn't mention partial fills)
--   * execution buffer is a per-order percentage tolerance used at the BR-08 pricing step (KAN-100)
--   * one cash_balance/currency per account, real multi-market/FX trading likely needs
--     per-currency cash wallets, the BRS doesn't ask for this explicitly so it's out of scope for now
--   * ssn is stored as text here; in a real deployment this must be encrypted
--     at rest / tokenised, not stored in plain text (KAN-78)
--   * BR-16/BR-17 reporting likely wants a separate analytical store fed from
--     this one, so it doesn't compete with live trading capacity, no new
--     tables are added here for that, it's an architecture decision, not a
--     schema one

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP TABLE IF EXISTS audit_trail;
DROP TABLE IF EXISTS holding_movements;
DROP TABLE IF EXISTS cash_transactions;
DROP TABLE IF EXISTS fills;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS holdings;
DROP TABLE IF EXISTS market_state;
DROP TABLE IF EXISTS candles;
DROP TABLE IF EXISTS quotes;
DROP TABLE IF EXISTS market_ticks;
DROP TABLE IF EXISTS price_points;
DROP TABLE IF EXISTS stocks;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS instruments;
DROP TABLE IF EXISTS users;

-- Users: registration + auth + session/rate-limit state.
-- Columns: KAN-78 (registration schema), KAN-82 (password hashing),
-- KAN-84 (rate limiting), KAN-85/88 (session timeout), KAN-86/92
-- (active/deactivated state), KAN-89 (password reset), KAN-100 (execution buffer).
CREATE TABLE users (
    user_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),   -- KAN-78: UUID
    username                  TEXT NOT NULL UNIQUE,                        -- KAN-78
    password_hash             TEXT NOT NULL,                               -- KAN-78, KAN-82
    email                     TEXT NOT NULL UNIQUE,                           -- KAN-78
    ssn                       TEXT NOT NULL,                                -- KAN-78
    date_of_birth             DATE NOT NULL,                                -- KAN-78
    trader_level              TEXT NOT NULL DEFAULT 'BEGINNER'
                                  CHECK (trader_level IN ('BEGINNER', 'INTERMEDIATE', 'ADVANCED')), -- KAN-78
    available_funds           NUMERIC(14,2) NOT NULL DEFAULT 0
                                  CHECK (available_funds >= 0),             -- KAN-78, KAN-93
    user_role                 TEXT NOT NULL DEFAULT 'TRADER'
                                  CHECK (user_role IN ('ADMIN', 'TRADER')),  -- KAN-78
    account_status            TEXT NOT NULL DEFAULT 'ACTIVE'
                                  CHECK (account_status IN ('ACTIVE', 'DEACTIVATED')), -- KAN-86, KAN-92
    session_timeout_minutes   INTEGER NOT NULL DEFAULT 10,                  -- KAN-85, KAN-88
    execution_buffer_percent  NUMERIC(5,2) NOT NULL DEFAULT 0
                                  CHECK (execution_buffer_percent >= 0),     -- KAN-100
    failed_login_attempts     INTEGER NOT NULL DEFAULT 0,                   -- KAN-84
    locked_until              TIMESTAMPTZ,                                  -- KAN-84
    reset_token               TEXT,                                         -- KAN-89
    reset_token_expires_at    TIMESTAMPTZ,                                  -- KAN-89
    last_login_at             TIMESTAMPTZ,                                  -- KAN-92
    last_activity_at          TIMESTAMPTZ,                                  -- KAN-85, KAN-92
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now()            -- KAN-78: "Date Created"
);

-- Sessions: a signed-in session, time-limited and independently revocable (BR-03).
-- Distinct from users.session_timeout_minutes/last_activity_at, which drive
-- KAN-85's 10-minute inactivity timeout and KAN-92's 3-month dormant-account
-- check, this table is what lets a specific session be killed on demand
-- (compromised credential) without waiting for expires_at.
CREATE TABLE sessions (
    session_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(user_id),
    issued_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL,
    revoked_at    TIMESTAMPTZ,                                   -- BR-03: revoked before natural expiry
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Instruments: an equity, FX pair, or crypto asset (BR-12, glossary section 13).
-- market applies to equities only (BR-12: UK/US/Indian markets); FX pairs and
-- crypto assets are identified by ticker alone (e.g. "GBPUSD", "BTC-USD").
-- is_tradable backs the BR-05 "instrument currently tradable" trading-rule check.
CREATE TABLE instruments (
    instrument_id  SERIAL PRIMARY KEY,
    ticker         TEXT NOT NULL UNIQUE,
    name           TEXT NOT NULL,
    asset_class    TEXT NOT NULL CHECK (asset_class IN ('Equity', 'FX', 'Crypto')),
    market         TEXT CHECK (market IN ('UK', 'US', 'IN')),
    currency       TEXT NOT NULL,
    is_tradable    BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (asset_class <> 'Equity' OR ticker ~ '^[A-Z][A-Z0-9.]{0,4}$'),
    CHECK ((asset_class = 'Equity') = (market IS NOT NULL))
);

-- Stocks: FMS Stock reference data for instruments FMS simulates (KAN-91, KAN-98).
-- Field-for-field match of app.models.Stock.
CREATE TABLE stocks (
    instrument_id     INTEGER PRIMARY KEY REFERENCES instruments(instrument_id),
    company_name      TEXT NOT NULL CHECK (char_length(company_name) BETWEEN 1 AND 120),
    starting_price    NUMERIC(18,6) NOT NULL CHECK (starting_price > 0),          -- FMS: Money
    sector            TEXT NOT NULL CHECK (char_length(sector) BETWEEN 1 AND 80),
    average_volume    BIGINT NOT NULL CHECK (average_volume > 0),                 -- FMS: PositiveInt
    base_volatility   NUMERIC(18,6) NOT NULL CHECK (base_volatility >= 0)         -- FMS: NonNegativeMoney
);

-- Accounts: KAN-78's "child accounts" — one user owns many accounts, each
-- account belongs to exactly one user (user_id NOT NULL, never shared) and
-- has exactly one cash holding (a single cash_balance column, not a
-- multi-currency wallet). KAN-103/KAN-104 read/display these per user.
-- cash_balance is a current-state cache (BR-10: "correct as of their last
-- executed trade"), the source of truth is the cash_transactions ledger below,
-- reconcilable at any time by summing it (BR-15).
CREATE TABLE accounts (
    account_id    SERIAL PRIMARY KEY,
    user_id       UUID NOT NULL REFERENCES users(user_id),
    cash_balance  NUMERIC(14,2) NOT NULL DEFAULT 0
                      CHECK (cash_balance >= 0),                            -- KAN-93, KAN-103, BR-10
    opened_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    currency      TEXT NOT NULL DEFAULT 'USD'
);

-- Price points: what FMS's PriceSimulationEngine actually generates today
-- (Phase 4, implemented). Field-for-field match of app.simulation.PricePoint.
CREATE TABLE price_points (
    price_point_id   SERIAL PRIMARY KEY,
    instrument_id    INTEGER NOT NULL REFERENCES instruments(instrument_id),
    price            NUMERIC(18,6) NOT NULL CHECK (price > 0),               -- FMS: Money, 6dp
    sequence_number  BIGINT NOT NULL CHECK (sequence_number > 0),            -- FMS: per-symbol sequence
    observed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (instrument_id, sequence_number)
);

-- Market ticks: raw market updates (KAN-91, KAN-98). Field-for-field match of
-- app.models.MarketTick. Not yet produced by FMS (needs its Phase 8), the
-- shape is fixed now so ingestion doesn't require a migration later.
CREATE TABLE market_ticks (
    tick_id          SERIAL PRIMARY KEY,
    instrument_id    INTEGER NOT NULL REFERENCES instruments(instrument_id),
    price            NUMERIC(18,6) NOT NULL CHECK (price > 0),
    bid              NUMERIC(18,6) NOT NULL CHECK (bid > 0),
    ask              NUMERIC(18,6) NOT NULL CHECK (ask > 0),
    bid_size         INTEGER NOT NULL CHECK (bid_size > 0),
    ask_size         INTEGER NOT NULL CHECK (ask_size > 0),
    trade_volume     INTEGER NOT NULL CHECK (trade_volume > 0),
    sequence_number  BIGINT NOT NULL CHECK (sequence_number > 0),
    observed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (bid < ask AND price BETWEEN bid AND ask),                        -- FMS: validate_tick_prices
    UNIQUE (instrument_id, sequence_number)
);

-- Quotes: bid/ask snapshots (KAN-91, KAN-98). Field-for-field match of
-- app.models.Quote. Not yet produced by FMS (needs its Phase 7).
CREATE TABLE quotes (
    quote_id       SERIAL PRIMARY KEY,
    instrument_id  INTEGER NOT NULL REFERENCES instruments(instrument_id),
    bid            NUMERIC(18,6) NOT NULL CHECK (bid > 0),
    ask            NUMERIC(18,6) NOT NULL CHECK (ask > bid),                -- FMS: validate_quote_prices
    bid_size       INTEGER NOT NULL CHECK (bid_size > 0),
    ask_size       INTEGER NOT NULL CHECK (ask_size > 0),
    observed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Candles: OHLCV bars (KAN-91, KAN-98). Field-for-field match of
-- app.models.Candle. Not yet produced by FMS (needs its Phase 9).
CREATE TABLE candles (
    candle_id      SERIAL PRIMARY KEY,
    instrument_id  INTEGER NOT NULL REFERENCES instruments(instrument_id),
    interval       TEXT NOT NULL CHECK (interval ~ '^[1-9][0-9]*(s|m|h|d)$'), -- e.g. '1s','1m','5m','1h','1d'
    period_start   TIMESTAMPTZ NOT NULL,
    open           NUMERIC(18,6) NOT NULL,
    high           NUMERIC(18,6) NOT NULL,
    low            NUMERIC(18,6) NOT NULL,
    close          NUMERIC(18,6) NOT NULL,
    volume         INTEGER NOT NULL CHECK (volume > 0),
    trade_count    INTEGER NOT NULL CHECK (trade_count > 0),
    CHECK (high >= GREATEST(open, close, low) AND low <= LEAST(open, close, high)), -- FMS: validate_ohlc_prices
    UNIQUE (instrument_id, interval, period_start)
);

-- Market state: simulator behavior inputs driving price movement (KAN-91, KAN-98).
-- Field-for-field match of app.models.MarketState/MarketTrend.
-- Not yet produced by FMS (needs its Phase 5).
CREATE TABLE market_state (
    market_state_id  SERIAL PRIMARY KEY,
    instrument_id    INTEGER NOT NULL REFERENCES instruments(instrument_id),
    trend            TEXT NOT NULL DEFAULT 'normal'
                         CHECK (trend IN ('normal', 'uptrend', 'downtrend', 'sideways')),
    volatility       NUMERIC(18,6) NOT NULL CHECK (volatility >= 0),          -- FMS: NonNegativeMoney
    liquidity        DOUBLE PRECISION NOT NULL CHECK (liquidity BETWEEN 0.0 AND 1.0),   -- FMS: Ratio
    momentum         DOUBLE PRECISION NOT NULL CHECK (momentum BETWEEN -1.0 AND 1.0),   -- FMS: SignedRatio
    as_of            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Holdings: current portfolio position per account/instrument (KAN-90, KAN-103, KAN-104).
-- Current-state cache like accounts.cash_balance (BR-10), the source of truth
-- is the holding_movements ledger below, reconcilable by summing it (BR-15).
CREATE TABLE holdings (
    holding_id     SERIAL PRIMARY KEY,
    account_id     INTEGER NOT NULL REFERENCES accounts(account_id),
    instrument_id  INTEGER NOT NULL REFERENCES instruments(instrument_id),
    quantity       NUMERIC(14,4) NOT NULL DEFAULT 0,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, instrument_id)
);

-- Orders: the client's instruction, a firm commitment once ACCEPTED (BR-04,
-- BR-05, BR-06). Execution is deliberately a separate step/table (fills
-- below): an order can be ACCEPTED with no fill yet, and that record of
-- intent must not depend on execution succeeding (BR-06).
-- client_reference is a client-generated idempotency key so a retried
-- submission (network retry, double-click) can't create a duplicate order
-- (section 9.1: "no trade record may be lost or duplicated").
CREATE TABLE orders (
    order_id          SERIAL PRIMARY KEY,
    account_id        INTEGER NOT NULL REFERENCES accounts(account_id),
    instrument_id     INTEGER NOT NULL REFERENCES instruments(instrument_id),
    client_reference  UUID NOT NULL,
    order_type        TEXT NOT NULL CHECK (order_type IN ('BUY', 'SELL')),         -- BR-04
    status            TEXT NOT NULL DEFAULT 'SUBMITTED'
                          CHECK (status IN ('SUBMITTED', 'ACCEPTED', 'REJECTED', 'FILLED', 'EXECUTION_FAILED')), -- BR-06, BR-07
    quantity          NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    indicative_price  NUMERIC(18,6),                                              -- BR-13: shown before submission
    buffer_percent    NUMERIC(5,2),                                               -- execution price tolerance (KAN-100), used at the BR-08 pricing step
    rejection_reason  TEXT,                                                       -- set for REJECTED or EXECUTION_FAILED (BR-15)
    submitted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at       TIMESTAMPTZ,                                                -- BR-05 trading-rule check passed
    resolved_at       TIMESTAMPTZ,                                                -- FILLED / REJECTED / EXECUTION_FAILED time
    UNIQUE (account_id, client_reference)
);

-- Fills: the outcome of executing an ACCEPTED order (BR-06, BR-08). One row
-- per order, no partial fills modelled (see header assumptions).
CREATE TABLE fills (
    fill_id      SERIAL PRIMARY KEY,
    order_id     INTEGER NOT NULL UNIQUE REFERENCES orders(order_id),
    quote_price  NUMERIC(18,6) NOT NULL CHECK (quote_price > 0),                  -- BR-08: quote used at execution
    quantity     NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    filled_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Cash transactions: append-only cash ledger (BR-09, BR-14). Every fill
-- produces exactly one row here; deposits/withdrawals produce others with a
-- null fill_id. accounts.cash_balance is the cache this reconciles against.
CREATE TABLE cash_transactions (
    cash_transaction_id  SERIAL PRIMARY KEY,
    account_id           INTEGER NOT NULL REFERENCES accounts(account_id),
    fill_id              INTEGER UNIQUE REFERENCES fills(fill_id),
    amount                NUMERIC(14,2) NOT NULL,                                 -- signed: + credit, - debit
    reason                TEXT NOT NULL CHECK (reason IN ('ORDER_FILL', 'DEPOSIT', 'WITHDRAWAL')),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((reason = 'ORDER_FILL') = (fill_id IS NOT NULL))
);

-- Holding movements: append-only position ledger (BR-09, BR-14), the other
-- half of what a fill must update atomically alongside cash_transactions.
-- holdings.quantity is the cache this reconciles against.
CREATE TABLE holding_movements (
    holding_movement_id  SERIAL PRIMARY KEY,
    account_id           INTEGER NOT NULL REFERENCES accounts(account_id),
    instrument_id        INTEGER NOT NULL REFERENCES instruments(instrument_id),
    fill_id              INTEGER NOT NULL UNIQUE REFERENCES fills(fill_id),
    quantity_delta       NUMERIC(14,4) NOT NULL CHECK (quantity_delta <> 0),      -- signed: + for BUY, - for SELL
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Audit trail: permanent, unalterable record of every order-lifecycle event
-- (BR-14, BR-15, section 9.4 and glossary's "Audit trail"). Insert-only by
-- design, grant the application's normal role INSERT/SELECT only on this
-- table, never UPDATE/DELETE, so a trade record can't be altered after the fact.
CREATE TABLE audit_trail (
    audit_id      SERIAL PRIMARY KEY,
    order_id      INTEGER NOT NULL REFERENCES orders(order_id),
    event_type    TEXT NOT NULL CHECK (event_type IN ('SUBMITTED', 'ACCEPTED', 'REJECTED', 'FILLED', 'EXECUTION_FAILED')),
    detail        TEXT,
    recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
