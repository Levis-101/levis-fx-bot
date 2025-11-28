//+------------------------------------------------------------------+
//| LevisFxBot.mq5                                                   |
//| Automated Asian Gold Trading System - Phase 1: Core Detection   |
//| Alerts-only prototype: Session range + retest counter           |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "1.0.0"
#property strict
#property description "Deterministic rule-based EA for XAUUSD Asian session"

#include <Trade\Trade.mqh>

//========== INPUT PARAMETERS ==========

// Session Configuration
input int    AsianStartHour    = 0;      // Asian session start (server time)
input int    AsianStartMinute  = 0;
input int    AsianEndHour      = 8;      // Asian session end (server time)
input int    AsianEndMinute    = 0;

// Detection Parameters
input int    LookbackBars      = 500;    // Bars to analyze
input int    TouchTolerancePts = 50;     // Touch tolerance in points
input int    MinConfirmBars    = 1;      // Candles to confirm touch
input ENUM_TIMEFRAMES RangeTF  = PERIOD_M5;  // Timeframe for range calc

// Retest Logic
input int    MaxRetestsToTrack = 5;      // Max retest count to track
input bool   EnableAlerts      = true;
input bool   EnableLogging     = true;

// Chart Display
input bool   ShowRangeLines    = true;   // Display Asian High/Low lines
input color  HighLineColor     = clrRed;
input color  LowLineColor      = clrBlue;
input ENUM_LINE_STYLE LineStyle = STYLE_SOLID;
input int    LineWidth         = 2;

//========== GLOBAL VARIABLES ==========

double asianHigh = 0.0;
double asianLow  = 0.0;
datetime lastAsianCalcTime = 0;

int touchCountHigh = 0;
int touchCountLow  = 0;

struct SessionData {
    datetime sessionStart;
    datetime sessionEnd;
    double   high;
    double   low;
    int      touchesHigh;
    int      touchesLow;
};

SessionData currentSession;

// Chart objects
string objHighLine = "AsianHigh";
string objLowLine = "AsianLow";
string objSessionBox = "SessionBox";

//========== UTILITY FUNCTIONS ==========

