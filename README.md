# ⚡️ StepIt

> **Effortless step-by-step workflow capture & AI synthesis for macOS.**  
> Native Swift. Privacy-first. Multi-provider AI Gateway. Static & Animated (GIF/WebM) capture.  
> **1-Click Publishing to Interactive Web Documentation, Print-Ready PDFs, and Markdown.**

---

## 🌟 Key Features

- **Zero Friction Capture**: Start recording with one shortcut (`⌥ Space` or Menu Bar icon), perform actions in any macOS application, and click Done.
- **Ultra-Minimal Glassmorphic HUD**: A floating, draggable HUD pill displaying live recording time, pulse indicator, step counter, and quick pause/stop controls.
- **Dual Visual Capture Pipeline**:
  - **Static High-Res Snapshots**: Crisp Retina screen capture with pinpoint click indicators (outer glow, accent ring, coordinate center dot, and numbered step badges).
  - **Animated Micro-Clips (GIF & MP4)**: Rolling frame buffer capturing cursor motion, hover reveals, and click ripples using macOS native `ImageIO` and `AVAssetWriter` — **zero external dependencies**.
- **macOS Accessibility Inspection**: Automatically identifies the frontmost application, window title, target UI element role (`AXButton`, `AXLink`, `AXTextField`), and label/value under the cursor.
- **Universal AI Gateway & LLM Integration**:
  - **OpenAI-Compatible Streaming**: Pure Swift `URLSession` async SSE client compatible with OpenRouter, Portkey, LiteLLM, Cloudflare AI Gateway, and local offline models (Ollama, LM Studio).
  - **Multimodal Vision**: Encodes captured step screenshots as base64 images so vision models (Claude 3.5 Sonnet, GPT-4o, Gemini Flash, Llama 3.2 Vision) can inspect actual visual state.
  - **Templates Included**: SOP / How-To Guide, Bug Reproduction Report, Automation Script (Bash/Python/AppleScript), and Executive Summary.
- **1-Click Multi-Format Publishing Engine**:
  - 🌐 **Interactive Web Documentation**: Self-contained static site with pre-defined modern themes (*Modern Minimalist*, *Developer Dark*, *Enterprise SOP*), sticky step navigator, checklist mode with `localStorage` persistence, copy snippet buttons, and media switcher tabs (Screenshot vs Animated GIF vs Video).
  - 📄 **Print-Ready PDF Guides**: Executive SOPs rendered via Apple's native `WebKit` (`WKWebView.createPDF`) with `@media print` CSS rules, page-break management, and vector callouts.
  - 📝 **Markdown & Assets**: GitHub Flavored Markdown ready for READMEs, Notion, Confluence, or internal wikis.

---

## 🚀 Quick Start

### 1. Requirements
- macOS 14.0 (Sonoma) or macOS Sequoia
- Xcode 15+ / Command Line Tools (Swift 5.9+)

### 2. Run Headless Demo (Instant 1-Click Verification)
Generate a rich sample session, build all exports, and open the interactive documentation in your browser:
```bash
swift run stepit demo
```

### 3. CLI Commands
```bash
# Show status & macOS permissions (Screen Recording, Accessibility)
swift run stepit status

# List all recorded sessions
swift run stepit list

# Re-export any session by ID
swift run stepit export <session_id>

# Run GUI Menu Bar application
swift run stepit app
```

### 4. Build Standalone macOS App Bundle
To create a signed `.app` bundle ready to drop into `/Applications`:
```bash
./Scripts/bundle_app.sh
# Creates: .build/StepIt.app
```

---

## ⌨️ Global Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌥ Space` (Option + Space) | Toggle recording (Start / Stop & open Review window) |

---

## 🏗️ Architecture

```
StepIt
├── Sources/
│   ├── StepItCore/
│   │   ├── Model/                # StepSession, Step, Settings, MediaAssets
│   │   ├── Permissions/          # Screen Recording & Accessibility manager
│   │   ├── Capture/              # EventMonitor, AccessibilityInspector, ScreenRecorder, MicroClipRecorder, CaptureCoordinator
│   │   ├── Storage/              # SessionStore (JSON persistence, media directories)
│   │   ├── AIGateway/            # AIGatewayClient (SSE stream), CLIExecutor, MultimodalPayloadBuilder, PromptTemplates
│   │   └── Publishing/           # WebDocGenerator, PDFGenerator, MarkdownExporter, PublishingCoordinator
│   └── StepIt/
│       ├── App/                  # AppDelegate, NSStatusItem menu bar integration
│       ├── UI/                   # FloatingHUDView, FloatingHUDWindowController, ReviewWindow, SettingsView, PermissionsBannerView
│       ├── CLI/                  # CLICommands, DemoSessionGenerator
│       └── main.swift            # Entry point for dual GUI and CLI modes
├── Tests/
│   └── StepItTests/              # Full unit test suite
└── Scripts/
    └── bundle_app.sh             # Native StepIt.app packaging & ad-hoc code-signing
```

---

## 🔒 Privacy & Permissions

StepIt is 100% local by default. All screenshots, animated GIFs, videos, and metadata are saved locally on your device under:
`~/Library/Application Support/StepIt/Sessions/`

AI requests are only dispatched when you explicitly click **"Generate Documentation with AI"** in the Review window.

StepIt requires standard macOS permissions:
1. **Screen Recording**: To capture snapshots and animated clips of the workflow.
2. **Accessibility**: To inspect target UI element roles, buttons, and titles under the cursor.

---

## 📄 License
MIT License. Crafted with Swift 6 on macOS.
