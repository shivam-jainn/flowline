import SwiftUI
import StepItIR
import AppKit

public struct CalculatorAppView: View {
    @State private var displayValue: String = "0"
    @State private var accumulator: Double = 0
    @State private var pendingOp: String? = nil
    @State private var exchangeRate: Double = 1.08 // EUR to USD
    @State private var convertedUSD: Double = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Display Screen
            VStack(alignment: .trailing, spacing: 4) {
                Text(displayValue)
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                
                HStack {
                    Text("≈ $\(String(format: "%.2f", (Double(displayValue) ?? 0) * exchangeRate)) USD")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                    Spacer()
                    Text("EUR base")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            
            // Currency Exchange Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Exchange Rate (EUR/USD):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(String(format: "%.2f", exchangeRate))")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                Slider(value: $exchangeRate, in: 0.8...1.5, step: 0.01)
            }
            .padding(.horizontal, 4)
            
            // Numeric Keypad Grid
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    calcButton("C", color: .gray) { clear() }
                    calcButton("±", color: .gray) { toggleSign() }
                    calcButton("%", color: .gray) { applyPercent() }
                    calcButton("÷", color: .orange) { setOp("÷") }
                }
                HStack(spacing: 8) {
                    calcButton("7") { appendDigit("7") }
                    calcButton("8") { appendDigit("8") }
                    calcButton("9") { appendDigit("9") }
                    calcButton("×", color: .orange) { setOp("×") }
                }
                HStack(spacing: 8) {
                    calcButton("4") { appendDigit("4") }
                    calcButton("5") { appendDigit("5") }
                    calcButton("6") { appendDigit("6") }
                    calcButton("-", color: .orange) { setOp("-") }
                }
                HStack(spacing: 8) {
                    calcButton("1") { appendDigit("1") }
                    calcButton("2") { appendDigit("2") }
                    calcButton("3") { appendDigit("3") }
                    calcButton("+", color: .orange) { setOp("+") }
                }
                HStack(spacing: 8) {
                    calcButton("0", wide: true) { appendDigit("0") }
                    calcButton(".") { appendDot() }
                    calcButton("=", color: .orange) { evaluate() }
                }
            }
        }
        .padding(18)
        .frame(width: 320, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func calcButton(_ label: String, color: Color = Color.secondary.opacity(0.3), wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: wide ? .infinity : 60, maxHeight: 48)
                .background(color)
                .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func appendDigit(_ digit: String) {
        if displayValue == "0" {
            displayValue = digit
        } else {
            displayValue += digit
        }
    }
    
    private func appendDot() {
        if !displayValue.contains(".") {
            displayValue += "."
        }
    }
    
    private func clear() {
        displayValue = "0"
        accumulator = 0
        pendingOp = nil
    }
    
    private func toggleSign() {
        if let val = Double(displayValue) {
            displayValue = String(val * -1)
        }
    }
    
    private func applyPercent() {
        if let val = Double(displayValue) {
            displayValue = String(val / 100.0)
        }
    }
    
    private func setOp(_ op: String) {
        accumulator = Double(displayValue) ?? 0
        pendingOp = op
        displayValue = "0"
    }
    
    private func evaluate() {
        guard let op = pendingOp, let current = Double(displayValue) else { return }
        var result: Double = 0
        switch op {
        case "+": result = accumulator + current
        case "-": result = accumulator - current
        case "×": result = accumulator * current
        case "÷": result = current != 0 ? accumulator / current : 0
        default: break
        }
        displayValue = String(result)
        pendingOp = nil
    }
}
