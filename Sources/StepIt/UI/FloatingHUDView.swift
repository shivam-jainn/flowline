import SwiftUI
import StepItCore

public struct FloatingHUDView: View {
    @ObservedObject var coordinator = CaptureCoordinator.shared
    public var onStop: () -> Void
    
    @State private var isPulsing = false
    
    public init(onStop: @escaping () -> Void = {}) {
        self.onStop = onStop
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            // Recording Indicator Dot
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.state == .recording ? Color.red : Color.orange)
                    .frame(width: 10, height: 10)
                    .scaleEffect(coordinator.state == .recording && isPulsing ? 1.25 : 1.0)
                    .opacity(coordinator.state == .recording && isPulsing ? 0.6 : 1.0)
                    .animation(
                        coordinator.state == .recording
                            ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
                
                Text(coordinator.state == .recording ? "REC" : "PAUSED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(coordinator.state == .recording ? .red : .orange)
            }
            .padding(.leading, 4)
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))
            
            // Timer Display
            Text(formattedDuration(coordinator.recordingDuration))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            
            // Steps Badge
            HStack(spacing: 4) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 10))
                Text("\(coordinator.stepCount) \(coordinator.stepCount == 1 ? "step" : "steps")")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.15))
            .cornerRadius(12)
            .foregroundColor(.white)
            
            // Controls
            HStack(spacing: 8) {
                // Pause / Resume
                Button(action: {
                    if coordinator.state == .recording {
                        coordinator.pauseRecording()
                    } else if coordinator.state == .paused {
                        coordinator.resumeRecording()
                    }
                }) {
                    Image(systemName: coordinator.state == .recording ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help(coordinator.state == .recording ? "Pause Recording" : "Resume Recording")
                
                // Stop Button
                Button(action: {
                    onStop()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Done")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Finish Recording")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.65)
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 14, x: 0, y: 6)
        .onAppear {
            isPulsing = true
        }
    }
    
    private func formattedDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// AppKit VisualEffectBlur helper for native glassmorphism
public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    
    public init(material: NSVisualEffectView.Material = .hudWindow, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
