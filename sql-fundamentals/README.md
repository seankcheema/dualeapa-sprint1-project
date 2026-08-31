# Module 03 Lab — Basic Queries Against the Enterprise Schema

## Objectives

By the end of this lab you will have:

- Written SELECT/WHERE/ORDER BY queries answering real business questions
- Correctly handled NULL in a WHERE clause
- Written queries that are clear and readable, not just correct

## Setup

- The enterprise schema, loaded in Module 02

## Task sheet

Write one query per business question. Keep queries readable: consistent capitalisation of
keywords, one clause per line once a query has more than one clause.

1. List every client's name and risk profile.
2. List the names of all clients with a "Cautious" risk profile.
3. List all clients who joined before 2018-01-01, ordered by join date, oldest first.
4. List all clients with a risk profile of either "Cautious" or "Adventurous" (not "Balanced").
5. List the name and date of birth of every client born in the 1980s.
6. List every instrument's ticker and name, ordered alphabetically by name.
7. List all transactions of type 'DIVIDEND', most recent first.
8. Find every transaction that has no associated instrument (hint: think about which
   transaction types wouldn't have one, and what that means for the `instrument_id` column).
   Use the correct way of checking for this, not `= NULL`.
9. List the distinct list of account types that actually exist in the `accounts` table.
10. List every client along with their date of birth, but only for clients whose date of birth
    is **not** null. (Trick question: check whether this table can even contain nulls here, and
    explain why your query is correct either way.)

## Acceptance criteria

- All ten queries run without error and return the expected rows.
- Query 8 correctly uses `IS NULL`, not `= NULL`.
- Queries are formatted consistently: keywords capitalised, one clause per line for anything
  with more than a single WHERE condition.

If you finish early, rewrite query 4 two different ways (once with `IN`, once with `OR`), which
do you find more readable, and why?
