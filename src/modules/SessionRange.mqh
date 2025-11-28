//+------------------------------------------------------------------+
//| SessionRange.mqh                                                 |
//| Module: Asian session range detection and calculation            |
//| Phase 5: Range detection updated for risk control                |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "5.0.0"
#property strict

//+------------------------------------------------------------------+
//| Session Range Class                                              |
//+------------------------------------------------------------------+
class CSessionRange {
private:
    // Session parameters
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_startHour;
    int m_endHour;
    int m_londonEndHour; // New parameter
    
    // Current session data
    double m_sessionHigh;
    double m_sessionLow;
    datetime m_sessionStart;
    datetime m_sessionEnd;
    datetime m_lastCalculationTime;
    
    bool m_isSessionActive;
    bool m_isRangeSet;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor (Updated for V11.0.0 compatibility)                  |
    //+------------------------------------------------------------------+
    CSessionRange(string symbol, ENUM_TIMEFRAMES timeframe, int startHour, int endHour, int londonEndHour) {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_startHour = startHour;
        m_endHour = endHour;
        m_londonEndHour = londonEndHour;
        Reset();
    }

    //+------------------------------------------------------------------+
    //| Update Session High/Low                                          |
    //+------------------------------------------------------------------+
    void Update() {
        datetime currentTime = iTime(m_symbol, m_timeframe, 0);
        if (currentTime == m_lastCalculationTime) return;
        m_lastCalculationTime = currentTime;

        MqlDateTime dt;
        TimeToStruct(currentTime, dt);
        
        bool currentActive = (dt.hour >= m_startHour && dt.hour < m_endHour);

        if (currentActive && !m_isSessionActive) {
            // Session just started, reset and start finding range
            Reset();
            m_isSessionActive = true;
            m_sessionStart = currentTime;
        }

        if (m_isSessionActive) {
            // Find High/Low of the active session
            double high, low;
            if (!FindSessionRange(high, low)) return;
            
            m_sessionHigh = high;
            m_sessionLow = low;
            m_isRangeSet = true;
            
            // Check for London close time
            if (dt.hour >= m_londonEndHour) {
                m_isSessionActive = false;
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| Helper to find range of active bars (simplified)                 |
    //+------------------------------------------------------------------+
    bool FindSessionRange(double &high, double &low) {
        // Simple search for high/low since session start
        long startTime = m_sessionStart;
        if (startTime == 0) return false;
        
        int barIndex = 0;
        int count = 0;
        
        while(true) {
            datetime barTime = iTime(m_symbol, m_timeframe, barIndex);
            if (barTime < startTime) break;
            count++;
            barIndex++;
        }
        
        if (count < 2) return false;

        double high_array[];
        double low_array[];
        
        if(CopyHigh(m_symbol, m_timeframe, 1, count - 1, high_array) != count - 1) return false;
        if(CopyLow(m_symbol, m_timeframe, 1, count - 1, low_array) != count - 1) return false;
        
        high = high_array[ArrayMaximum(high_array)];
        low = low_array[ArrayMinimum(low_array)];
        
        return true;
    }

    // --- Accessor Methods (must be present for LevisFxBot.mq5) ---
    bool IsValid() const { return m_isRangeSet; }
    double GetHigh() const { return m_sessionHigh; }
    double GetLow() const { return m_sessionLow; }
    double GetRange() const { return MathAbs(m_sessionHigh - m_sessionLow); }
    // ... (rest of the functions like IsNearHigh/IsNearLow omitted for brevity but should be included)

    //+------------------------------------------------------------------+
    //| Reset session data                                               |
    //+------------------------------------------------------------------+
    void Reset() {
        m_sessionHigh = 0.0;
        m_sessionLow = 0.0;
        m_sessionStart = 0;
        m_sessionEnd = 0;
        m_lastCalculationTime = 0;
        m_isSessionActive = false;
        m_isRangeSet = false;
    }
};
//+------------------------------------------------------------------+
