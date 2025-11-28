# Levis.fx BOT - Problem Definition

## Executive Summary

The Levis.fx BOT is an automated trading system designed to solve critical challenges in Asian session gold (XAUUSD) trading. This document outlines the 11 core problems the bot addresses, their root causes, and the systematic solutions implemented.

---

## Problem 1: Missed Trading Setups

### Problem Statement
Manual monitoring of Asian session ranges (00:00-08:00 UTC) is impractical, leading to missed high-probability retest opportunities.

### Impact
- Lost profit opportunities when optimal setups occur during sleep/work hours
- Inconsistent capture of Asian session liquidity traps
- Emotional frustration from missed trades

### Root Causes
1. Asian session timing conflicts with trader availability
2. Human inability to monitor markets 24/7
3. Delayed reaction time to price action

### Solution Implemented
**Automated Session Detection Module (SessionRange.mqh)**
- Automatically calculates Asian High/Low every session
- Real-time monitoring on M5 timeframe
- Instant alert generation on retest conditions

### Success Criteria
- ✅ 100% capture rate of valid Asian session ranges
- ✅ Zero missed sessions due to human unavailability
- ✅ Alert latency < 1 second from touch event

---

## Problem 2: Inconsistent Execution

### Problem Statement
Manual trade execution introduces variability in entry timing, stop-loss placement, and position sizing, reducing statistical edge.

### Impact
- Reduced win rate due to late entries
- Inconsistent risk management
- Inability to backtest strategy accurately
- Emotional decision-making during volatile moves

### Root Causes
1. Human hesitation and second-guessing
2. Emotional state affecting decision quality
3. Variable reaction time (1-5 seconds delay)
4. Inconsistent interpretation of "valid retest"

### Solution Implemented
**Deterministic Rule Engine**
- Fixed touch tolerance (50 points configurable)
- Exact retest counting algorithm
- No subjective interpretation
- Microsecond execution precision

### Success Criteria
- ✅ 100% rule adherence (no discretionary overrides)
- ✅ Consistent entry within tolerance every time
- ✅ Reproducible results in backtesting

---

## Problem 3: Slow Reaction to Liquidity Sweeps

### Problem Statement
Human traders cannot detect and react to fast wick sweeps of Asian ranges in real-time, missing prime continuation entries.

### Impact
- Missed optimal entry prices
- Entering late after momentum exhausted
- Reduced risk/reward ratios

### Root Causes
1. Human visual processing delay (200-300ms)
2. Manual order placement time (2-5 seconds)
3. Indecision during volatile candles
4. Fear of false breakouts

### Solution Implemented
**Tick-by-Tick Monitoring (OnTick)**
- Real-time price monitoring every tick
- Instant detection of wick touches
- Immediate alert/log generation
- Preparation for Phase 4 automated execution

### Success Criteria
- ✅ Detection within 1 tick of touch event
- ✅ Alert fired before candle close
- ✅ Wick vs body touch differentiation

---

## Problem 4: Ambiguity Between Retest vs Continuation

### Problem Statement
Difficulty determining if a retest is the "final" retest before breakout or just another range-bound touch.

### Impact
- Entering too early (on first touch, getting stopped out)
- Entering too late (after breakout already happened)
- Confusion about optimal entry timing

### Root Causes
1. No systematic counting mechanism
2. Subjective interpretation of "valid retest"
3. Lack of historical retest patterns analysis
4. Emotion-driven pattern recognition

### Solution Implemented
**Deterministic Retest Counter (RetestCounter.mqh)**
- Exact touch counting: 1st, 2nd, 3rd+
- Mode detection algorithm:
  - 1st touch = "FIRST_TOUCH" (monitor only)
  - 2nd touch = "CONTINUATION_MODE" (high probability)
  - 3+ touches = "CAUTION_MULTIPLE" (risk of fake breakout)
- Timestamp tracking to prevent double-counting
- Wick vs body touch classification

### Success Criteria
- ✅ 100% accurate touch counting
- ✅ 95%+ correlation between "CONTINUATION_MODE" and actual breakouts
- ✅ Clear mode signals for decision-making

---

## Problem 5: Overtrading & Noise in Asian Session

### Problem Statement
Not all Asian ranges are equal; some are too tight (noise) while others expand due to news, leading to false signals.

### Impact
- Losses from trading low-probability setups
- Emotional fatigue from excessive alerts
- Capital erosion from spread/commission costs

### Root Causes
1. No range quality filter
2. Trading during low-liquidity periods
3. Ignoring volatility context (ATR)
4. No maximum touch count cutoff

