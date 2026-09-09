-- V001__Initial_Schema.sql
-- Trading Season Platform - Initial Database Schema

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- USERS table
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    ssn TEXT,
    date_of_birth DATE,
    trader_level TEXT NOT NULL DEFAULT 'BEGINNER' CHECK (trader_level IN ('BEGINNER', 'INTERMEDIATE', 'ADVANCED')),
    available_funds NUMERIC(19,2),
    user_role TEXT NOT NULL DEFAULT 'TRADER' CHECK (user_role IN ('ADMIN', 'TRADER')),
    account_status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (account_status IN ('ACTIVE', 'DEACTIVATED')),
    session_timeout_minutes INTEGER DEFAULT 30,
    execution_buffer_percent NUMERIC(5,2),
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    reset_token TEXT,
    reset_token_expires_at TIMESTAMP WITH TIME ZONE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    last_activity_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- SESSIONS table
CREATE TABLE sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    issued_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- INSTRUMENTS table
CREATE TABLE instruments (
    instrument_id SERIAL PRIMARY KEY,
    ticker TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    asset_class TEXT NOT NULL CHECK (asset_class IN ('Equity', 'FX', 'Crypto')),
    market TEXT CHECK (market IN ('UK', 'US', 'IN')),
    currency TEXT NOT NULL,
    is_tradable BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- STOCKS table
CREATE TABLE stocks (
    instrument_id INTEGER PRIMARY KEY REFERENCES instruments(instrument_id) ON DELETE CASCADE,
    company_name TEXT NOT NULL,
    starting_price NUMERIC(19,4) NOT NULL,
    sector TEXT,
    average_volume BIGINT,
    base_volatility NUMERIC(5,4)
);

-- ACCOUNTS table
CREATE TABLE accounts (
    account_id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    cash_balance NUMERIC(19,2) NOT NULL DEFAULT 0.00,
    opened_date DATE DEFAULT CURRENT_DATE,
    currency TEXT DEFAULT 'USD',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- PRICE_POINTS table
CREATE TABLE price_points (
    price_point_id SERIAL PRIMARY KEY,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id) ON DELETE CASCADE,
    price NUMERIC(19,4) NOT NULL,
    sequence_number BIGINT NOT NULL,
    observed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    UNIQUE(instrument_id, sequence_number)
);

-- MARKET_TICKS table
CREATE TABLE market_ticks (
    tick_id SERIAL PRIMARY KEY,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id) ON DELETE CASCADE,
    price NUMERIC(19,4) NOT NULL,
    bid NUMERIC(19,4),
    ask NUMERIC(19,4),
    bid_size INTEGER,
    ask_size INTEGER,
    trade_volume INTEGER,
    sequence_number BIGINT NOT NULL,
    observed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    UNIQUE(instrument_id, sequence_number)
);

-- QUOTES table
CREATE TABLE quotes (
    quote_id SERIAL PRIMARY KEY,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id) ON DELETE CASCADE,
    bid NUMERIC(19,4) NOT NULL,
    ask NUMERIC(19,4) NOT NULL,
    bid_size INTEGER,
    ask_size INTEGER,
    observed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- CANDLES table
CREATE TABLE candles (
    candle_id SERIAL PRIMARY KEY,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id) ON DELETE CASCADE,
    interval TEXT NOT NULL CHECK (interval IN ('1m', '5m', '15m', '1h', '4h', '1d')),
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    open NUMERIC(19,4) NOT NULL,
    high NUMERIC(19,4) NOT NULL,
    low NUMERIC(19,4) NOT NULL,
    close NUMERIC(19,4) NOT NULL,
    volume INTEGER,
    trade_count INTEGER,
    UNIQUE(instrument_id, interval, period_start)
);

-- MARKET_STATE table
CREATE TABLE market_state (
    market_state_id SERIAL PRIMARY KEY,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id) ON DELETE CASCADE,
    trend TEXT NOT NULL DEFAULT 'normal' CHECK (trend IN ('normal', 'uptrend', 'downtrend', 'sideways')),
    volatility NUMERIC(5,4),
    liquidity NUMERIC(3,2) CHECK (liquidity >= 0.0 AND liquidity <= 1.0),
    momentum NUMERIC(4,2) CHECK (momentum >= -1.0 AND momentum <= 1.0),
    as_of TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- HOLDINGS table
CREATE TABLE holdings (
    holding_id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id) ON DELETE RESTRICT,
    quantity NUMERIC(19,4) NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ORDERS table
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id) ON DELETE RESTRICT,
    client_reference UUID UNIQUE NOT NULL,
    order_type TEXT NOT NULL CHECK (order_type IN ('BUY', 'SELL')),
    status TEXT NOT NULL DEFAULT 'SUBMITTED' CHECK (status IN ('SUBMITTED', 'ACCEPTED', 'REJECTED', 'FILLED', 'EXECUTION_FAILED')),
    quantity NUMERIC(19,4) NOT NULL,
    indicative_price NUMERIC(19,4),
    buffer_percent NUMERIC(5,2),
    rejection_reason TEXT,
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    accepted_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE
);

-- FILLS table
CREATE TABLE fills (
    fill_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL UNIQUE REFERENCES orders(order_id) ON DELETE CASCADE,
    quote_price NUMERIC(19,4) NOT NULL,
    quantity NUMERIC(19,4) NOT NULL,
    filled_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- CASH_TRANSACTIONS table
CREATE TABLE cash_transactions (
    cash_transaction_id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    fill_id INTEGER UNIQUE REFERENCES fills(fill_id) ON DELETE SET NULL,
    amount NUMERIC(19,2) NOT NULL,
    reason TEXT NOT NULL CHECK (reason IN ('ORDER_FILL', 'DEPOSIT', 'WITHDRAWAL')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- HOLDING_MOVEMENTS table
CREATE TABLE holding_movements (
    holding_movement_id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id) ON DELETE RESTRICT,
    fill_id INTEGER NOT NULL UNIQUE REFERENCES fills(fill_id) ON DELETE CASCADE,
    quantity_delta NUMERIC(19,4) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- AUDIT_TRAIL table
CREATE TABLE audit_trail (
    audit_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('SUBMITTED', 'ACCEPTED', 'REJECTED', 'FILLED', 'EXECUTION_FAILED')),
    detail TEXT,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);
CREATE INDEX idx_accounts_user_id ON accounts(user_id);
CREATE INDEX idx_holdings_account_id ON holdings(account_id);
CREATE INDEX idx_holdings_instrument_id ON holdings(instrument_id);
CREATE INDEX idx_orders_account_id ON orders(account_id);
CREATE INDEX idx_orders_instrument_id ON orders(instrument_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_cash_transactions_account_id ON cash_transactions(account_id);
CREATE INDEX idx_holding_movements_account_id ON holding_movements(account_id);
CREATE INDEX idx_audit_trail_order_id ON audit_trail(order_id);
CREATE INDEX idx_price_points_instrument_id ON price_points(instrument_id);
CREATE INDEX idx_market_ticks_instrument_id ON market_ticks(instrument_id);
CREATE INDEX idx_quotes_instrument_id ON quotes(instrument_id);
CREATE INDEX idx_candles_instrument_id_interval ON candles(instrument_id, interval);
