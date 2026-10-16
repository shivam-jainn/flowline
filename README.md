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

### 2. 10-Page Interactive Playground
A full-stack, 10-page component testbed with buttons, forms, range sliders, audio equalizers, and cloud toggles:
```bash
# Serve the 10-page playground locally on http://localhost:8080/
swift run stepit serve

# Or open directly in your browser
open Playground/web/index.html
```

The 10 pages included:
1. `page1_onboarding.html`: Auth, password strength indicator, role dropdown, team capacity range slider, 2FA toggle.
2. `page2_checkout.html`: E-commerce shopping cart, quantity steppers, promo discount code, shipping radios.
3. `page3_analytics.html`: KPI metric cards, timeframe filter dropdown, hourly/daily resolution buttons, alert sliders.
4. `page4_cloud.html`: Data center selector, compute vCPU & RAM sliders, NVMe storage slider, snapshots toggle.
5. `page5_media.html`: 5-band vertical parametric equalizer sliders, stereo panning fader, codec selector, master gain.
6. `page6_apigateway.html`: HTTP method selector, API key generator, JSON request payload editor, timeout slider.
7. `page7_support.html`: Severity level selector, category dropdown, rich reproduction textarea, impact slider.
8. `page8_survey.html`: Multi-step wizard, interactive 5-star rating, Likert scale NPS slider, progress bar.
9. `page9_datagrid.html`: Real-time text search filter, status filter, multi-select checkboxes, pagination buttons.
10. `page10_diagnostics.html`: Live hardware health gauges, background daemon restart buttons, real-time log streamer.

### 3. Automated End-to-End Workflow Recording
Run the automated recorder across the 10-page playground. It captures real snapshots, animated GIFs, inspects element roles, records coordinates, and generates full Web Docs, PDFs, and Markdown:
```bash
swift run stepit automate
```

### 4. Interactive Desktop Recorder CLI
Start a live workflow recording session directly from your terminal:
```bash
swift run stepit record
# Clicks on your screen are automatically captured. Press Ctrl+C to finish & export!
```

### 5. Native Mini Applications
Test StepIt against dedicated native macOS desktop applications:
```bash
# Launch native Calculator & Currency Converter mini app
swift run stepit app-calculator

# Launch native Sprint Kanban Task Board mini app
swift run stepit app-kanban

# Launch native Hardware & Resource Monitor mini app
swift run stepit app-monitor
```

### 6. AI Gateway CLI Tester
Test OpenAI-compatible streaming gateways directly in your terminal:
```bash
swift run stepit gateway "Summarize the architecture of StepIt"
```

### 7. Build Standalone macOS App Bundle
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