### Solution Implemented
**Volatility & Range Filters (Planned Phase 5)**
- ATR-based range validation
- Minimum range size requirement
- Maximum touch count filter (>3 = skip)
- Time-of-day quality score

### Success Criteria
- ✅ Reduce trade frequency by 40-60%
- ✅ Improve win rate by 10-15%
- ✅ Filter out noise ranges < 0.5 × average ATR

---

## Problem 6: Static Risk Parameters Across Volatility Regimes

### Problem Statement
Using fixed stop-loss and take-profit distances fails to adapt to changing market volatility, causing premature stops or missed profit targets.

### Impact
- Stopped out during normal volatility expansion
- Leaving profit on table during strong trends
- Poor risk/reward ratios in different regimes

### Root Causes
1. No volatility measurement in decision-making
2. Fixed pip-based SL/TP regardless of ATR
3. Ignoring regime changes (low → high volatility)

### Solution Implemented
**ATR-Based Risk Scaling (Planned Phase 5)**
- SL = ATR(14) × 1.5 (adjustable multiplier)
- TP = ATR(14) × 2.0
- Dynamic lot sizing based on volatility
- Regime detection (low/medium/high volatility)

### Success Criteria
- ✅ SL/TP automatically adjust to current ATR
- ✅ Reduce premature stop-outs by 30%
- ✅ Improve profit capture by 20%

---

## Problem 7: Lack of Confluence Checks

### Problem Statement
Entering solely on retest count ignores other critical factors like Fair Value Gaps (FVG), VWAP bias, and proximity to session extremes.

### Impact
- Lower win rate due to isolated signal reliance
- Missing high-confluence setups
- Entering against broader market structure

### Root Causes
1. Single-factor decision-making
2. No systematic confluence scoring
3. Manual confluence checks too slow

### Solution Implemented
**Multi-Confluence Filter (Planned Phase 2-3)**
- FVG detection within range
- VWAP bias confirmation
- HTF/LTF trend alignment
- Minimum confluence score required (e.g., 2 of 3 checks)

### Success Criteria
- ✅ Require 2+ confluence factors before entry
- ✅ Improve win rate by 15-20%
- ✅ Reduce false signals by 40%

---

## Problem 8: Poor Logging & Traceability

### Problem Statement
Without structured logs of every decision (why trade was taken/skipped), it's impossible to diagnose issues or optimize strategy.

### Impact
- Cannot identify which rules are failing
- No audit trail for debugging
- Inability to prove strategy edge statistically

### Root Causes
1. Manual note-taking is incomplete
2. No timestamp precision
3. Missing key decision factors in logs
4. Unstructured log format

### Solution Implemented
**Structured Logging System (Logger.mqh - Phase 1)**
- Timestamp every decision (millisecond precision)
- Log session data: High, Low, Range
- Log every touch: Price, Type (wick/body), Count
- Log trading mode changes
- Export to CSV for analysis

### Success Criteria
- ✅ 100% of decisions logged with full context
- ✅ Logs parsable for statistical analysis
- ✅ Traceability from alert → decision → execution

---

## Problem 9: HTF/LTF Trend Misalignment

### Problem Statement
Entering retests against Higher Timeframe (HTF) trend leads to low win rates, as LTF setups get overwhelmed by HTF momentum.

### Impact
- Counter-trend trades with poor risk/reward
- Increased stop-out rate
- Fighting institutional order flow

### Root Causes
1. Only analyzing Lower Timeframe (M5)
2. Ignoring H4/H1 trend direction
3. No swing structure awareness (HH/HL/LL/LH)

### Solution Implemented
**HTF/LTF Alignment Module (Planned Phase 2)**
- H4 trend detection (price above/below EMA/SMA)
- Swing structure mapping (HH, HL, LL, LH)
- Require HTF and LTF alignment before entry
- Support/Resistance level marking on HTF

### Success Criteria
- ✅ Only trade with HTF trend (no counter-trend)
- ✅ Improve win rate by 20-25%
- ✅ Reduce drawdown by 30%

---

## Problem 10: No Automatic Support/Resistance Marking

### Problem Statement
Manually identifying swing highs/lows for stop-loss and take-profit placement is time-consuming and subjective.

### Impact
- Inconsistent SL/TP placement
- Missing optimal S/R levels
- Suboptimal risk/reward ratios

### Root Causes
1. Manual chart drawing is slow
2. Subjective interpretation of "significant" swing
3. Missed hidden levels

