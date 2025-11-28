//+------------------------------------------------------------------+
//| RetestCounter.mqh                                                |
//| Module: Deterministic retest and touch counting                  |
//| Phase 1: Core Detection                                          |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "1.0.0"
#property strict

//+------------------------------------------------------------------+
//| Touch Event Structure                                            |
//+------------------------------------------------------------------+
struct TouchEvent {
    datetime time;          // Time of touch
    double price;           // Price at touch
    bool isHigh;           // True if touching high, false if low
    bool isWickTouch;      // True if wick touch, false if body
    int barIndex;          // Bar index where touch occurred
};

//+------------------------------------------------------------------+
//| Retest Counter Class                                             |
//| Tracks touches and retests of key price levels                   |
//+------------------------------------------------------------------+
class CRetestCounter {
private:
    // Target levels
    double m_highLevel;
    double m_lowLevel;
    
    // Touch tolerance
    double m_tolerancePoints;
    int m_minConfirmBars;
    
    // Touch counters
    int m_touchCountHigh;
    int m_touchCountLow;
    
    // Touch history
    TouchEvent m_touchesHigh[];
    TouchEvent m_touchesLow[];
    
    // Last touch tracking (to prevent double counting)
    datetime m_lastTouchHighTime;
    datetime m_lastTouchLowTime;
    
    // Settings
    ENUM_TIMEFRAMES m_timeframe;
    string m_symbol;
    int m_maxHistorySize;
    
    // Statistics
    int m_totalTouches;
    double m_avgTimeBetweenTouches;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CRetestCounter(double tolerancePts = 50, int confirmBars = 1) {
        m_tolerancePoints = tolerancePts;
        m_minConfirmBars = confirmBars;
        
        m_highLevel = 0.0;
        m_lowLevel = 0.0;
        
        m_touchCountHigh = 0;
        m_touchCountLow = 0;
        
        m_lastTouchHighTime = 0;
        m_lastTouchLowTime = 0;
        
        m_timeframe = PERIOD_M5;
        m_symbol = _Symbol;
        m_maxHistorySize = 100;
        
        m_totalTouches = 0;
        m_avgTimeBetweenTouches = 0.0;
        
        ArrayResize(m_touchesHigh, 0);
        ArrayResize(m_touchesLow, 0);
    }
    
    //+------------------------------------------------------------------+
    //| Set target levels to monitor                                    |
    //+------------------------------------------------------------------+
    void SetLevels(double highLevel, double lowLevel) {
        m_highLevel = highLevel;
        m_lowLevel = lowLevel;
    }
    
    //+------------------------------------------------------------------+
    //| Set tolerance for touch detection                               |
    //+------------------------------------------------------------------+
    void SetTolerance(double tolerancePoints) {
        m_tolerancePoints = tolerancePoints;
    }
    
    //+------------------------------------------------------------------+
    //| Set timeframe for detection                                     |
    //+------------------------------------------------------------------+
    void SetTimeframe(ENUM_TIMEFRAMES tf) {
        m_timeframe = tf;
    }
    
    //+------------------------------------------------------------------+
    //| Reset all counters (call at start of new session)              |
    //+------------------------------------------------------------------+
    void Reset() {
        m_touchCountHigh = 0;
        m_touchCountLow = 0;
        m_lastTouchHighTime = 0;
        m_lastTouchLowTime = 0;
        
        ArrayResize(m_touchesHigh, 0);
        ArrayResize(m_touchesLow, 0);
        
        Print("RetestCounter: Counters reset for new session");
    }
    
