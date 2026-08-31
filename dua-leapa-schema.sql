-- Dua LEAPa — Trading Platform Schema
-- Source: LEAP-BRS-2026-014 v0.9 ("BR-*" refs below) + KAN-* Jira stories (impl detail).
--
-- Core design decisions:
--   * Orders vs fills are separate (BR-06): an ACCEPTED order can exist with no fill yet.
--   * cash_balance / holdings.quantity are caches; cash_transactions and
--     holding_movements are the append-only ledgers they're derived from (BR-09, BR-15).
--   * audit_trail is insert-only (BR-14/15, 9.4): grant the app role INSERT/SELECT only.
--   * orders.client_reference is an idempotency key stopping duplicate submissions (9.1).
--
-- Market data (BR-08/12/13) mirrors github.com/ChrisChang8/FMS's Pydantic models.
-- FMS currently only implements price_points (Phase 4, US equities only).
-- quotes / market_ticks / candles / market_state are modelled now but stay empty
-- until FMS reaches Phases 5-9; UK/India equities, FX and crypto (BR-12) aren't
-- simulated yet — flag with the Programme Sponsor.
--
-- Open assumptions (confirm with Product Owner before relying on them):
--   * trader_level: BEGINNER / INTERMEDIATE / ADVANCED (KAN-78)
--   * user_role: ADMIN / TRADER (KAN-78, KAN-86)
--   * order lifecycle: SUBMITTED -> ACCEPTED/REJECTED -> FILLED/EXECUTION_FAILED (BR-06/07)
--   * no partial fills: one order produces at most one fill
--   * buffer_percent: per-order execution price tolerance (KAN-100)
--   * one cash_balance/currency per account (no multi-currency wallets)
--   * ssn is TEXT here for lab purposes only — must be encrypted/tokenised in production
--   * BR-16/17 reporting: assumed to be a separate downstream store, not modelled here

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

