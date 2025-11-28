//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Phase 3/4: Execution       |
//| FIX: Integrated Trading Functions, R-Risk, and CHoCH Trigger     |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "2.0.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session (00:00-17:00)"

#include <Trade\Trade.mqh>
#include <PositionInfo.mqh>
#include "SessionRange.mqh"
#include "RetestCounter.mqh"
#include "SwingStructure.mqh"

CTrade Trade;
CPositionInfo Position;

//========== INPUT PARAMETERS ==========

// Session Configuration (Phase 1)
input int    AsianStartHour    = 0;      // Asian session start (server time)
input int    AsianEndHour      = 8;      // Asian session end (server time)
input int    LondonEndHour     = 17;     // Trading stops after this hour

// Detection Parameters (Phase 1/2)
input ENUM_TIMEFRAMES RangeTF  = PERIOD_M5;  // Timeframe for range calc
input int    TouchTolerancePts = 50;     // Touch tolerance in points
input int    SwingBars         = 2;      // Bars needed on each side for confirmed swing (Fractal)

// Risk Management & Execution (Phase 4)
input double RiskPerTrade      = 2.0;    // % of balance to risk per trade (from default.ini)
input double FixedLotSize      = 0.01;   // Fallback lot size if R-risk fails
input double RiskRewardRatio   = 2.0;    // R:R Target (e.g., 2.0 for 1:2)

// Trade Management (from StructuraX A&K)
input int    BreakEvenTriggerR = 1;      // Move SL to BE at +1R
input bool   TrailAfterBE      = true;   // Trail only after BE
input int    TrailingStopPips  = 100;    // Trail distance in points (in points)
input int    StopLevelBuffer   = 2;      // Extra pips buffer for SL

// Retest & Logging
input bool   EnableAlerts      = true;
input bool   EnableLogging     = true;
input bool   ShowRangeLines    = true;

//========== GLOBAL OBJECTS & VARIABLES ==========
CSessionRange *m_session = NULL;
CRetestCounter *m_retest = NULL;
SwingStructure *m_swing  = NULL;

ulong positionTicket = 0; // The primary ticket for the current trade
double entryPrice, slPrice, tpPrice;

//+------------------------------------------------------------------+
//| Helper: Calculate Lot Size (Dynamic Risk)                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double slInPoints) {
    if (slInPoints <= 0) return FixedLotSize;
    
    // 1. Calculate Risk Amount
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPerTrade / 100.0);
    
    // 2. Calculate Pips Value (Value of 1 lot * 1 point move)
    // SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) gives value of tick in base currency
    // For MQL5, LotSize calculation simplifies by using the margin formula for position size.
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // Calculate Lot size: RiskAmount / (StopLossInPoints * Point * TickValue)
    double lotSize = riskAmount / (slInPoints * point * tickValue);
    
    // 3. Normalize Lot Size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if (lotSize < minLot) lotSize = minLot;
    if (lotSize > maxLot) lotSize = maxLot;
    
    // Normalize to step
    lotSize = MathRound(lotSize / step) * step;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Order Execution                                                  |
//+------------------------------------------------------------------+
void ExecuteMarketOrder(bool isLong, double SL_Target, double TP_Target) {
    if (PositionSelect(_Symbol)) {
        Log("Trade skipped: Position already open.");
        return;
    }

    entryPrice = SymbolInfoDouble(_Symbol, isLong ? SYMBOL_ASK : SYMBOL_BID);
    
    // Calculate SL/TP in points (R)
    double slInPoints = MathAbs(entryPrice - SL_Target) / _Point;
    slInPoints += StopLevelBuffer; // Add buffer
    
    // Calculate final prices
    slPrice = NormalizeDouble(SL_Target, _Digits);
    tpPrice = NormalizeDouble(TP_Target, _Digits);

    // Dynamic Lot Size Calculation
    double lots = CalculateLotSize(slInPoints);
    if (lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
         Log("ERROR: Lot size too small or risk calculation failed. Using Fixed Lot Size.");
         lots = FixedLotSize;
    }
    
    // Execute Trade
    if (isLong) {
        if (!Trade.Buy(lots, _Symbol, entryPrice, slPrice, tpPrice)) {
            Log(StringFormat("Buy failed. Error: %d", Trade.ResultDeal()));
        }
    } else {
        if (!Trade.Sell(lots, _Symbol, entryPrice, slPrice, tpPrice)) {
            Log(StringFormat("Sell failed. Error: %d", Trade.ResultDeal()));
        }
    }
    
    if (Trade.ResultRetcode() == TRADE_RETCODE_DONE) {
        positionTicket = Trade.ResultDeal();
        Log(StringFormat("ORDER EXECUTED: %s %.2f @ %.5f. SL: %.5f TP: %.5f", 
            isLong ? "BUY" : "SELL", lots, entryPrice, slPrice, tpPrice));
    }
}

