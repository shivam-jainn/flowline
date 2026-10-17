import SwiftUI
import AppKit

public struct SystemMonitorAppView: View {
    @State private var cpuUsage: Double = 14.2
    @State private var ramUsageGB: Double = 8.6
    @State private var networkBandwidthMB: Double = 2.4
    @State private var isMonitoring = true
    
    @State private var activeProcesses = [
        ("StepIt", "PID 4910", "1.2% CPU", "180 MB"),
        ("Safari", "PID 1204", "8.4% CPU", "920 MB"),
        ("Terminal", "PID 892", "0.4% CPU", "64 MB"),
        ("WindowServer", "PID 198", "4.1% CPU", "340 MB"),
        ("Ollama", "PID 5821", "0.1% CPU", "4,200 MB")
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Live Stats Cards
            HStack(spacing: 12) {
                metricBox(title: "CPU Load", value: "\(String(format: "%.1f", cpuUsage))%", color: .blue)
                metricBox(title: "RAM In-Use", value: "\(String(format: "%.1f", ramUsageGB)) GB", color: .purple)
                metricBox(title: "Network I/O", value: "\(String(format: "%.1f", networkBandwidthMB)) MB/s", color: .green)
            }
            
            // Process Table
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top Active Processes")
                        .font(.headline)
                    Spacer()
                    Button("Simulate Spike") {
                        simulateSpike()
                    }
                    .controlSize(.small)
                }
                
                VStack(spacing: 6) {
                    ForEach(activeProcesses, id: \.1) { proc in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(proc.0).fontWeight(.semibold)
                                Text(proc.1).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(proc.2).font(.system(size: 11, design: .monospaced))
                            Text(proc.3).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).frame(width: 70, alignment: .trailing)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
            
            HStack {
                Button(isMonitoring ? "Pause Monitor" : "Resume Monitor") {
                    isMonitoring.toggle()
                }
                Spacer()
                Button("Clear Memory Cache") {
                    ramUsageGB = max(4.0, ramUsageGB - 2.1)
                }
            }
        }
        .padding(18)
        .frame(width: 480, height: 420)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func metricBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title2).fontWeight(.bold).foregroundColor(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func simulateSpike() {
        cpuUsage = Double.random(in: 45...88)
        ramUsageGB = Double.random(in: 11...14)
        networkBandwidthMB = Double.random(in: 8...24)
    }
}