-- Purpose (granular): login credentials, profile, and account-level settings for one trader/admin.
-- Purpose (overarching): the root identity every account, order, and audit record belongs to.
-- Refs: KAN-78 registration, KAN-82 hashing, KAN-84 rate limiting, KAN-85/88
--       session timeout, KAN-86/92 active/deactivated state, KAN-89 reset, KAN-100 buffer.
CREATE TABLE users (
    user_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username                  TEXT NOT NULL UNIQUE,
    password_hash             TEXT NOT NULL,                               -- hashed, never plaintext
    email                     TEXT NOT NULL UNIQUE,
    ssn                       TEXT NOT NULL,                                -- PII: encrypt/tokenise in real deployment
    date_of_birth             DATE NOT NULL,
    trader_level              TEXT NOT NULL DEFAULT 'BEGINNER'
                                  CHECK (trader_level IN ('BEGINNER', 'INTERMEDIATE', 'ADVANCED')),
    available_funds           NUMERIC(14,2) NOT NULL DEFAULT 0
                                  CHECK (available_funds >= 0),
    user_role                 TEXT NOT NULL DEFAULT 'TRADER'
                                  CHECK (user_role IN ('ADMIN', 'TRADER')),
    account_status            TEXT NOT NULL DEFAULT 'ACTIVE'
                                  CHECK (account_status IN ('ACTIVE', 'DEACTIVATED')),
    session_timeout_minutes   INTEGER NOT NULL DEFAULT 10,                  -- inactivity timeout (KAN-85/88)
    execution_buffer_percent  NUMERIC(5,2) NOT NULL DEFAULT 0
                                  CHECK (execution_buffer_percent >= 0),     -- price tolerance (KAN-100)
    failed_login_attempts     INTEGER NOT NULL DEFAULT 0,                   -- rate limiting (KAN-84)
    locked_until              TIMESTAMPTZ,                                  -- lockout expiry (KAN-84)
    reset_token               TEXT,                                         -- password reset (KAN-89)
    reset_token_expires_at    TIMESTAMPTZ,
    last_login_at             TIMESTAMPTZ,
    last_activity_at          TIMESTAMPTZ,                                  -- dormant-account check (KAN-92)
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Purpose (granular): one signed-in session with its own expiry and revocation state.
-- Purpose (overarching): lets a single compromised session be killed on demand (BR-03) without affecting the user's other sessions.
CREATE TABLE sessions (
    session_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(user_id),
    issued_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL,
    revoked_at    TIMESTAMPTZ,                                   -- manual revoke, before natural expiry
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Purpose (granular): one tradable asset — equity, FX pair, or crypto.
-- Purpose (overarching): shared reference table every quote, order, holding, and fill hangs off.
CREATE TABLE instruments (
    instrument_id  SERIAL PRIMARY KEY,
    ticker         TEXT NOT NULL UNIQUE,
    name           TEXT NOT NULL,
    asset_class    TEXT NOT NULL CHECK (asset_class IN ('Equity', 'FX', 'Crypto')),
    market         TEXT CHECK (market IN ('UK', 'US', 'IN')),                        -- equities only; NULL for FX/crypto
    currency       TEXT NOT NULL,
    is_tradable    BOOLEAN NOT NULL DEFAULT TRUE,                                    -- BR-05 tradability check
    CHECK (asset_class <> 'Equity' OR ticker ~ '^[A-Z][A-Z0-9.]{0,4}$'),
    CHECK ((asset_class = 'Equity') = (market IS NOT NULL))
);

-- Purpose (granular): name, sector, and simulation params for instruments FMS simulates.
-- Purpose (overarching): feeds the price simulator; matches app.models.Stock field-for-field (KAN-91, KAN-98).
CREATE TABLE stocks (
    instrument_id     INTEGER PRIMARY KEY REFERENCES instruments(instrument_id),
    company_name      TEXT NOT NULL CHECK (char_length(company_name) BETWEEN 1 AND 120),
    starting_price    NUMERIC(18,6) NOT NULL CHECK (starting_price > 0),          -- FMS: Money
    sector            TEXT NOT NULL CHECK (char_length(sector) BETWEEN 1 AND 80),
    average_volume    BIGINT NOT NULL CHECK (average_volume > 0),                 -- FMS: PositiveInt
    base_volatility   NUMERIC(18,6) NOT NULL CHECK (base_volatility >= 0)         -- FMS: NonNegativeMoney
);

-- Purpose (granular): one brokerage/child account, holding a single cash balance in one currency.
-- Purpose (overarching): the unit orders and holdings attach to; a user can own many (KAN-78, KAN-103/104).
-- Notes: cash_balance is a cache (BR-10); reconcile against cash_transactions below (BR-15).
CREATE TABLE accounts (
    account_id    SERIAL PRIMARY KEY,
    user_id       UUID NOT NULL REFERENCES users(user_id),                           -- one owner, never shared
    cash_balance  NUMERIC(14,2) NOT NULL DEFAULT 0
                      CHECK (cash_balance >= 0),
    opened_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    currency      TEXT NOT NULL DEFAULT 'USD'
);

-- Purpose (granular): one simulated price tick — instrument, price, sequence number.
-- Purpose (overarching): the only market-data table FMS actually produces today (Phase 4); everything downstream reads this.
CREATE TABLE price_points (
    price_point_id   SERIAL PRIMARY KEY,
    instrument_id    INTEGER NOT NULL REFERENCES instruments(instrument_id),
    price            NUMERIC(18,6) NOT NULL CHECK (price > 0),
    sequence_number  BIGINT NOT NULL CHECK (sequence_number > 0),            -- per-instrument, monotonic
    observed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (instrument_id, sequence_number)
);

-- Purpose (granular): one raw tick with bid/ask/volume.
-- Purpose (overarching): storage shape reserved now (matches app.models.MarketTick) so ingestion needs no migration once FMS Phase 8 lands.
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
    CHECK (bid < ask AND price BETWEEN bid AND ask),
    UNIQUE (instrument_id, sequence_number)
);

-- Purpose (granular): one bid/ask snapshot for an instrument.
-- Purpose (overarching): reserved for FMS Phase 7 (app.models.Quote); stays empty until then.
CREATE TABLE quotes (
    quote_id       SERIAL PRIMARY KEY,
    instrument_id  INTEGER NOT NULL REFERENCES instruments(instrument_id),
    bid            NUMERIC(18,6) NOT NULL CHECK (bid > 0),
    ask            NUMERIC(18,6) NOT NULL CHECK (ask > bid),                -- FMS: validate_quote_prices
    bid_size       INTEGER NOT NULL CHECK (bid_size > 0),
    ask_size       INTEGER NOT NULL CHECK (ask_size > 0),
    observed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Purpose (granular): one OHLCV bar per instrument/interval/period.
-- Purpose (overarching): reserved for FMS Phase 9 (app.models.Candle); feeds future charting/reporting.
CREATE TABLE candles (
    candle_id      SERIAL PRIMARY KEY,
    instrument_id  INTEGER NOT NULL REFERENCES instruments(instrument_id),
    interval       TEXT NOT NULL CHECK (interval ~ '^[1-9][0-9]*(s|m|h|d)$'), -- e.g. '1m', '5m', '1h', '1d'
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

-- Purpose (granular): trend/volatility/liquidity/momentum inputs the simulator uses per instrument.
-- Purpose (overarching): reserved for FMS Phase 5 (app.models.MarketState); drives future price generation, not consumer-facing.
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

-- Purpose (granular): one account/instrument pair holding a current quantity.
-- Purpose (overarching): portfolio-position cache KAN-103/104 display; source of truth is holding_movements below (BR-15).
CREATE TABLE holdings (
    holding_id     SERIAL PRIMARY KEY,
    account_id     INTEGER NOT NULL REFERENCES accounts(account_id),
    instrument_id  INTEGER NOT NULL REFERENCES instruments(instrument_id),
    quantity       NUMERIC(14,4) NOT NULL DEFAULT 0,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, instrument_id)
);

-- Purpose (granular): one client instruction to buy/sell, tracked through its own status lifecycle.
-- Purpose (overarching): the client's firm commitment (BR-04/05/06), deliberately separate from execution (fills below).
-- Notes: client_reference is a client-supplied idempotency key stopping duplicate submissions on retry (section 9.1).
CREATE TABLE orders (
    order_id          SERIAL PRIMARY KEY,
    account_id        INTEGER NOT NULL REFERENCES accounts(account_id),
    instrument_id     INTEGER NOT NULL REFERENCES instruments(instrument_id),
    client_reference  UUID NOT NULL,                                              -- idempotency key, see notes above
    order_type        TEXT NOT NULL CHECK (order_type IN ('BUY', 'SELL')),
    status            TEXT NOT NULL DEFAULT 'SUBMITTED'
                          CHECK (status IN ('SUBMITTED', 'ACCEPTED', 'REJECTED', 'FILLED', 'EXECUTION_FAILED')),
    quantity          NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    indicative_price  NUMERIC(18,6),                                              -- BR-13: price shown before submission
    buffer_percent    NUMERIC(5,2),                                               -- KAN-100: execution price tolerance
    rejection_reason  TEXT,                                                       -- set only for REJECTED/EXECUTION_FAILED
    submitted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at       TIMESTAMPTZ,                                                -- BR-05 trading-rule check passed
    resolved_at       TIMESTAMPTZ,                                                -- time of FILLED/REJECTED/EXECUTION_FAILED
    UNIQUE (account_id, client_reference)
);

-- Purpose (granular): one executed order — the price and quantity it actually filled at.
-- Purpose (overarching): the execution outcome of an ACCEPTED order (BR-06/08); no partial fills, so 1:1 with orders.
CREATE TABLE fills (
    fill_id      SERIAL PRIMARY KEY,
    order_id     INTEGER NOT NULL UNIQUE REFERENCES orders(order_id),
    quote_price  NUMERIC(18,6) NOT NULL CHECK (quote_price > 0),                  -- BR-08: quote used at execution time
    quantity     NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    filled_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Purpose (granular): one append-only cash movement — a fill, a deposit, or a withdrawal.
-- Purpose (overarching): the ledger accounts.cash_balance is cached from and reconciled against (BR-09/14/15).
CREATE TABLE cash_transactions (
    cash_transaction_id  SERIAL PRIMARY KEY,
    account_id           INTEGER NOT NULL REFERENCES accounts(account_id),
    fill_id              INTEGER UNIQUE REFERENCES fills(fill_id),                  -- NULL for deposit/withdrawal
    amount                NUMERIC(14,2) NOT NULL,                                 -- signed: + credit, - debit
    reason                TEXT NOT NULL CHECK (reason IN ('ORDER_FILL', 'DEPOSIT', 'WITHDRAWAL')),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((reason = 'ORDER_FILL') = (fill_id IS NOT NULL))
);

-- Purpose (granular): one append-only position change caused by a fill.
-- Purpose (overarching): the ledger holdings.quantity is cached from and reconciled against (BR-09/14/15); paired 1:1 with a fill.
CREATE TABLE holding_movements (
    holding_movement_id  SERIAL PRIMARY KEY,
    account_id           INTEGER NOT NULL REFERENCES accounts(account_id),
    instrument_id        INTEGER NOT NULL REFERENCES instruments(instrument_id),
    fill_id              INTEGER NOT NULL UNIQUE REFERENCES fills(fill_id),
    quantity_delta       NUMERIC(14,4) NOT NULL CHECK (quantity_delta <> 0),      -- signed: + for BUY, - for SELL
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Purpose (granular): one row per order-lifecycle event (submitted/accepted/rejected/filled/failed).
-- Purpose (overarching): the permanent, unalterable trade record (BR-14/15, 9.4) — grant app role INSERT/SELECT only, never UPDATE/DELETE.
CREATE TABLE audit_trail (
    audit_id      SERIAL PRIMARY KEY,
    order_id      INTEGER NOT NULL REFERENCES orders(order_id),
    event_type    TEXT NOT NULL CHECK (event_type IN ('SUBMITTED', 'ACCEPTED', 'REJECTED', 'FILLED', 'EXECUTION_FAILED')),
    detail        TEXT,
    recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