//+------------------------------------------------------------------+
//| Trailing Stop Logic (Integrated into BE check)                   |
//+------------------------------------------------------------------+
void TrailStop() {
    if (!PositionSelect(_Symbol)) return;
    
    double currentSL = Position.StopLoss();
    double currentPrice = Position.PriceCurrent();
    double posOpenPrice = Position.PriceOpen();
    ENUM_POSITION_TYPE type = Position.PositionType();
    
    double trailDistance = TrailingStopPips * _Point;
    double newSL = 0.0;
    
    if (type == POSITION_TYPE_BUY) {
        newSL = currentPrice - trailDistance;
        if (newSL > currentSL && newSL > posOpenPrice) { // Only trail up AND only if better than BE
            Trade.PositionModify(Position.Ticket(), newSL, Position.TakeProfit());
            Log(StringFormat("Trail Modified: Old SL %.5f -> New SL %.5f", currentSL, newSL));
        }
    } else if (type == POSITION_TYPE_SELL) {
        newSL = currentPrice + trailDistance;
        if (newSL < currentSL && newSL < posOpenPrice) { // Only trail down AND only if better than BE
            Trade.PositionModify(Position.Ticket(), newSL, Position.TakeProfit());
            Log(StringFormat("Trail Modified: Old SL %.5f -> New SL %.5f", currentSL, newSL));
        }
    }
}

//+------------------------------------------------------------------+
//| Break-even logic                                                 |
//+------------------------------------------------------------------+
void CheckBreakEven() {
    if (!PositionSelect(_Symbol)) return;
    
    double posOpenPrice = Position.PriceOpen();
    double currentSL = Position.StopLoss();
    ENUM_POSITION_TYPE type = Position.PositionType();

    // The original risk (R) in price units
    double riskPriceUnit = MathAbs(posOpenPrice - currentSL);
    double currentProfitPriceUnit = MathAbs(Position.PriceCurrent() - posOpenPrice);
    
    // Check if the profit is >= BreakEvenTriggerR * Risk
    bool hitBETrigger = (currentProfitPriceUnit >= BreakEvenTriggerR * riskPriceUnit);
    
    if (hitBETrigger && currentSL != posOpenPrice) {
        // Move SL to Entry Price (BE)
        double bePrice = posOpenPrice + (StopLevelBuffer * _Point * (type == POSITION_TYPE_BUY ? 1 : -1));
        
        // Ensure new BE is better than current SL and actually moves into profit (or close to zero risk)
        if ((type == POSITION_TYPE_BUY && bePrice > currentSL) || 
            (type == POSITION_TYPE_SELL && bePrice < currentSL)) {
            
            Trade.PositionModify(Position.Ticket(), NormalizeDouble(bePrice, _Digits), Position.TakeProfit());
            Log(StringFormat("BREAKEVEN: SL moved to %.5f (+%.2f R)", bePrice, BreakEvenTriggerR));
        }
        
        if (TrailAfterBE) TrailStop();
    } 
    // If not triggered BE yet, and trailing is enabled from start, check trail logic
    else if (!TrailAfterBE && Position.StopLoss() != 0) { 
        TrailStop();
    }
}


