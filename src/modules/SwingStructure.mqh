// SwingStructure.mqh
// Class for identifying swing points: Higher Highs (HH), Higher Lows (HL), Lower Lows (LL), Lower Highs (LH)

class SwingStructure {
public:
    double lastHigh;
    double lastLow;
    bool isHigherHigh;
    bool isHigherLow;
    bool isLowerHigh;
    bool isLowerLow;

    SwingStructure() {
        lastHigh = 0.0;
        lastLow = 0.0;
        isHigherHigh = false;
        isHigherLow = false;
        isLowerHigh = false;
        isLowerLow = false;
    }

    void detectSwing(double currentPrice) {
        if (currentPrice > lastHigh) {
            isHigherHigh = true;
            lastHigh = currentPrice;

            // Reset lower points when a new higher high is found
            isLowerLow = false;  
            isLowerHigh = false;  
        } else if (currentPrice < lastLow) {
            isLowerLow = true;
            lastLow = currentPrice;

            // Reset higher points when a new lower low is found
            isHigherHigh = false;  
            isHigherLow = false;  
        } else {
            if (currentPrice > lastLow) isHigherLow = true;
            if (currentPrice < lastHigh) isLowerHigh = true;
        }
    }

    void printCurrentSwing() {
        if (isHigherHigh) {
            Print("Current Swing: Higher High");
        } else if (isHigherLow) {
            Print("Current Swing: Higher Low");
        } else if (isLowerHigh) {
            Print("Current Swing: Lower High");
        } else if (isLowerLow) {
            Print("Current Swing: Lower Low");
        } else {
            Print("No significant swing detected.");
        }
    }
};