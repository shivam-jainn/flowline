import SwiftUI
import StepItIR
import StepItCore

public struct FloatingHUDView: View {
    @ObservedObject var controller = WorkflowController.shared
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
                    .fill(controller.state == .recording ? Color.red : Color.orange)
                    .frame(width: 10, height: 10)
                    .scaleEffect(controller.state == .recording && isPulsing ? 1.25 : 1.0)
                    .opacity(controller.state == .recording && isPulsing ? 0.6 : 1.0)
                    .animation(
                        controller.state == .recording
                            ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
                
                Text(controller.state == .recording ? "REC" : "PAUSED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(controller.state == .recording ? .red : .orange)
            }
            .padding(.leading, 4)
            
            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))
            
            // Timer Display
            Text(formattedDuration(controller.recordingDuration))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            
            // Steps Badge
            HStack(spacing: 4) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 10))
                Text("\(controller.stepCount) \(controller.stepCount == 1 ? "step" : "steps")")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.15))
            .cornerRadius(12)
            .foregroundColor(.white)
            
            // Gesture Notice Badge
            if let gesture = controller.lastGestureNotice {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                    Text(gesture)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.indigo.opacity(0.6))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.indigo.opacity(0.9), lineWidth: 1)
                )
                .transition(.scale.combined(with: .opacity))
            }
            
            // Controls
            HStack(spacing: 8) {
                // Pause / Resume
                Button(action: {
                    if controller.state == .recording {
                        Task { await controller.pauseRecording() }
                    } else if controller.state == .paused {
                        Task { await controller.resumeRecording() }
                    }
                }) {
                    Image(systemName: controller.state == .recording ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help(controller.state == .recording ? "Pause Recording" : "Resume Recording")
                
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