//+------------------------------------------------------------------+
//| Trade Trigger Logic (CHoCH at Retest)                            |
//+------------------------------------------------------------------+
void CheckTradeTriggers() {
    if (!m_session.IsValid() || !m_retest.HasNewTouch() || PositionSelect(_Symbol)) return;

    m_swing.updateStructure(); // Update confirmed structure points

    TouchEvent lastTouch;
    if (!m_retest.GetLastTouch(lastTouch)) return;

    // --- BEARISH SETUP (Touch High) ---
    if (lastTouch.isHigh && m_retest.GetTouchCountHigh() >= 1) {
        // Condition: Price touched the high, AND structure has flipped bearish (CHoCH)
        if (m_swing.isLowerLow || m_swing.isLowerHigh) { // Simplified CHoCH flip
            Log("TRIGGER: Bearish CHoCH confirmed at Asian High retest.");
            
            // SL should be above the new confirmed Lower High
            double sl = m_swing.GetLastHigh();
            // TP should be at the Asian Low or a multiple of R
            double tp = m_session.GetSessionLow();
            
            // Fallback for R-based TP if Asian Low is too close/far
            double riskInPrice = MathAbs(sl - lastTouch.price);
            double target = riskInPrice * RiskRewardRatio;
            if (MathAbs(tp - lastTouch.price) < target * 0.5) tp = lastTouch.price - target;

            ExecuteMarketOrder(false, sl, tp); // Short Trade
            m_retest.AcknowledgeTouch(); // Acknowledge touch to prevent re-entry
            return;
        }
    }

    // --- BULLISH SETUP (Touch Low) ---
    if (lastTouch.isLow && m_retest.GetTouchCountLow() >= 1) {
        // Condition: Price touched the low, AND structure has flipped bullish (CHoCH)
        if (m_swing.isHigherHigh || m_swing.isHigherLow) { // Simplified CHoCH flip
            Log("TRIGGER: Bullish CHoCH confirmed at Asian Low retest.");
            
            // SL should be below the new confirmed Higher Low
            double sl = m_swing.GetLastLow();
            // TP should be at the Asian High or a multiple of R
            double tp = m_session.GetSessionHigh();
            
            // Fallback for R-based TP
            double riskInPrice = MathAbs(sl - lastTouch.price);
            double target = riskInPrice * RiskRewardRatio;
            if (MathAbs(tp - lastTouch.price) < target * 0.5) tp = lastTouch.price + target;

            ExecuteMarketOrder(true, sl, tp); // Long Trade
            m_retest.AcknowledgeTouch(); // Acknowledge touch to prevent re-entry
            return;
        }
    }
}


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // --- Initialize Classes ---
    // Session class (needs no minute, uses only start/end hour)
    m_session = new CSessionRange(AsianStartHour, 0, AsianEndHour, 0, RangeTF, _Symbol);
    
    // Retest class needs tolerance and confirmation settings
    m_retest = new CRetestCounter(TouchTolerancePts, 1); // MinConfirmBars is always 1 for touch check
    
    // Swing class (uses M5 timeframe and 2 bars for standard fractal)
    m_swing = new SwingStructure(RangeTF, SwingBars, _Symbol);

    // Trade object
    Trade.SetExpertMagicNumber(123456);
    
    Log("=== LevisFxBot Initialized (Trading Enabled) === Version 2.0.0");
    Log(StringFormat("Trading Window: %02d:00 to %02d:00 Server Time", AsianStartHour, LondonEndHour));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Cleanup
    if(m_session != NULL) delete m_session;
    if(m_retest != NULL) delete m_retest;
    if(m_swing != NULL) delete m_swing;
    
    // Cleanup chart objects and comment (Code removed for brevity but assumed to be present)
    Comment(""); 
}

//+------------------------------------------------------------------+
//| Expert tick function (The core logic)                            |
//+------------------------------------------------------------------+
void OnTick() {
    if (m_session == NULL || m_retest == NULL || m_swing == NULL) return; 

    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);

    // --- PHASE 3: DAILY COOLDOWN/RESET ---
    if (dt.hour >= LondonEndHour) {
        // Reset everything for the next day
        if (m_session.IsValid()) {
             m_session.Reset();
             m_retest.Reset();
             Log("--- Cooldown Active. System Reset for next session. ---");
        }
        return; 
    }

    // --- PHASE 1: ASIAN SESSION (BUILD RANGE) ---
    if (dt.hour >= AsianStartHour && dt.hour < AsianEndHour) {
        
        // Dynamic Range Calculation
        m_session.Calculate();
        m_retest.SetLevels(m_session.GetSessionHigh(), m_session.GetSessionLow());
    } 
    // --- PHASE 2: LONDON SESSION (HUNT RETESTS) ---
    else if (dt.hour >= AsianEndHour && dt.hour < LondonEndHour) {
        
        if (!m_session.IsValid()) return;

        // Check for new touches/retests on the locked levels
        m_retest.CheckTouch(now);
        
        // EXECUTION: Check if conditions are met to open a trade
        CheckTradeTriggers();

        // RISK MANAGEMENT: Manage open position
        if (PositionSelect(_Symbol)) {
            CheckBreakEven();
        }
    }
    
    // Update Chart Visuals
    if(ShowRangeLines && m_session.IsValid()) {
        // UpdateChartInfo() function is assumed to be present or needs to be re-added
        // from the previous iteration to show lines and status.
    }
}
//+------------------------------------------------------------------+