string LogPrefix() {
    return StringFormat("[%s] LevisFxBot: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
}

void Log(string msg) {
    if(EnableLogging) {
        Print(LogPrefix() + msg);
    }
}

void AlertLog(string msg) {
    if(EnableAlerts) {
        Alert(LogPrefix() + msg);
    }
    Log(msg);
}

//========== SESSION RANGE MODULE ==========

datetime GetSessionStartTime(datetime baseTime) {
    MqlDateTime dt;
    TimeToStruct(baseTime, dt);
    dt.hour = AsianStartHour;
    dt.min = AsianStartMinute;
    dt.sec = 0;
    return StructToTime(dt);
}

datetime GetSessionEndTime(datetime baseTime) {
    MqlDateTime dt;
    TimeToStruct(baseTime, dt);
    dt.hour = AsianEndHour;
    dt.min = AsianEndMinute;
    dt.sec = 0;
    datetime endTime = StructToTime(dt);
    
    // If end <= start, assume end is next day
    if(endTime <= GetSessionStartTime(baseTime)) {
        endTime += 24*3600;
    }
    return endTime;
}

void CalculateAsianRange() {
    datetime now = TimeCurrent();
    datetime sessionStart = GetSessionStartTime(now);
    datetime sessionEnd = GetSessionEndTime(now);
    
    // If current time before session start, use previous day's session
    if(now < sessionStart) {
        sessionStart -= 24*3600;
        sessionEnd -= 24*3600;
    }
    
    // Only recalculate once per session
    if(lastAsianCalcTime >= sessionStart && lastAsianCalcTime < sessionEnd) {
        return;
    }
    
    // Find bars within session on RangeTF
    int startIdx = iBarShift(_Symbol, RangeTF, sessionStart, true);
    int endIdx = iBarShift(_Symbol, RangeTF, sessionEnd, true);
    
    if(startIdx == -1 || endIdx == -1) {
        Log("ERROR: Could not find session bars for range calculation");
        return;
    }
    
    // Ensure correct order
    int fromIdx = MathMin(startIdx, endIdx);
    int toIdx = MathMax(startIdx, endIdx);
    
    double high = -DBL_MAX;
    double low = DBL_MAX;
    
    for(int i = fromIdx; i <= toIdx; i++) {
        double h = iHigh(_Symbol, RangeTF, i);
        double l = iLow(_Symbol, RangeTF, i);
        if(h > high) high = h;
        if(l < low) low = l;
    }
    
    asianHigh = high;
    asianLow = low;
    lastAsianCalcTime = now;
    
    // Reset counters each session
    touchCountHigh = 0;
    touchCountLow = 0;
    
    currentSession.sessionStart = sessionStart;
    currentSession.sessionEnd = sessionEnd;
    currentSession.high = asianHigh;
    currentSession.low = asianLow;
    currentSession.touchesHigh = 0;
    currentSession.touchesLow = 0;
    
    // Update chart display
    if(ShowRangeLines) {
        UpdateChartLines();
    }
    
    Log(StringFormat("NEW SESSION: High=%.5f, Low=%.5f (Period: %s to %s)",
        asianHigh, asianLow,
        TimeToString(sessionStart, TIME_DATE|TIME_SECONDS),
        TimeToString(sessionEnd, TIME_DATE|TIME_SECONDS)));
}

//========== CHART DISPLAY FUNCTIONS ==========

void UpdateChartLines() {
    // Draw Asian High line
    if(ObjectFind(0, objHighLine) < 0) {
        ObjectCreate(0, objHighLine, OBJ_HLINE, 0, 0, asianHigh);
        ObjectSetInteger(0, objHighLine, OBJPROP_COLOR, HighLineColor);
        ObjectSetInteger(0, objHighLine, OBJPROP_STYLE, LineStyle);
        ObjectSetInteger(0, objHighLine, OBJPROP_WIDTH, LineWidth);
        ObjectSetString(0, objHighLine, OBJPROP_TEXT, "Asian High");
    } else {
        ObjectSetDouble(0, objHighLine, OBJPROP_PRICE, asianHigh);
    }
    
    // Draw Asian Low line
    if(ObjectFind(0, objLowLine) < 0) {
        ObjectCreate(0, objLowLine, OBJ_HLINE, 0, 0, asianLow);
        ObjectSetInteger(0, objLowLine, OBJPROP_COLOR, LowLineColor);
        ObjectSetInteger(0, objLowLine, OBJPROP_STYLE, LineStyle);
        ObjectSetInteger(0, objLowLine, OBJPROP_WIDTH, LineWidth);
        ObjectSetString(0, objLowLine, OBJPROP_TEXT, "Asian Low");
    } else {
        ObjectSetDouble(0, objLowLine, OBJPROP_PRICE, asianLow);
    }
    
    ChartRedraw();
}

void UpdateChartInfo() {
    string info = StringFormat("Asian Session: %.5f - %.5f | High Touches: %d | Low Touches: %d",
        asianHigh, asianLow, touchCountHigh, touchCountLow);
    Comment(info);
}

//========== RETEST COUNTER MODULE ==========

void CheckForRetests() {
    // Use M5 or configured TF for touch detection
    int barsToCheck = MathMin(LookbackBars, iBars(_Symbol, PERIOD_M5));
    
    static datetime lastTouchHighTime = 0;
    static datetime lastTouchLowTime = 0;
    
    double tolerance = TouchTolerancePts * _Point;
    
    for(int i = 0; i < barsToCheck; i++) {
        double high = iHigh(_Symbol, PERIOD_M5, i);
        double low = iLow(_Symbol, PERIOD_M5, i);
        datetime barTime = iTime(_Symbol, PERIOD_M5, i);
        
        // Check Asian High touch
        if(MathAbs(high - asianHigh) <= tolerance || (low <= asianHigh && high >= asianHigh)) {
            if(barTime != lastTouchHighTime) {
                touchCountHigh++;
                lastTouchHighTime = barTime;
                currentSession.touchesHigh++;
                
                Log(StringFormat("TOUCH HIGH #%d at %.5f (Asian High: %.5f)", 
                    touchCountHigh, high, asianHigh));
                
                // Alert on specific retest counts
                if(touchCountHigh == 1) {
                    AlertLog("🔔 Asian High TOUCHED (1st retest) - Monitor for continuation");
                }
                else if(touchCountHigh == 2) {
                    AlertLog("🔔 Asian High TOUCHED (2nd retest) - CONTINUATION MODE LIKELY");
                }
                else if(touchCountHigh >= 3) {
                    AlertLog(StringFormat("🔔 Asian High touched %d times - Caution: potential fake breakout", 
                        touchCountHigh));
                }
                
                UpdateChartInfo();
            }
        }
        
        // Check Asian Low touch
        if(MathAbs(low - asianLow) <= tolerance || (low <= asianLow && high >= asianLow)) {
            if(barTime != lastTouchLowTime) {
                touchCountLow++;
                lastTouchLowTime = barTime;
                currentSession.touchesLow++;
                
                Log(StringFormat("TOUCH LOW #%d at %.5f (Asian Low: %.5f)", 
                    touchCountLow, low, asianLow));
                
                // Alert on specific retest counts
                if(touchCountLow == 1) {
                    AlertLog("🔔 Asian Low TOUCHED (1st retest) - Monitor for continuation");
                }
                else if(touchCountLow == 2) {
                    AlertLog("🔔 Asian Low TOUCHED (2nd retest) - CONTINUATION MODE LIKELY");
                }
                else if(touchCountLow >= 3) {
                    AlertLog(StringFormat("🔔 Asian Low touched %d times - Caution: potential fake breakout", 
                        touchCountLow));
                }
                
                UpdateChartInfo();
            }
        }
    }
}

//========== MAIN EXPERT FUNCTIONS ==========

int OnInit() {
    Log("=== LevisFxBot Initialized ===");
    Log(StringFormat("Symbol: %s | Timeframe: %s", _Symbol, EnumToString(_Period)));
    Log(StringFormat("Asian Session: %02d:%02d - %02d:%02d (Server Time)",
        AsianStartHour, AsianStartMinute, AsianEndHour, AsianEndMinute));
    Log("MODE: Alerts-Only (No Live Trading Yet)");
    Log("Phase 1: Session Range Detection + Retest Counter");
    
    CalculateAsianRange();
    
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    Log("=== LevisFxBot Shut Down ===");
    Log(StringFormat("Reason: %s", GetUninitReasonText(reason)));
    Print("Final Session Data:");
    Print(StringFormat("  High: %.5f | Low: %.5f", currentSession.high, currentSession.low));
    Print(StringFormat("  High Touches: %d | Low Touches: %d", 
        currentSession.touchesHigh, currentSession.touchesLow));
    
    // Clean up chart objects
    if(ShowRangeLines) {
        ObjectDelete(0, objHighLine);
        ObjectDelete(0, objLowLine);
        ObjectDelete(0, objSessionBox);
    }
    Comment("");
}

void OnTick() {
    // 1. Calculate/recalculate session range if needed
    CalculateAsianRange();
    
    // 2. Check for new touches/retests
    CheckForRetests();
    
    // 3. Update chart display
    if(ShowRangeLines) {
        UpdateChartInfo();
    }
}

string GetUninitReasonText(int reason) {
    switch(reason) {
        case REASON_PROGRAM: return "Expert stopped manually";
        case REASON_REMOVE: return "Expert removed from chart";
        case REASON_RECOMPILE: return "Expert recompiled";
        case REASON_CHARTCHANGE: return "Symbol or timeframe changed";
        case REASON_CHARTCLOSE: return "Chart closed";
        case REASON_PARAMETERS: return "Input parameters changed";
        case REASON_ACCOUNT: return "Account changed";
        default: return "Unknown reason";
    }
}

//+------------------------------------------------------------------+