### Solution Implemented
**Swing Structure Detector (SwingStructure.mqh - Phase 1)**
- Automatic HH/HL/LL/LH detection
- Mark swing points as S/R levels
- Adaptive SL = Previous HL/LL
- Adaptive TP = Previous S/R level

### Success Criteria
- ✅ 95%+ accuracy in swing detection
- ✅ SL placement at structural levels
- ✅ TP aligned with resistance zones

---

## Problem 11: No CHoCH (Change of Character) Monitoring

### Problem Statement
Without detecting trend reversals (CHoCH), the bot may continue trading a broken setup after market structure shifts.

### Impact
- Trading outdated patterns
- Losses during trend reversals
- No adaptation to changing conditions

### Root Causes
1. No break-of-structure detection
2. Ignoring HH/LL break patterns
3. Lagging response to reversals

### Solution Implemented
**CHoCH Detector (Planned Phase 3)**
- Monitor for HH break (potential reversal to downtrend)
- Monitor for LL break (potential reversal to uptrend)
- Pause trading on CHoCH until new structure confirmed
- Alert on structural breaks

### Success Criteria
- ✅ Detect 95%+ of valid CHoCH events
- ✅ Avoid 50%+ of post-reversal losses
- ✅ Adapt strategy to new structure within 1-2 bars

---

## Summary: Problems → Solutions Mapping

| # | Problem | Solution Module | Phase | Status |
|---|---------|----------------|-------|--------|
| 1 | Missed Setups | SessionRange.mqh | 1 | ✅ Implemented |
| 2 | Inconsistent Execution | Deterministic Rules | 1 | ✅ Implemented |
| 3 | Slow Reaction | OnTick Monitoring | 1 | ✅ Implemented |
| 4 | Retest Ambiguity | RetestCounter.mqh | 1 | ✅ Implemented |
| 5 | Overtrading | Volatility Filters | 5 | 🔄 Planned |
| 6 | Static Risk | ATR Scaling | 5 | 🔄 Planned |
| 7 | No Confluence | Confluence.mqh | 2-3 | 🔄 Planned |
| 8 | Poor Logging | Logger.mqh | 1 | ✅ Implemented |
| 9 | HTF/LTF Misalignment | TrendAlignment.mqh | 2 | 🔄 Planned |
| 10 | Manual S/R | SwingStructure.mqh | 1 | ✅ Implemented |
| 11 | No CHoCH Detection | BreakoutTrigger.mqh | 3 | 🔄 Planned |

---

## Development Philosophy

### Core Principles
1. **Determinism Over Discretion**: Every decision is rule-based, no subjective calls
2. **Traceability Over Opacity**: Full logging of every action for audit and optimization
3. **Adaptability Over Static Rules**: Parameters adjust to volatility and market regime
4. **Confluence Over Single Signals**: Require multiple confirming factors
5. **Protection Over Aggression**: Risk management takes priority over profit maximization

### Validation Requirements
- **Backtesting**: Minimum 6 months tick data across different volatility regimes
- **Walk-Forward Testing**: Out-of-sample validation on unseen data
- **Paper Trading**: 30 days live paper trading before real capital deployment
- **Statistical Significance**: Minimum 100 trades for meaningful win rate/expectancy

---

## Next Steps

### Phase 1 (Current) - Core Detection ✅
- [x] Session range calculation
- [x] Retest counter with touch detection
- [x] Swing structure detection
- [x] Basic logging

### Phase 2 - Confluence & Filters 🔄
- [ ] HTF/LTF trend alignment
- [ ] FVG detector
- [ ] VWAP bias confirmation
- [ ] Multi-confluence aggregator

### Phase 3 - Trigger & Breakout 🔄
- [ ] CHoCH detection
- [ ] HH/LL break logic
- [ ] Entry confirmation system

### Phase 4 - Execution & Risk 🔄
- [ ] Order placement engine
- [ ] Adaptive SL/TP
- [ ] Dynamic lot sizing
- [ ] Cooldown management

### Phase 5 - Volatility Adaptation 🔄
- [ ] ATR-based scaling
- [ ] Regime detection
- [ ] Dynamic parameters

### Phase 6 - Backtest & Optimization 🔄
- [ ] Strategy Tester validation
- [ ] Walk-forward testing
- [ ] Parameter optimization
- [ ] Live paper trading

---

**Last Updated**: 2025-11-28  
**Author**: Levis Mwaniki (@Levis-101)  
**Status**: Phase 1 Complete - Core Detection Modules Operational
