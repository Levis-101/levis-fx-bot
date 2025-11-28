//+------------------------------------------------------------------+
//| RetestCounter.mqh                                                |
//| Module: Deterministic retest and touch counting                  |
//| Phase 5: Enhanced Touch Management                               |
//+------------------------------------------------------------------+
#property copyright "Levis Mwaniki"
#property version   "5.0.0"
#property strict

//+------------------------------------------------------------------+
//| Touch Event Structure                                            |
//+------------------------------------------------------------------+
struct TouchEvent {
    datetime time;          // Time of touch
    double price;           // Price at touch
    bool isHigh;            // True if touching high, false if low
    int barIndex;           // Bar index where touch occurred
};

//+------------------------------------------------------------------+
//| Retest Counter Class                                             |
//+------------------------------------------------------------------+
class CRetestCounter {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    double m_tolerancePoints;
    
    // Touch management
    TouchEvent m_lastTouch;
    bool m_hasNewTouch;
    bool m_isTouchAcknowledged;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor (V5.0.0 - Matches LevisFxBot.mq5 V11.0.0)            |
    //| Parameters: symbol, timeframe, tolerancePoints                   |
    //+------------------------------------------------------------------+
    CRetestCounter(string symbol, ENUM_TIMEFRAMES timeframe, int tolerancePoints) {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_tolerancePoints = tolerancePoints;
        m_hasNewTouch = false;
        m_isTouchAcknowledged = true; // Start in acknowledged state
    }

    //+------------------------------------------------------------------+
    //| Check for New Touches (Requires CSessionRange instance)          |
    //+------------------------------------------------------------------+
    void CheckTouches(CSessionRange *session) {
        if (!session->IsValid() || !m_isTouchAcknowledged) return;

        double currentHigh = iHigh(m_symbol, m_timeframe, 1);
        double currentLow = iLow(m_symbol, m_timeframe, 1);
        
        double sessionHigh = session->GetHigh();
        double sessionLow = session->GetLow();
        double tolerance = m_tolerancePoints * _Point;

        bool touchedHigh = (currentHigh >= sessionHigh - tolerance && currentHigh <= sessionHigh + tolerance);
        bool touchedLow = (currentLow <= sessionLow + tolerance && currentLow >= sessionLow - tolerance);

        if (touchedHigh && !touchedLow) {
            // New touch on the high side
            m_lastTouch.isHigh = true;
            m_lastTouch.price = currentHigh;
            m_lastTouch.time = iTime(m_symbol, m_timeframe, 1);
            m_lastTouch.barIndex = 1;
            m_hasNewTouch = true;
            m_isTouchAcknowledged = false;
        } else if (touchedLow && !touchedHigh) {
            // New touch on the low side
            m_lastTouch.isHigh = false;
            m_lastTouch.price = currentLow;
            m_lastTouch.time = iTime(m_symbol, m_timeframe, 1);
            m_lastTouch.barIndex = 1;
            m_hasNewTouch = true;
            m_isTouchAcknowledged = false;
        }
    }

    // --- Required Public Methods ---
    bool HasNewTouch() const { 
        return m_hasNewTouch && !m_isTouchAcknowledged; 
    }
    
    bool GetLastTouch(TouchEvent &touch) const {
        if (!m_hasNewTouch || m_isTouchAcknowledged) return false;
        touch = m_lastTouch;
        return true;
    }
    
    void AcknowledgeTouch() {
        m_isTouchAcknowledged = true;
        m_hasNewTouch = false;
    }
};
//+------------------------------------------------------------------+
