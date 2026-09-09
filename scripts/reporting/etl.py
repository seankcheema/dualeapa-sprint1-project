"""
Reporting ETL (Extract, Transform, Load)
Handles data pipeline from operational database to reporting database.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
import psycopg2
from psycopg2 import sql
from contextlib import contextmanager
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ReportingDatabaseConnection:
    """Manages connections to PostgreSQL databases."""
    
    def __init__(
        self,
        host: str,
        port: int,
        database: str,
        user: str,
        password: str
    ):
        self.connection_params = {
            'host': host,
            'port': port,
            'database': database,
            'user': user,
            'password': password
        }
    
    @contextmanager
    def get_connection(self):
        """Context manager for database connections."""
        conn = psycopg2.connect(**self.connection_params)
        try:
            yield conn
            conn.commit()
        except Exception as e:
            conn.rollback()
            logger.error(f"Database error: {e}")
            raise
        finally:
            conn.close()
    
    @contextmanager
    def get_cursor(self):
        """Context manager for database cursors."""
        with self.get_connection() as conn:
            cursor = conn.cursor()
            try:
                yield cursor
            finally:
                cursor.close()


class ReportingETL:
    """Handles ETL process for reporting."""
    
    def __init__(self, db_connection: ReportingDatabaseConnection):
        self.db = db_connection
    
    def extract_trades(
        self,
        account_id: int,
        start_date: datetime,
        end_date: datetime
    ) -> pd.DataFrame:
        """
        Extract trades from operational database.
        
        Args:
            account_id: Account ID to extract trades for
            start_date: Start date for extraction
            end_date: End date for extraction
            
        Returns:
            DataFrame with trade data
        """
        query = sql.SQL("""
            SELECT 
                o.order_id,
                o.account_id,
                o.instrument_id,
                i.ticker,
                o.order_type,
                o.quantity,
                o.indicative_price,
                f.quote_price,
                f.quantity as filled_quantity,
                f.filled_at,
                (f.quote_price * f.quantity) - (o.indicative_price * f.quantity) as pnl,
                o.submitted_at
            FROM orders o
            JOIN instruments i ON o.instrument_id = i.instrument_id
            LEFT JOIN fills f ON o.order_id = f.order_id
            WHERE o.account_id = %s
                AND o.submitted_at >= %s
                AND o.submitted_at <= %s
                AND f.fill_id IS NOT NULL
            ORDER BY f.filled_at
        """)
        
        with self.db.get_cursor() as cursor:
            cursor.execute(query, (account_id, start_date, end_date))
            columns = [desc[0] for desc in cursor.description]
            data = cursor.fetchall()
        
        df = pd.DataFrame(data, columns=columns)
        logger.info(f"Extracted {len(df)} trades for account {account_id}")
        return df
    
    def extract_holdings(
        self,
        account_id: int,
        as_of_date: datetime
    ) -> pd.DataFrame:
        """
        Extract holdings as of a specific date.
        
        Args:
            account_id: Account ID
            as_of_date: Date to extract holdings as of
            
        Returns:
            DataFrame with holdings data
        """
        query = sql.SQL("""
            SELECT 
                h.holding_id,
                h.account_id,
                h.instrument_id,
                i.ticker,
                h.quantity,
                mp.price as current_price,
                (h.quantity * mp.price) as market_value,
                h.updated_at
            FROM holdings h
            JOIN instruments i ON h.instrument_id = i.instrument_id
            LEFT JOIN (
                SELECT DISTINCT ON (instrument_id)
                    instrument_id,
                    price
                FROM price_points
                WHERE observed_at <= %s
                ORDER BY instrument_id, observed_at DESC
            ) mp ON h.instrument_id = mp.instrument_id
            WHERE h.account_id = %s
                AND h.updated_at <= %s
                AND h.quantity > 0
        """)
        
        with self.db.get_cursor() as cursor:
            cursor.execute(query, (as_of_date, account_id, as_of_date))
            columns = [desc[0] for desc in cursor.description]
            data = cursor.fetchall()
        
        df = pd.DataFrame(data, columns=columns)
        logger.info(f"Extracted {len(df)} holdings for account {account_id}")
        return df
    
    def extract_cash_balance(
        self,
        account_id: int,
        as_of_date: datetime
    ) -> float:
        """
        Extract cash balance as of a specific date.
        
        Args:
            account_id: Account ID
            as_of_date: Date to extract balance as of
            
        Returns:
            Cash balance amount
        """
        query = sql.SQL("""
            SELECT cash_balance
            FROM accounts
            WHERE account_id = %s
        """)
        
        with self.db.get_cursor() as cursor:
            cursor.execute(query, (account_id,))
            result = cursor.fetchone()
        
        return result[0] if result else 0.0
    
    def transform_daily_performance(
        self,
        trades: pd.DataFrame,
        previous_balance: float,
        current_balance: float,
        daily_returns: pd.Series
    ) -> Dict:
        """
        Transform trade and balance data into performance metrics.
        
        Args:
            trades: DataFrame of trades for the period
            previous_balance: Balance at start of period
            current_balance: Balance at end of period
            daily_returns: Series of daily returns
            
        Returns:
            Dict with transformed performance data
        """
        total_trades = len(trades)
        winning_trades = (trades['pnl'] > 0).sum() if len(trades) > 0 else 0
        losing_trades = (trades['pnl'] < 0).sum() if len(trades) > 0 else 0
        
        total_return = (
            (current_balance - previous_balance) / previous_balance * 100
            if previous_balance > 0 else 0
        )
        
        sharpe_ratio = (
            (daily_returns.mean() / daily_returns.std()) * np.sqrt(252)
            if len(daily_returns) > 1 and daily_returns.std() > 0 else 0
        )
        
        avg_pnl = trades['pnl'].mean() if len(trades) > 0 else 0
        win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0
        
        profit_factor = 0
        if len(trades) > 0:
            gross_profit = trades[trades['pnl'] > 0]['pnl'].sum()
            gross_loss = abs(trades[trades['pnl'] < 0]['pnl'].sum())
            profit_factor = gross_profit / gross_loss if gross_loss > 0 else 0
        
        return {
            'total_return_percent': round(total_return, 4),
            'sharpe_ratio': round(sharpe_ratio, 4),
            'win_rate_percent': round(win_rate, 4),
            'profit_factor': round(profit_factor, 4),
            'avg_trade_return': round(avg_pnl, 2),
            'total_trades_count': total_trades,
            'winning_trades_count': winning_trades,
            'losing_trades_count': losing_trades
        }
    
    def load_performance_metrics(
        self,
        account_id: int,
        metrics: Dict,
        date_calculated: datetime
    ) -> bool:
        """
        Load performance metrics into reporting database.
        
        Args:
            account_id: Account ID
            metrics: Dict of performance metrics
            date_calculated: Date metrics were calculated
            
        Returns:
            True if successful, False otherwise
        """
        query = sql.SQL("""
            INSERT INTO performance_metrics (
                account_id,
                date_calculated,
                total_return_percent,
                sharpe_ratio,
                win_rate_percent,
                profit_factor,
                avg_trade_return,
                total_trades_count,
                winning_trades_count,
                losing_trades_count
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (account_id, date_calculated) DO UPDATE SET
                total_return_percent = EXCLUDED.total_return_percent,
                sharpe_ratio = EXCLUDED.sharpe_ratio,
                win_rate_percent = EXCLUDED.win_rate_percent,
                profit_factor = EXCLUDED.profit_factor,
                avg_trade_return = EXCLUDED.avg_trade_return,
                total_trades_count = EXCLUDED.total_trades_count,
                winning_trades_count = EXCLUDED.winning_trades_count,
                losing_trades_count = EXCLUDED.losing_trades_count
        """)
        
        try:
            with self.db.get_cursor() as cursor:
                cursor.execute(
                    query,
                    (
                        account_id,
                        date_calculated,
                        metrics['total_return_percent'],
                        metrics['sharpe_ratio'],
                        metrics['win_rate_percent'],
                        metrics['profit_factor'],
                        metrics['avg_trade_return'],
                        metrics['total_trades_count'],
                        metrics['winning_trades_count'],
                        metrics['losing_trades_count']
                    )
                )
            logger.info(f"Loaded performance metrics for account {account_id}")
            return True
        except Exception as e:
            logger.error(f"Error loading metrics: {e}")
            return False
    
    def load_trade_analytics(
        self,
        account_id: int,
        instrument_id: int,
        trades: pd.DataFrame,
        period_start: datetime,
        period_end: datetime
    ) -> bool:
        """
        Load trade analytics into reporting database.
        
        Args:
            account_id: Account ID
            instrument_id: Instrument ID
            trades: DataFrame of trades
            period_start: Start of analysis period
            period_end: End of analysis period
            
        Returns:
            True if successful, False otherwise
        """
        if len(trades) == 0:
            return True  # No trades to load
        
        total_trades = len(trades)
        total_volume = trades['quantity'].sum()
        total_cost = (trades['indicative_price'] * trades['quantity']).sum()
        realized_pnl = trades['pnl'].sum()
        avg_entry = trades['indicative_price'].mean()
        avg_exit = trades['quote_price'].mean()
        win_rate = (trades['pnl'] > 0).sum() / total_trades * 100
        
        query = sql.SQL("""
            INSERT INTO trade_analytics (
                account_id,
                instrument_id,
                period_start,
                period_end,
                total_trades_count,
                total_volume,
                total_cost,
                realized_pnl,
                avg_entry_price,
                avg_exit_price,
                win_rate_percent
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (account_id, instrument_id, period_start) DO UPDATE SET
                total_trades_count = EXCLUDED.total_trades_count,
                total_volume = EXCLUDED.total_volume,
                total_cost = EXCLUDED.total_cost,
                realized_pnl = EXCLUDED.realized_pnl,
                avg_entry_price = EXCLUDED.avg_entry_price,
                avg_exit_price = EXCLUDED.avg_exit_price,
                win_rate_percent = EXCLUDED.win_rate_percent
        """)
        
        try:
            with self.db.get_cursor() as cursor:
                cursor.execute(
                    query,
                    (
                        account_id,
                        instrument_id,
                        period_start,
                        period_end,
                        total_trades,
                        round(total_volume, 4),
                        round(total_cost, 2),
                        round(realized_pnl, 2),
                        round(avg_entry, 4),
                        round(avg_exit, 4),
                        round(win_rate, 4)
                    )
                )
            logger.info(f"Loaded trade analytics for account {account_id}, instrument {instrument_id}")
            return True
        except Exception as e:
            logger.error(f"Error loading trade analytics: {e}")
            return False


class ReportingScheduler:
    """Manages scheduled reporting jobs."""
    
    def __init__(self, etl: ReportingETL):
        self.etl = etl
    
    def run_daily_aggregation(self, target_date: datetime) -> bool:
        """
        Run daily metrics aggregation job.
        
        Args:
            target_date: Date to aggregate metrics for
            
        Returns:
            True if successful
        """
        logger.info(f"Starting daily aggregation for {target_date.date()}")
        
        # TODO: Get all active accounts
        # TODO: For each account:
        #   1. Extract trades for the day
        #   2. Extract holdings as of end of day
        #   3. Calculate performance metrics
        #   4. Load metrics into reporting DB
        
        logger.info("Daily aggregation completed")
        return True
    
    def run_hourly_refresh(self) -> bool:
        """Run hourly cache refresh job."""
        logger.info("Starting hourly cache refresh")
        
        # TODO: Refresh cache for current metrics
        # TODO: Update materialized views
        
        logger.info("Hourly refresh completed")
        return True
    
    def run_weekly_consolidation(self, week_start_date: datetime) -> bool:
        """
        Run weekly consolidation job.
        
        Args:
            week_start_date: Start date of week to consolidate
            
        Returns:
            True if successful
        """
        logger.info(f"Starting weekly consolidation for week of {week_start_date.date()}")
        
        # TODO: Consolidate metrics for the week
        # TODO: Generate weekly reports
        
        logger.info("Weekly consolidation completed")
        return True


if __name__ == "__main__":
    # Example usage
    db_conn = ReportingDatabaseConnection(
        host="localhost",
        port=5432,
        database="trading_platform_reporting",
        user="postgres",
        password="password"
    )
    
    etl = ReportingETL(db_conn)
    
    # Example: Extract trades for an account
    account_id = 1
    start_date = datetime.now() - timedelta(days=30)
    end_date = datetime.now()
    
    trades = etl.extract_trades(account_id, start_date, end_date)
    print(f"Extracted {len(trades)} trades")
    print(trades.head())
