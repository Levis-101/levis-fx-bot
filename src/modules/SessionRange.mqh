//+------------------------------------------------------------------+
//| SessionRange.mqh                                                 |
//| Module: Asian session range detection and calculation            |
//| Phase 1: Core Detection                                          |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "1.0.0"
#property strict

//+------------------------------------------------------------------+
//| Session Range Class                                              |
//| Handles detection and calculation of trading session ranges      |
//+------------------------------------------------------------------+
class CSessionRange {
private:
    // Session parameters
    int m_startHour;
    int m_startMinute;
    int m_endHour;
    int m_endMinute;
    
    // Current session data
    double m_sessionHigh;
    double m_sessionLow;
    datetime m_sessionStart;
    datetime m_sessionEnd;
    datetime m_lastCalculationTime;
    
    // Detection settings
    ENUM_TIMEFRAMES m_timeframe;
    string m_symbol;
    bool m_isSessionActive;
    
    // Statistics
    int m_sessionCount;
    double m_avgRange;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CSessionRange(int startHour = 0, int startMin = 0, int endHour = 8, int endMin = 0) {
        m_startHour = startHour;
        m_startMinute = startMin;
        m_endHour = endHour;
        m_endMinute = endMin;
        
        m_sessionHigh = 0.0;
        m_sessionLow = 0.0;
        m_sessionStart = 0;
        m_sessionEnd = 0;
        m_lastCalculationTime = 0;
        
        m_timeframe = PERIOD_M5;
        m_symbol = _Symbol;
        m_isSessionActive = false;
        
        m_sessionCount = 0;
        m_avgRange = 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| Set session times                                               |
    //+------------------------------------------------------------------+
    void SetSessionTimes(int startHour, int startMin, int endHour, int endMin) {
        m_startHour = startHour;
        m_startMinute = startMin;
        m_endHour = endHour;
        m_endMinute = endMin;
    }
    
    //+------------------------------------------------------------------+
    //| Set timeframe for range calculation                             |
    //+------------------------------------------------------------------+
    void SetTimeframe(ENUM_TIMEFRAMES tf) {
        m_timeframe = tf;
    }
    
    //+------------------------------------------------------------------+
    //| Set symbol                                                       |
    //+------------------------------------------------------------------+
    void SetSymbol(string symbol) {
        m_symbol = symbol;
    }
    
    //+------------------------------------------------------------------+
    //| Get session start time for a given base time                    |
    //+------------------------------------------------------------------+
    datetime GetSessionStartTime(datetime baseTime) {
        MqlDateTime dt;
        TimeToStruct(baseTime, dt);
        dt.hour = m_startHour;
        dt.min = m_startMinute;
        dt.sec = 0;
        return StructToTime(dt);
    }
    
    //+------------------------------------------------------------------+
    //| Get session end time for a given base time                      |
    //+------------------------------------------------------------------+
    datetime GetSessionEndTime(datetime baseTime) {
        MqlDateTime dt;
        TimeToStruct(baseTime, dt);
        dt.hour = m_endHour;
        dt.min = m_endMinute;
        dt.sec = 0;
        datetime endTime = StructToTime(dt);
        
        // If end time is before or equal to start, it's the next day
        datetime startTime = GetSessionStartTime(baseTime);
        if(endTime <= startTime) {
            endTime += 24 * 3600; // Add 24 hours
        }
        
        return endTime;
    }
    
    //+------------------------------------------------------------------+
    //| Check if currently within session time                          |
    //+------------------------------------------------------------------+
    bool IsInSession(datetime checkTime) {
        datetime sessionStart = GetSessionStartTime(checkTime);
        datetime sessionEnd = GetSessionEndTime(checkTime);
        
        // Adjust for current day
        if(checkTime < sessionStart) {
            sessionStart -= 24 * 3600;
            sessionEnd -= 24 * 3600;
        }
        
        return (checkTime >= sessionStart && checkTime < sessionEnd);
    }
    
    //+------------------------------------------------------------------+
    //| Calculate session range (High and Low)                          |
    //+------------------------------------------------------------------+
    bool CalculateRange() {
        datetime now = TimeCurrent();
        datetime sessionStart = GetSessionStartTime(now);
        datetime sessionEnd = GetSessionEndTime(now);
        
        // If current time is before session start, use previous day's session
        if(now < sessionStart) {
            sessionStart -= 24 * 3600;
            sessionEnd -= 24 * 3600;
        }
        
        // Check if we've already calculated for this session
        if(m_lastCalculationTime >= sessionStart && m_lastCalculationTime < sessionEnd) {
            return false; // Already calculated
        }
        
        // Find bar indices for session period
        int startIdx = iBarShift(m_symbol, m_timeframe, sessionStart, true);
        int endIdx = iBarShift(m_symbol, m_timeframe, sessionEnd, true);
        
        if(startIdx == -1 || endIdx == -1) {
            Print("SessionRange ERROR: Could not find bars for session range");
            return false;
        }
        
        // Ensure correct order (oldest to newest)
        int fromIdx = MathMax(startIdx, endIdx);
        int toIdx = MathMin(startIdx, endIdx);
        
        // Calculate high and low
        double high = -DBL_MAX;
        double low = DBL_MAX;
        
        for(int i = fromIdx; i >= toIdx; i--) {
            double barHigh = iHigh(m_symbol, m_timeframe, i);
            double barLow = iLow(m_symbol, m_timeframe, i);
            
            if(barHigh > high) high = barHigh;
            if(barLow < low) low = barLow;
        }
        
        // Update session data
        m_sessionHigh = high;
        m_sessionLow = low;
        m_sessionStart = sessionStart;
        m_sessionEnd = sessionEnd;
        m_lastCalculationTime = now;
        m_isSessionActive = true;
        
        // Update statistics
        m_sessionCount++;
        double range = high - low;
        m_avgRange = ((m_avgRange * (m_sessionCount - 1)) + range) / m_sessionCount;
        
        Print(StringFormat("SessionRange: NEW SESSION calculated | High: %.5f | Low: %.5f | Range: %.5f",
            m_sessionHigh, m_sessionLow, range));
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get session high                                                |
    //+------------------------------------------------------------------+
    double GetHigh() {
        return m_sessionHigh;
    }
    
    //+------------------------------------------------------------------+
    //| Get session low                                                 |
    //+------------------------------------------------------------------+
    double GetLow() {
        return m_sessionLow;
    }
    
    //+------------------------------------------------------------------+
    //| Get session range (High - Low)                                  |
    //+------------------------------------------------------------------+
    double GetRange() {
        return m_sessionHigh - m_sessionLow;
    }
    
    //+------------------------------------------------------------------+
    //| Get session midpoint                                            |
    //+------------------------------------------------------------------+
    double GetMidpoint() {
        return (m_sessionHigh + m_sessionLow) / 2.0;
    }
    
    //+------------------------------------------------------------------+
    //| Get session start time                                          |
    //+------------------------------------------------------------------+
    datetime GetStartTime() {
        return m_sessionStart;
    }
    
    //+------------------------------------------------------------------+
    //| Get session end time                                            |
    //+------------------------------------------------------------------+
    datetime GetEndTime() {
        return m_sessionEnd;
    }
    
    //+------------------------------------------------------------------+
    //| Check if session data is valid                                  |
    //+------------------------------------------------------------------+
    bool IsValid() {
        return (m_sessionHigh > 0 && m_sessionLow > 0 && m_sessionHigh > m_sessionLow);
    }
    
    //+------------------------------------------------------------------+
    //| Get average range across all sessions                           |
    //+------------------------------------------------------------------+
    double GetAverageRange() {
        return m_avgRange;
    }
    
    //+------------------------------------------------------------------+
    //| Get total session count                                         |
    //+------------------------------------------------------------------+
    int GetSessionCount() {
        return m_sessionCount;
    }
    
    //+------------------------------------------------------------------+
    //| Check if price is near session high                             |
    //+------------------------------------------------------------------+
    bool IsNearHigh(double price, double tolerancePoints) {
        if(!IsValid()) return false;
        double tolerance = tolerancePoints * _Point;
        return MathAbs(price - m_sessionHigh) <= tolerance;
    }
    
    //+------------------------------------------------------------------+
    //| Check if price is near session low                              |
    //+------------------------------------------------------------------+
    bool IsNearLow(double price, double tolerancePoints) {
        if(!IsValid()) return false;
        double tolerance = tolerancePoints * _Point;
        return MathAbs(price - m_sessionLow) <= tolerance;
    }
    
    //+------------------------------------------------------------------+
    //| Get session info as string                                      |
    //+------------------------------------------------------------------+
    string GetInfo() {
        return StringFormat("Session: %.5f - %.5f | Range: %.5f | Time: %s to %s",
            m_sessionHigh, m_sessionLow, GetRange(),
            TimeToString(m_sessionStart, TIME_DATE|TIME_SECONDS),
            TimeToString(m_sessionEnd, TIME_DATE|TIME_SECONDS));
    }
    
    //+------------------------------------------------------------------+
    //| Reset session data                                              |
    //+------------------------------------------------------------------+
    void Reset() {
        m_sessionHigh = 0.0;
        m_sessionLow = 0.0;
        m_sessionStart = 0;
        m_sessionEnd = 0;
        m_lastCalculationTime = 0;
        m_isSessionActive = false;
    }
};

//+------------------------------------------------------------------+
