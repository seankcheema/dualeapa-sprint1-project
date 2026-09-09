"""
Reporting Metrics Calculator
Calculates performance, risk, and trading analytics metrics for the reporting system.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
from enum import Enum


class TimeFrame(Enum):
    """Time frame options for metric calculations."""
    DAILY = "1D"
    WEEKLY = "1W"
    MONTHLY = "1M"
    QUARTERLY = "1Q"
    YEARLY = "1Y"


@dataclass
class PerformanceMetrics:
    """Container for performance metrics."""
    total_return_percent: float
    ytd_return_percent: float
    sharpe_ratio: float
    max_drawdown_percent: float
    win_rate_percent: float
    profit_factor: float
    avg_trade_return: float
    total_trades_count: int
    winning_trades_count: int
    losing_trades_count: int
    calculated_date: datetime


@dataclass
class TradeAnalytics:
    """Container for trade analytics."""
    total_trades_count: int
    total_volume: float
    total_cost: float
    realized_pnl: float
    avg_entry_price: float
    avg_exit_price: float
    win_rate_percent: float
    period_start: datetime
    period_end: datetime


@dataclass
class RiskMetrics:
    """Container for risk metrics."""
    portfolio_value: float
    at_risk_value: float
    var_95_percent: float  # Value at Risk at 95% confidence
    cvar_95_percent: float  # Conditional Value at Risk
    beta: float
    correlation_to_market: float
    concentration_percent: float  # Concentration in top holding
    leverage_ratio: float


class PerformanceCalculator:
    """Calculates performance metrics for trading accounts."""

    @staticmethod
    def calculate_returns(
        starting_balance: float,
        ending_balance: float,
        period_days: int
    ) -> Dict[str, float]:
        """
        Calculate returns for a period.
        
        Args:
            starting_balance: Starting account balance
            ending_balance: Ending account balance
            period_days: Number of days in period
            
        Returns:
            Dict with total_return_percent and annualized_return_percent
        """
        if starting_balance <= 0:
            return {"total_return_percent": 0, "annualized_return_percent": 0}
        
        total_return = ((ending_balance - starting_balance) / starting_balance) * 100
        annualized_return = total_return * (365 / period_days) if period_days > 0 else 0
        
        return {
            "total_return_percent": round(total_return, 4),
            "annualized_return_percent": round(annualized_return, 4)
        }

    @staticmethod
    def calculate_drawdown(equity_curve: pd.Series) -> Tuple[float, float]:
        """
        Calculate maximum drawdown and current drawdown.
        
        Args:
            equity_curve: Series of portfolio values over time
            
        Returns:
            Tuple of (max_drawdown_percent, current_drawdown_percent)
        """
        if len(equity_curve) == 0:
            return 0, 0
        
        running_max = equity_curve.expanding().max()
        drawdown = (equity_curve - running_max) / running_max * 100
        max_drawdown = drawdown.min()
        current_drawdown = drawdown.iloc[-1]
        
        return round(max_drawdown, 4), round(current_drawdown, 4)

    @staticmethod
    def calculate_sharpe_ratio(
        returns: pd.Series,
        risk_free_rate: float = 0.02
    ) -> float:
        """
        Calculate Sharpe Ratio.
        
        Args:
            returns: Series of daily returns (as decimals)
            risk_free_rate: Annual risk-free rate
            
        Returns:
            Sharpe Ratio
        """
        if len(returns) < 2:
            return 0
        
        excess_returns = returns - (risk_free_rate / 252)  # 252 trading days
        sharpe = (excess_returns.mean() / excess_returns.std()) * np.sqrt(252)
        
        return round(sharpe, 4)

    @staticmethod
    def calculate_sortino_ratio(
        returns: pd.Series,
        risk_free_rate: float = 0.02
    ) -> float:
        """
        Calculate Sortino Ratio (penalizes downside volatility only).
        
        Args:
            returns: Series of daily returns (as decimals)
            risk_free_rate: Annual risk-free rate
            
        Returns:
            Sortino Ratio
        """
        if len(returns) < 2:
            return 0
        
        excess_returns = returns - (risk_free_rate / 252)
        downside_returns = returns[returns < 0]
        downside_std = downside_returns.std()
        
        if downside_std == 0:
            return 0
        
        sortino = (excess_returns.mean() / downside_std) * np.sqrt(252)
        return round(sortino, 4)

    @staticmethod
    def calculate_calmar_ratio(
        returns: pd.Series,
        max_drawdown: float
    ) -> float:
        """
        Calculate Calmar Ratio (annual return / max drawdown).
        
        Args:
            returns: Series of daily returns
            max_drawdown: Maximum drawdown (as decimal, e.g., -0.15 for -15%)
            
        Returns:
            Calmar Ratio
        """
        if max_drawdown >= 0 or len(returns) == 0:
            return 0
        
        annual_return = (1 + returns.sum()) ** 252 - 1
        calmar = annual_return / abs(max_drawdown)
        
        return round(calmar, 4)


class TradeAnalyticsCalculator:
    """Calculates trade-level analytics."""

    @staticmethod
    def calculate_win_rate(trades: pd.DataFrame) -> float:
        """
        Calculate percentage of winning trades.
        
        Args:
            trades: DataFrame with 'pnl' column
            
        Returns:
            Win rate as percentage
        """
        if len(trades) == 0:
            return 0
        
        winning_trades = (trades['pnl'] > 0).sum()
        win_rate = (winning_trades / len(trades)) * 100
        
        return round(win_rate, 4)

    @staticmethod
    def calculate_profit_factor(trades: pd.DataFrame) -> float:
        """
        Calculate profit factor (gross profit / gross loss).
        
        Args:
            trades: DataFrame with 'pnl' column
            
        Returns:
            Profit factor
        """
        if len(trades) == 0:
            return 0
        
        gross_profit = trades[trades['pnl'] > 0]['pnl'].sum()
        gross_loss = abs(trades[trades['pnl'] < 0]['pnl'].sum())
        
        if gross_loss == 0:
            return 0
        
        profit_factor = gross_profit / gross_loss
        return round(profit_factor, 4)

    @staticmethod
    def calculate_average_win_loss(
        trades: pd.DataFrame
    ) -> Dict[str, float]:
        """
        Calculate average win and average loss.
        
        Args:
            trades: DataFrame with 'pnl' column
            
        Returns:
            Dict with avg_win and avg_loss
        """
        if len(trades) == 0:
            return {"avg_win": 0, "avg_loss": 0}
        
        wins = trades[trades['pnl'] > 0]['pnl']
        losses = trades[trades['pnl'] < 0]['pnl']
        
        avg_win = wins.mean() if len(wins) > 0 else 0
        avg_loss = losses.mean() if len(losses) > 0 else 0
        
        return {
            "avg_win": round(avg_win, 2),
            "avg_loss": round(avg_loss, 2)
        }

    @staticmethod
    def calculate_expectancy(trades: pd.DataFrame) -> float:
        """
        Calculate expected value per trade.
        
        Args:
            trades: DataFrame with 'pnl' column
            
        Returns:
            Expected value per trade
        """
        if len(trades) == 0:
            return 0
        
        expectancy = trades['pnl'].mean()
        return round(expectancy, 2)

    @staticmethod
    def group_trades_by_instrument(
        trades: pd.DataFrame
    ) -> Dict[str, pd.DataFrame]:
        """
        Group trades by instrument for instrument-level analytics.
        
        Args:
            trades: DataFrame with 'instrument_id' column
            
        Returns:
            Dict mapping instrument_id to trade DataFrame
        """
        return {
            instrument_id: group
            for instrument_id, group in trades.groupby('instrument_id')
        }


class RiskCalculator:
    """Calculates risk metrics."""

    @staticmethod
    def calculate_var(
        returns: pd.Series,
        confidence_level: float = 0.95,
        portfolio_value: float = 100000
    ) -> float:
        """
        Calculate Value at Risk (VaR).
        
        Args:
            returns: Series of daily returns
            confidence_level: Confidence level (e.g., 0.95 for 95%)
            portfolio_value: Current portfolio value
            
        Returns:
            VaR in dollars
        """
        if len(returns) == 0:
            return 0
        
        var = np.percentile(returns, (1 - confidence_level) * 100)
        return round(var * portfolio_value, 2)

    @staticmethod
    def calculate_cvar(
        returns: pd.Series,
        confidence_level: float = 0.95,
        portfolio_value: float = 100000
    ) -> float:
        """
        Calculate Conditional Value at Risk (CVaR / Expected Shortfall).
        
        Args:
            returns: Series of daily returns
            confidence_level: Confidence level
            portfolio_value: Current portfolio value
            
        Returns:
            CVaR in dollars
        """
        if len(returns) == 0:
            return 0
        
        var_threshold = np.percentile(returns, (1 - confidence_level) * 100)
        tail_returns = returns[returns <= var_threshold]
        cvar = tail_returns.mean()
        
        return round(cvar * portfolio_value, 2)

    @staticmethod
    def calculate_beta(
        asset_returns: pd.Series,
        market_returns: pd.Series
    ) -> float:
        """
        Calculate Beta (correlation with market).
        
        Args:
            asset_returns: Series of asset returns
            market_returns: Series of market returns
            
        Returns:
            Beta coefficient
        """
        if len(asset_returns) < 2 or len(market_returns) < 2:
            return 0
        
        covariance = np.cov(asset_returns, market_returns)[0, 1]
        market_variance = np.var(market_returns)
        
        if market_variance == 0:
            return 0
        
        beta = covariance / market_variance
        return round(beta, 4)

    @staticmethod
    def calculate_concentration(holdings: pd.DataFrame) -> float:
        """
        Calculate portfolio concentration (% of top holding).
        
        Args:
            holdings: DataFrame with 'value' column (market value)
            
        Returns:
            Concentration percentage
        """
        if len(holdings) == 0:
            return 0
        
        total_value = holdings['value'].sum()
        if total_value == 0:
            return 0
        
        top_holding_value = holdings['value'].max()
        concentration = (top_holding_value / total_value) * 100
        
        return round(concentration, 4)

    @staticmethod
    def calculate_leverage(
        total_position_value: float,
        account_equity: float
    ) -> float:
        """
        Calculate leverage ratio.
        
        Args:
            total_position_value: Total value of all positions
            account_equity: Account equity/capital
            
        Returns:
            Leverage ratio
        """
        if account_equity <= 0:
            return 0
        
        leverage = total_position_value / account_equity
        return round(leverage, 4)


class ReportingAggregator:
    """Aggregates metrics for reporting."""

    @staticmethod
    def generate_daily_report(
        account_id: int,
        equity_curve: pd.Series,
        daily_returns: pd.Series,
        trades: pd.DataFrame,
        date: datetime
    ) -> PerformanceMetrics:
        """
        Generate daily performance report.
        
        Args:
            account_id: Account ID
            equity_curve: Series of daily account values
            daily_returns: Series of daily returns
            trades: DataFrame of trades
            date: Report date
            
        Returns:
            PerformanceMetrics object
        """
        pc = PerformanceCalculator()
        tac = TradeAnalyticsCalculator()
        
        # Calculate returns
        returns = pc.calculate_returns(
            starting_balance=equity_curve.iloc[0],
            ending_balance=equity_curve.iloc[-1],
            period_days=(date - equity_curve.index[0]).days or 1
        )
        
        # Calculate drawdown
        max_dd, _ = pc.calculate_drawdown(equity_curve)
        
        # Calculate trading metrics
        win_rate = tac.calculate_win_rate(trades)
        profit_factor = tac.calculate_profit_factor(trades)
        avg_return = tac.calculate_expectancy(trades)
        
        return PerformanceMetrics(
            total_return_percent=returns['total_return_percent'],
            ytd_return_percent=returns['total_return_percent'],  # For daily, same as total
            sharpe_ratio=pc.calculate_sharpe_ratio(daily_returns),
            max_drawdown_percent=max_dd,
            win_rate_percent=win_rate,
            profit_factor=profit_factor,
            avg_trade_return=avg_return,
            total_trades_count=len(trades),
            winning_trades_count=(trades['pnl'] > 0).sum(),
            losing_trades_count=(trades['pnl'] < 0).sum(),
            calculated_date=date
        )

    @staticmethod
    def generate_risk_report(
        account_id: int,
        returns: pd.Series,
        holdings: pd.DataFrame,
        portfolio_value: float,
        market_returns: pd.Series
    ) -> RiskMetrics:
        """
        Generate risk metrics report.
        
        Args:
            account_id: Account ID
            returns: Series of daily returns
            holdings: DataFrame of current holdings
            portfolio_value: Current portfolio value
            market_returns: Series of market returns
            
        Returns:
            RiskMetrics object
        """
        rc = RiskCalculator()
        
        return RiskMetrics(
            portfolio_value=portfolio_value,
            at_risk_value=rc.calculate_var(returns, portfolio_value=portfolio_value),
            var_95_percent=rc.calculate_var(returns, 0.95, portfolio_value),
            cvar_95_percent=rc.calculate_cvar(returns, 0.95, portfolio_value),
            beta=rc.calculate_beta(returns, market_returns),
            correlation_to_market=returns.corr(market_returns),
            concentration_percent=rc.calculate_concentration(holdings),
            leverage_ratio=rc.calculate_leverage(holdings['value'].sum(), portfolio_value)
        )
