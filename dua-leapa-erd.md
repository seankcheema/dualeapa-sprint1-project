# Dua LEAPa — Database Visualization

Companion diagram for [dua-leapa-schema.sql](./dua-leapa-schema.sql). Shows every
table, its columns, key attributes, and how tables relate.

## Legend — column attributes

| Tag | Meaning |
|---|---|
| `PK` | Primary key |
| `FK` | Foreign key (references another table) |
| `UK` | Unique constraint |
| *(no tag)* | Plain column, not unique/keyed |

| Sensitivity label (in quotes) | Meaning |
|---|---|
| `"PII"` | Personally identifiable — must be encrypted/tokenised, never logged or returned as-is |
| `"secret"` | Credential/token material — never expose via API or logs |
| `"internal"` | System/derived state — not user-facing, but not sensitive |
| `"financial"` | Money or position data — read-access should be scoped to the owning user/admin only |
| *(no label)* | Public-safe — ok to expose to the owning user or in normal API responses |

## Entity-relationship diagram

Column tags/sensitivity labels follow the legend above; enum values and long-form notes live in [dua-leapa-schema.sql](./dua-leapa-schema.sql) comments, not repeated here to keep this compact.

```plantuml
@startuml
hide circle
hide empty members
skinparam linetype ortho
skinparam padding 1
skinparam classFontSize 11
skinparam classAttributeFontSize 10
skinparam shadowing false

entity USERS {
  *user_id : uuid <<PK>>
  --
  username : text <<UK>>
  password_hash : text <<secret>>
  email : text <<UK>>
  ssn : text <<PII>>
  date_of_birth : date <<PII>>
  trader_level : text
  available_funds : numeric <<financial>>
  user_role : text
  account_status : text
  session_timeout_minutes : int
  execution_buffer_percent : numeric
  failed_login_attempts : int <<internal>>
  locked_until : timestamptz <<internal>>
  reset_token : text <<secret>>
  reset_token_expires_at : timestamptz <<internal>>
  last_login_at : timestamptz
  last_activity_at : timestamptz
  created_at : timestamptz
}

entity SESSIONS {
  *session_id : uuid <<PK>>
  --
  user_id : uuid <<FK>>
  issued_at : timestamptz
  expires_at : timestamptz
  revoked_at : timestamptz <<internal>>
  last_seen_at : timestamptz
}

entity INSTRUMENTS {
  *instrument_id : int <<PK>>
  --
  ticker : text <<UK>>
  name : text
  asset_class : text
  market : text
  currency : text
  is_tradable : bool
}

entity STOCKS {
  *instrument_id : int <<PK,FK>>
  --
  company_name : text
  starting_price : numeric
  sector : text
  average_volume : bigint
  base_volatility : numeric
}

entity ACCOUNTS {
  *account_id : int <<PK>>
  --
  user_id : uuid <<FK>>
  cash_balance : numeric <<financial>>
  opened_date : date
  currency : text
}

entity PRICE_POINTS {
  *price_point_id : int <<PK>>
  --
  instrument_id : int <<FK>>
  price : numeric
  sequence_number : bigint <<UK>>
  observed_at : timestamptz
}

entity MARKET_TICKS {
  *tick_id : int <<PK>>
  --
  instrument_id : int <<FK>>
  price : numeric
  bid : numeric
  ask : numeric
  bid_size : int
  ask_size : int
  trade_volume : int
  sequence_number : bigint <<UK>>
  observed_at : timestamptz
}

entity QUOTES {
  *quote_id : int <<PK>>
  --
  instrument_id : int <<FK>>
  bid : numeric
  ask : numeric
  bid_size : int
  ask_size : int
  observed_at : timestamptz
}

entity CANDLES {
  *candle_id : int <<PK>>
  --
  instrument_id : int <<FK>>
  interval : text <<UK>>
  period_start : timestamptz <<UK>>
  open : numeric
  high : numeric
  low : numeric
  close : numeric
  volume : int
  trade_count : int
}

entity MARKET_STATE {
  *market_state_id : int <<PK>>
  --
  instrument_id : int <<FK>>
  trend : text
  volatility : numeric <<internal>>
  liquidity : double <<internal>>
  momentum : double <<internal>>
  as_of : timestamptz
}

entity HOLDINGS {
  *holding_id : int <<PK>>
  --
  account_id : int <<FK>>
  instrument_id : int <<FK>>
  quantity : numeric <<financial>>
  updated_at : timestamptz
}

entity ORDERS {
  *order_id : int <<PK>>
  --
  account_id : int <<FK>>
  instrument_id : int <<FK>>
  client_reference : uuid <<UK>>
  order_type : text
  status : text
  quantity : numeric
  indicative_price : numeric
  buffer_percent : numeric
  rejection_reason : text
  submitted_at : timestamptz
  accepted_at : timestamptz
  resolved_at : timestamptz
}

entity FILLS {
  *fill_id : int <<PK>>
  --
  order_id : int <<FK,UK>>
  quote_price : numeric
  quantity : numeric
  filled_at : timestamptz
}

entity CASH_TRANSACTIONS {
  *cash_transaction_id : int <<PK>>
  --
  account_id : int <<FK>>
  fill_id : int <<FK,UK>>
  amount : numeric <<financial>>
  reason : text
  created_at : timestamptz
}

entity HOLDING_MOVEMENTS {
  *holding_movement_id : int <<PK>>
  --
  account_id : int <<FK>>
  instrument_id : int <<FK>>
  fill_id : int <<FK,UK>>
  quantity_delta : numeric <<financial>>
  created_at : timestamptz
}

entity AUDIT_TRAIL {
  *audit_id : int <<PK>>
  --
  order_id : int <<FK>>
  event_type : text
  detail : text
  recorded_at : timestamptz <<internal>>
}

USERS ||--o{ SESSIONS : has
USERS ||--o{ ACCOUNTS : owns
ACCOUNTS ||--o{ ORDERS : places
ACCOUNTS ||--o{ HOLDINGS : holds
ACCOUNTS ||--o{ CASH_TRANSACTIONS : records
ACCOUNTS ||--o{ HOLDING_MOVEMENTS : records
INSTRUMENTS ||--o| STOCKS : "sim data"
INSTRUMENTS ||--o{ PRICE_POINTS : generates
INSTRUMENTS ||--o{ MARKET_TICKS : generates
INSTRUMENTS ||--o{ QUOTES : generates
INSTRUMENTS ||--o{ CANDLES : generates
INSTRUMENTS ||--o{ MARKET_STATE : has
INSTRUMENTS ||--o{ HOLDINGS : "held as"
INSTRUMENTS ||--o{ ORDERS : "traded in"
INSTRUMENTS ||--o{ HOLDING_MOVEMENTS : moves
ORDERS ||--o| FILLS : "executes as"
ORDERS ||--o{ AUDIT_TRAIL : logs
FILLS ||--o| CASH_TRANSACTIONS : produces
FILLS ||--|| HOLDING_MOVEMENTS : produces
@enduml
```

## Table groups, at a glance

- **Identity & access**: `users`, `sessions` — who can log in, and which sessions are live.
- **Reference data**: `instruments`, `stocks` — what can be traded.
- **Market data (FMS-fed)**: `price_points` (live today), `market_ticks`, `quotes`, `candles`, `market_state` (reserved for later FMS phases, empty for now).
- **Money & positions**: `accounts`, `holdings` — current-state caches.
- **Trading pipeline**: `orders` → `fills` → `cash_transactions` + `holding_movements` (the ledgers) → `audit_trail` (permanent record).