    //+------------------------------------------------------------------+
    //| Check for touches on both high and low levels                   |
    //+------------------------------------------------------------------+
    void CheckForTouches(int lookbackBars = 10) {
        if(m_highLevel == 0.0 || m_lowLevel == 0.0) {
            return; // Levels not set yet
        }
        
        double tolerance = m_tolerancePoints * _Point;
        int barsToCheck = MathMin(lookbackBars, iBars(m_symbol, m_timeframe));
        
        for(int i = 0; i < barsToCheck; i++) {
            double high = iHigh(m_symbol, m_timeframe, i);
            double low = iLow(m_symbol, m_timeframe, i);
            double open = iOpen(m_symbol, m_timeframe, i);
            double close = iClose(m_symbol, m_timeframe, i);
            datetime barTime = iTime(m_symbol, m_timeframe, i);
            
            // Check for HIGH level touch
            if(CheckHighTouch(high, low, open, close, barTime, i, tolerance)) {
                // Touch detected and recorded
            }
            
            // Check for LOW level touch
            if(CheckLowTouch(high, low, open, close, barTime, i, tolerance)) {
                // Touch detected and recorded
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| Check if bar touches high level                                 |
    //+------------------------------------------------------------------+
    bool CheckHighTouch(double high, double low, double open, double close, 
                        datetime barTime, int barIndex, double tolerance) {
        // Prevent double counting
        if(barTime == m_lastTouchHighTime) {
            return false;
        }
        
        bool isTouching = false;
        bool isWickTouch = false;
        double touchPrice = 0.0;
        
        // Check if price reached high level (including tolerance)
        if(high >= m_highLevel - tolerance && low <= m_highLevel + tolerance) {
            isTouching = true;
            touchPrice = high;
            
            // Determine if it's a wick touch or body touch
            double bodyTop = MathMax(open, close);
            if(bodyTop < m_highLevel - tolerance) {
                isWickTouch = true; // Wick only, body didn't reach
            }
        }
        
        if(isTouching) {
            m_touchCountHigh++;
            m_lastTouchHighTime = barTime;
            
            // Record touch event
            RecordTouchHigh(barTime, touchPrice, isWickTouch, barIndex);
            
            // Log the touch
            string touchType = isWickTouch ? "WICK" : "BODY";
            Print(StringFormat("RetestCounter: HIGH TOUCH #%d | Type: %s | Price: %.5f | Level: %.5f | Time: %s",
                m_touchCountHigh, touchType, touchPrice, m_highLevel, TimeToString(barTime, TIME_DATE|TIME_SECONDS)));
            
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Check if bar touches low level                                  |
    //+------------------------------------------------------------------+
    bool CheckLowTouch(double high, double low, double open, double close,
                       datetime barTime, int barIndex, double tolerance) {
        // Prevent double counting
        if(barTime == m_lastTouchLowTime) {
            return false;
        }
        
        bool isTouching = false;
        bool isWickTouch = false;
        double touchPrice = 0.0;
        
        // Check if price reached low level (including tolerance)
        if(low <= m_lowLevel + tolerance && high >= m_lowLevel - tolerance) {
            isTouching = true;
            touchPrice = low;
            
            // Determine if it's a wick touch or body touch
            double bodyBottom = MathMin(open, close);
            if(bodyBottom > m_lowLevel + tolerance) {
                isWickTouch = true; // Wick only, body didn't reach
            }
        }
        
        if(isTouching) {
            m_touchCountLow++;
            m_lastTouchLowTime = barTime;
            
            // Record touch event
            RecordTouchLow(barTime, touchPrice, isWickTouch, barIndex);
            
            // Log the touch
            string touchType = isWickTouch ? "WICK" : "BODY";
            Print(StringFormat("RetestCounter: LOW TOUCH #%d | Type: %s | Price: %.5f | Level: %.5f | Time: %s",
                m_touchCountLow, touchType, touchPrice, m_lowLevel, TimeToString(barTime, TIME_DATE|TIME_SECONDS)));
            
            return true;
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Record touch event for high level                               |
    //+------------------------------------------------------------------+
    void RecordTouchHigh(datetime time, double price, bool isWick, int barIdx) {
        int size = ArraySize(m_touchesHigh);
        ArrayResize(m_touchesHigh, size + 1);
        
        m_touchesHigh[size].time = time;
        m_touchesHigh[size].price = price;
        m_touchesHigh[size].isHigh = true;
        m_touchesHigh[size].isWickTouch = isWick;
        m_touchesHigh[size].barIndex = barIdx;
        
        m_totalTouches++;
    }
    
    //+------------------------------------------------------------------+
    //| Record touch event for low level                                |
    //+------------------------------------------------------------------+
    void RecordTouchLow(datetime time, double price, bool isWick, int barIdx) {
        int size = ArraySize(m_touchesLow);
        ArrayResize(m_touchesLow, size + 1);
        
        m_touchesLow[size].time = time;
        m_touchesLow[size].price = price;
        m_touchesLow[size].isHigh = false;
        m_touchesLow[size].isWickTouch = isWick;
        m_touchesLow[size].barIndex = barIdx;
        
        m_totalTouches++;
    }
    
    //+------------------------------------------------------------------+
    //| Get high touch count                                            |
    //+------------------------------------------------------------------+
    int GetHighTouchCount() {
        return m_touchCountHigh;
    }
    
    //+------------------------------------------------------------------+
    //| Get low touch count                                             |
    //+------------------------------------------------------------------+
    int GetLowTouchCount() {
        return m_touchCountLow;
    }
    
    //+------------------------------------------------------------------+
    //| Get total touch count                                           |
    //+------------------------------------------------------------------+
    int GetTotalTouchCount() {
        return m_touchCountHigh + m_touchCountLow;
    }
    
    //+------------------------------------------------------------------+
    //| Determine trading mode based on touch count                     |
    //+------------------------------------------------------------------+
    string GetTradingMode() {
        int totalTouches = GetTotalTouchCount();
        
        if(totalTouches == 0) {
            return "WAITING";
        }
        else if(totalTouches == 1) {
            return "FIRST_TOUCH";
        }
        else if(totalTouches == 2) {
            return "CONTINUATION_MODE"; // High probability setup
        }
        else if(totalTouches >= 3) {
            return "CAUTION_MULTIPLE"; // Potential fake breakout
        }
        
        return "UNKNOWN";
    }
    
    //+------------------------------------------------------------------+
    //| Check if continuation mode (2 touches)                          |
    //+------------------------------------------------------------------+
    bool IsContinuationMode() {
        return (GetTotalTouchCount() == 2);
    }
    
    //+------------------------------------------------------------------+
    //| Get time since last touch on high                               |
    //+------------------------------------------------------------------+
    int GetTimeSinceLastHighTouch() {
        if(m_lastTouchHighTime == 0) return -1;
        return (int)(TimeCurrent() - m_lastTouchHighTime);
    }
    
    //+------------------------------------------------------------------+
    //| Get time since last touch on low                                |
    //+------------------------------------------------------------------+
    int GetTimeSinceLastLowTouch() {
        if(m_lastTouchLowTime == 0) return -1;
        return (int)(TimeCurrent() - m_lastTouchLowTime);
    }
    
    //+------------------------------------------------------------------+
    //| Get last high touch event                                       |
    //+------------------------------------------------------------------+
    bool GetLastHighTouch(TouchEvent &touch) {
        int size = ArraySize(m_touchesHigh);
        if(size == 0) return false;
        
        touch = m_touchesHigh[size - 1];
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get last low touch event                                        |
    //+------------------------------------------------------------------+
    bool GetLastLowTouch(TouchEvent &touch) {
        int size = ArraySize(m_touchesLow);
        if(size == 0) return false;
        
        touch = m_touchesLow[size - 1];
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get info summary as string                                      |
    //+------------------------------------------------------------------+
    string GetInfo() {
        return StringFormat("Touches: High=%d | Low=%d | Total=%d | Mode=%s",
            m_touchCountHigh, m_touchCountLow, GetTotalTouchCount(), GetTradingMode());
    }
    
    //+------------------------------------------------------------------+
    //| Get detailed statistics                                         |
    //+------------------------------------------------------------------+
    string GetStatistics() {
        string stats = "=== Retest Counter Statistics ===\n";
        stats += StringFormat("High Touches: %d\n", m_touchCountHigh);
        stats += StringFormat("Low Touches: %d\n", m_touchCountLow);
        stats += StringFormat("Total Touches: %d\n", GetTotalTouchCount());
        stats += StringFormat("Trading Mode: %s\n", GetTradingMode());
        stats += StringFormat("High Level: %.5f\n", m_highLevel);
        stats += StringFormat("Low Level: %.5f\n", m_lowLevel);
        stats += "================================";
        return stats;
    }
};

//+------------------------------------------------------------------+
