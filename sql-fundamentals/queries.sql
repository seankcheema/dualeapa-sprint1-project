-- Module 03 Lab: Basic Queries Against the Enterprise Schema
-- NOTE: Schema uses joined_date (not joined_on), txn_type (not type), account_type (not type)

-- 1. List every client's name and risk profile.
SELECT name, risk_profile
FROM clients;

-- 2. List the names of all clients with a "Cautious" risk profile.
SELECT name
FROM clients
WHERE risk_profile = 'Cautious';

-- 3. List all clients who joined before 2018-01-01, ordered by join date, oldest first.
SELECT name, joined_date
FROM clients
WHERE joined_date < '2018-01-01'
ORDER BY joined_date ASC;

-- 4. List all clients with a risk profile of either "Cautious" or "Adventurous".
SELECT name, risk_profile
FROM clients
WHERE risk_profile IN ('Cautious', 'Adventurous');

-- 4b. Same query using OR instead of IN.
SELECT name, risk_profile
FROM clients
WHERE risk_profile = 'Cautious'
   OR risk_profile = 'Adventurous';

-- 5. List the name and date of birth of every client born in the 1980s.
SELECT name, date_of_birth
FROM clients
WHERE date_of_birth >= '1980-01-01'
  AND date_of_birth < '1990-01-01';

-- 6. List every instrument's ticker and name, ordered alphabetically by name.
SELECT ticker, name
FROM instruments
ORDER BY name ASC;

-- 7. List all transactions of type 'DIVIDEND', most recent first.
SELECT *
FROM transactions
WHERE txn_type = 'DIVIDEND'
ORDER BY txn_date DESC;

-- 8. Find every transaction that has no associated instrument (instrument_id IS NULL).
-- DEPOSIT and WITHDRAWAL transactions typically have no instrument.
SELECT *
FROM transactions
WHERE instrument_id IS NULL;

-- 9. List the distinct list of account types that actually exist in the accounts table.
SELECT DISTINCT account_type
FROM accounts;

-- 10. List every client along with their date of birth, only for clients whose DOB is not null.
-- NOTE: date_of_birth is defined NOT NULL in the schema, so this returns all clients.
-- The WHERE clause is still correct; it just happens to exclude nothing.
SELECT name, date_of_birth
FROM clients
WHERE date_of_birth IS NOT NULL;
