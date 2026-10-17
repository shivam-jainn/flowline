import Foundation
import StepItIR

extension WebDocGenerator {
    func getThemeCSS(for theme: ThemeName) -> String {
        return """
        /* Apple & Airbnb Minimalist Design System Tokens */
        :root {
            --font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Plus Jakarta Sans", "Helvetica Neue", Arial, sans-serif;
            --font-mono: ui-monospace, "SF Mono", "JetBrains Mono", Menlo, Monaco, Consolas, monospace;
            
            /* Modern Minimalist (Apple / Airbnb Light Canvas) */
            --bg: #ffffff;
            --surface: #ffffff;
            --surface-secondary: #fbfbfd;
            --surface-tertiary: #f5f5f7;
            --surface-glass: rgba(255, 255, 255, 0.85);
            
            --border: #e5e5ea;
            --border-subtle: #f0f0f2;
            --border-hover: #d2d2d7;
            
            --text: #1d1d1f;
            --text-secondary: #6e6e73;
            --text-muted: #86868b;
            
            --primary: #0071e3;
            --primary-hover: #0077ed;
            --primary-gradient: #1d1d1f;
            
            --accent-glow: rgba(0, 113, 227, 0.08);
            --success: #34c759;
            --danger: #ff3b30;
            --warning: #ff9500;
            
            --radius-xl: 18px;
            --radius-lg: 12px;
            --radius-md: 8px;
            --radius-sm: 6px;
            --radius-pill: 9999px;
            
            --shadow-subtle: 0 1px 3px rgba(0, 0, 0, 0.03);
            --shadow-card: rgba(0, 0, 0, 0.02) 0 0 0 1px, rgba(0, 0, 0, 0.04) 0 2px 6px 0, rgba(0, 0, 0, 0.06) 0 4px 12px 0;
            --shadow-hover: 0 12px 28px -4px rgba(0, 0, 0, 0.07);
            --ease-apple: cubic-bezier(0.16, 1, 0.3, 1);
        }

        /* Developer Dark (Apple Space Titanium / Pro Display) */
        [data-theme="developer-dark"] {
            --bg: #000000;
            --surface: #121214;
            --surface-secondary: #18181b;
            --surface-tertiary: #222226;
            --surface-glass: rgba(18, 18, 20, 0.85);
            
            --border: rgba(255, 255, 255, 0.1);
            --border-subtle: rgba(255, 255, 255, 0.05);
            --border-hover: rgba(255, 255, 255, 0.22);
            
            --text: #f5f5f7;
            --text-secondary: #a1a1a6;
            --text-muted: #6e6e73;
            
            --primary: #2997ff;
            --primary-hover: #47a6ff;
            --primary-gradient: #f5f5f7;
            
            --shadow-subtle: 0 1px 3px rgba(0, 0, 0, 0.5);
            --shadow-card: 0 4px 20px rgba(0, 0, 0, 0.7);
            --shadow-hover: 0 16px 36px rgba(0, 0, 0, 0.9);
        }

        /* Enterprise SOP (Warm Editorial Canvas) */
        [data-theme="enterprise-sop"] {
            --bg: #fafaf8;
            --surface: #ffffff;
            --surface-secondary: #f4f3ef;
            --surface-tertiary: #eceae3;
            --surface-glass: rgba(250, 250, 248, 0.88);
            --border: #e2dfd5;
            --border-subtle: #eceae3;
            --border-hover: #cdc9bc;
            --text: #1a1a18;
            --text-secondary: #5c5a53;
            --text-muted: #8c897f;
            --primary: #8b5a2b;
            --primary-hover: #704214;
            --primary-gradient: #1a1a18;
            --shadow-subtle: 0 1px 3px rgba(0, 0, 0, 0.04);
            --shadow-card: 0 2px 8px rgba(0, 0, 0, 0.05);
            --shadow-hover: 0 12px 28px rgba(0, 0, 0, 0.08);
        }
        """ + commonCSS
    }
    
    var commonCSS: String {
        return """
        /* Reset & Base */
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        html {
            scroll-behavior: smooth;
        }

        body {
            font-family: var(--font-sans);
            background-color: var(--bg);
            color: var(--text);
            line-height: 1.55;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
            transition: background-color 0.2s var(--ease-apple), color 0.2s var(--ease-apple);
        }

        /* Top Progress Bar */
        #progress-bar-container {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 2px;
            background: transparent;
            z-index: 1000;
        }
        #progress-bar {
            height: 100%;
            width: 0%;
            background: var(--primary);
            transition: width 0.3s var(--ease-apple);
        }

        /* Apple / Airbnb Minimalist Sticky Header */
        .site-header {
            position: sticky;
            top: 0;
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0 28px;
            height: 52px;
            background: var(--surface-glass);
            backdrop-filter: blur(20px) saturate(180%);
            -webkit-backdrop-filter: blur(20px) saturate(180%);
            border-bottom: 1px solid var(--border);
            z-index: 500;
            transition: border-color 0.2s ease, background 0.2s ease;
        }

        .header-left {
            display: flex;
            align-items: center;
            gap: 12px;
            min-width: 0;
        }
        .brand-lockup {
            display: inline-flex;
            align-items: center;
            text-decoration: none;
            color: var(--text);
            transition: opacity 0.15s ease;
        }
        .brand-lockup:hover {
            opacity: 0.85;
        }
        .brand-logo-svg {
            height: 22px;
            width: auto;
            display: block;
        }
        .header-crumb-sep {
            color: var(--border-hover);
            font-size: 0.85rem;
            font-weight: 300;
        }
        .header-title {
            font-weight: 500;
            font-size: 0.88rem;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            max-width: 320px;
            color: var(--text-secondary);
        }

        /* Center Progress Pill */
        .header-center {
            display: flex;
            align-items: center;
        }
        .header-progress-pill {
            display: flex;
            align-items: center;
            gap: 8px;
            background: var(--surface-secondary);
            border: 1px solid var(--border);
            padding: 4px 12px;
            border-radius: var(--radius-pill);
            font-size: 0.76rem;
            font-weight: 600;
            color: var(--text-secondary);
        }
        .mini-progress-track {
            width: 44px;
            height: 4px;
            background: var(--border);
            border-radius: var(--radius-pill);
            overflow: hidden;
        }
        #mini-progress-bar {
            width: 0%;
            height: 100%;
            background: var(--text);
            transition: width 0.3s var(--ease-apple);
        }

        /* Header Action Buttons */
        .header-actions {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .action-btn {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: var(--surface);
            border: 1px solid var(--border);
            color: var(--text);
            padding: 5px 12px;
            border-radius: var(--radius-pill);
            font-family: inherit;
            font-weight: 500;
            font-size: 0.78rem;
            cursor: pointer;
            transition: all 0.15s var(--ease-apple);
        }
        .action-btn:hover {
            background: var(--surface-tertiary);
            border-color: var(--border-hover);
        }
        .action-btn:active {
            transform: scale(0.97);
        }
        .action-btn.primary-action {
            background: var(--text);
            color: var(--bg);
            border-color: var(--text);
        }
        .action-btn.primary-action:hover {
            opacity: 0.9;
        }
        .action-btn.active {
            background: var(--text);
            color: var(--bg);
            border-color: var(--text);
        }
        .action-btn.copied {
            background: var(--success);
            color: #ffffff;
            border-color: var(--success);
        }
        /* Theme Dropdown Popover */
        .theme-selector-container {
            position: relative;
        }
        .theme-menu-popover {
            position: absolute;
            top: calc(100% + 8px);
            right: 0;
            background: var(--surface);
            border: 1px solid var(--border);
            box-shadow: var(--shadow-card);
            border-radius: var(--radius-md);
            padding: 6px;
            display: flex;
            flex-direction: column;
            gap: 2px;
            min-width: 180px;
            z-index: 1001;
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
        }
        .theme-menu-popover.hidden {
            display: none !important;
        }
        .theme-option {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 8px 12px;
            border-radius: var(--radius-sm);
            border: none;
            background: transparent;
            color: var(--text);
            font-size: 12px;
            font-weight: 500;
            cursor: pointer;
            text-align: left;
            transition: all 0.15s var(--ease-apple);
            width: 100%;
        }
        .theme-option:hover {
            background: var(--surface-tertiary);
            color: var(--primary);
        }
        .theme-option.active {
            background: var(--surface-secondary);
            font-weight: 700;
            color: var(--primary);
        }
        .theme-color-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            border: 1px solid rgba(0, 0, 0, 0.15);
            flex-shrink: 0;
        }
        .minimal-dot { background: #0071e3; }
        .dark-dot { background: #121214; border-color: #555; }
        .sop-dot { background: #8b5a2b; }

        /* Print Header (Hidden on Screen) */
        .print-header {
            display: none;
        }

        /* Main Layout */
        .layout-container {
            display: flex;
            max-width: 1320px;
            margin: 0 auto;
            padding: 40px 28px 80px 28px;
            gap: 44px;
        }

        /* Minimalist Sticky Left Rail */
        .sidebar-nav {
            width: 260px;
            flex-shrink: 0;
            position: sticky;
            top: 76px;
            height: calc(100vh - 100px);
            display: flex;
            flex-direction: column;
        }
        .sidebar-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 12px;
            padding: 0 4px;
        }
        .sidebar-title {
            font-size: 0.7rem;
            font-weight: 600;
            letter-spacing: 0.08em;
            color: var(--text-muted);
            text-transform: uppercase;
        }
        .step-count-pill {
            background: var(--surface-secondary);
            border: 1px solid var(--border);
            font-size: 0.7rem;
            font-weight: 600;
            padding: 2px 7px;
            border-radius: var(--radius-pill);
            color: var(--text-secondary);
        }

        .steps-menu {
            display: flex;
            flex-direction: column;
            gap: 3px;
            overflow-y: auto;
            flex: 1;
            padding-right: 4px;
        }
        .nav-link {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 7px 10px;
            border-radius: var(--radius-sm);
            text-decoration: none;
            color: var(--text-secondary);
            font-size: 0.84rem;
            font-weight: 500;
            transition: all 0.12s ease;
        }
        .nav-link:hover {
            background: var(--surface-tertiary);
            color: var(--text);
        }
        .nav-link.active {
            background: var(--surface-tertiary);
            color: var(--text);
            font-weight: 600;
        }
        .nav-indicator {
            display: flex;
            align-items: center;
            justify-content: center;
            min-width: 20px;
        }
        .nav-num {
            font-family: var(--font-mono);
            font-size: 0.72rem;
            color: var(--text-muted);
        }
        .nav-check-svg {
            display: none;
            color: var(--success);
        }
        .nav-link.nav-done .nav-num { display: none; }
        .nav-link.nav-done .nav-check-svg { display: block; }
        .nav-body {
            display: flex;
            flex-direction: column;
            min-width: 0;
            flex: 1;
        }
        .nav-label {
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .nav-tag {
            font-size: 0.68rem;
            color: var(--text-muted);
        }

        .sidebar-footer {
            margin-top: 14px;
            padding-top: 12px;
            border-top: 1px solid var(--border);
            font-size: 0.72rem;
            color: var(--text-muted);
            display: flex;
            flex-direction: column;
            gap: 6px;
        }
        .sidebar-shortcut-hint kbd {
            background: var(--surface-secondary);
            border: 1px solid var(--border);
            padding: 1px 4px;
            border-radius: 4px;
            font-family: var(--font-mono);
            font-size: 0.68rem;
        }

        /* Main Content */
        .main-content {
            flex: 1;
            min-width: 0;
        }

        /* Minimalist Hero Section */
        .doc-hero {
            padding-bottom: 28px;
            margin-bottom: 36px;
            border-bottom: 1px solid var(--border);
        }
        .hero-top-row {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 14px;
        }
        .hero-badge {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: var(--surface-secondary);
            border: 1px solid var(--border);
            padding: 3px 9px;
            border-radius: var(--radius-pill);
            font-size: 0.74rem;
            font-weight: 600;
            color: var(--text-secondary);
        }
        .badge-dot {
            width: 6px;
            height: 6px;
            border-radius: 50%;
            background: var(--success);
        }
        .hero-subline {
            font-size: 0.76rem;
            color: var(--text-muted);
        }
        .hero-title {
            font-size: 2.2rem;
            font-weight: 700;
            letter-spacing: -0.03em;
            line-height: 1.18;
            margin-bottom: 12px;
            color: var(--text);
        }
        .doc-summary {
            font-size: 1.05rem;
            color: var(--text-secondary);
            line-height: 1.5;
            margin-bottom: 24px;
            max-width: 760px;
        }

        /* Metadata Strip */
        .metadata-strip {
            display: flex;
            flex-wrap: wrap;
            gap: 24px;
            margin-top: 20px;
        }
        .meta-strip-item {
            display: flex;
            flex-direction: column;
            gap: 2px;
        }
        .meta-strip-label {
            font-size: 0.68rem;
            font-weight: 600;
            letter-spacing: 0.06em;
            color: var(--text-muted);
            text-transform: uppercase;
        }
        .meta-strip-val {
            font-size: 0.88rem;
            font-weight: 600;
            color: var(--text);
        }

        /* Step Card */
        .step-card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: var(--radius-xl);
            padding: 28px;
            margin-bottom: 32px;
            box-shadow: var(--shadow-subtle);
            transition: all 0.2s var(--ease-apple);
        }
        .step-card:hover {
            box-shadow: var(--shadow-card);
            border-color: var(--border-hover);
        }
        .step-card.step-completed {
            border-color: var(--border);
            background: var(--surface-secondary);
        }
        .step-card.step-completed .step-title {
            color: var(--text-secondary);
        }

        /* Step Card Header */
        .step-header {
            display: flex;
            align-items: flex-start;
            gap: 16px;
            margin-bottom: 16px;
        }
        .step-header-left {
            display: flex;
            align-items: flex-start;
            gap: 14px;
            flex: 1;
        }
        .step-check-label {
            position: relative;
            cursor: pointer;
            margin-top: 2px;
            flex-shrink: 0;
        }
        .step-check {
            position: absolute;
            opacity: 0;
            cursor: pointer;
        }
        .custom-checkbox {
            width: 24px;
            height: 24px;
            border-radius: 50%;
            border: 1.5px solid var(--border-hover);
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.15s ease;
            background: transparent;
        }
        .custom-checkbox svg {
            opacity: 0;
            stroke: var(--bg);
            transform: scale(0.7);
            transition: all 0.15s ease;
        }
        .step-check:checked + .custom-checkbox {
            background: var(--text);
            border-color: var(--text);
        }
        .step-check:checked + .custom-checkbox svg {
            opacity: 1;
            transform: scale(1);
        }
        .step-header-text {
            flex: 1;
        }
        .step-top-meta {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 4px;
        }
        .step-num-tag {
            font-family: var(--font-mono);
            font-size: 0.72rem;
            font-weight: 600;
            color: var(--text-muted);
            letter-spacing: 0.04em;
        }
        .chip {
            font-size: 0.72rem;
            font-weight: 600;
            padding: 2px 7px;
            border-radius: var(--radius-sm);
        }
        .action-chip {
            background: var(--surface-tertiary);
            color: var(--text-secondary);
        }
        .app-chip {
            background: transparent;
            color: var(--text-muted);
            font-weight: 500;
        }
        .step-title {
            font-size: 1.25rem;
            font-weight: 600;
            letter-spacing: -0.015em;
            line-height: 1.35;
            color: var(--text);
        }

        /* Step Details & Inspector Data Bar */
        .step-details {
            margin-bottom: 18px;
        }
        .step-info-bar {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-bottom: 14px;
        }
        .info-pill {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 4px 10px;
            background: var(--surface-secondary);
            border: 1px solid var(--border);
            border-radius: var(--radius-sm);
            font-size: 0.78rem;
        }
        .info-pill-label {
            color: var(--text-muted);
        }
        .info-pill-val {
            font-weight: 500;
            color: var(--text);
            max-width: 300px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .info-pill-code {
            font-family: var(--font-mono);
            font-weight: 600;
            color: var(--text);
        }
        .copy-micro-btn {
            background: none;
            border: none;
            color: var(--text-muted);
            cursor: pointer;
            font-size: 0.72rem;
            padding: 0 2px;
            display: inline-flex;
            align-items: center;
            gap: 3px;
            font-family: inherit;
        }
        .copy-micro-btn:hover {
            color: var(--text);
        }

        /* Apple Style Note Callout */
        .step-callout {
            padding: 12px 16px;
            border-radius: var(--radius-md);
            margin-bottom: 16px;
            font-size: 0.88rem;
            line-height: 1.5;
            background: var(--surface-secondary);
            border: 1px solid var(--border);
        }
        .callout-title {
            font-weight: 600;
            font-size: 0.74rem;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 4px;
        }
        .callout-text {
            color: var(--text);
        }

        /* macOS Terminal / Code Window */
        .code-window-frame {
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            overflow: hidden;
            background: #0d1117;
            margin-bottom: 18px;
        }
        .code-window-titlebar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 14px;
            background: rgba(255, 255, 255, 0.04);
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
            font-size: 0.76rem;
        }
        .traffic-lights {
            display: flex;
            align-items: center;
            gap: 6px;
        }
        .traffic-dot {
            width: 9px;
            height: 9px;
            border-radius: 50%;
            display: inline-block;
        }
        .traffic-dot.close { background: #ff5f56; }
        .traffic-dot.minimize { background: #ffbd2e; }
        .traffic-dot.maximize { background: #27c93f; }

        .code-window-title {
            display: flex;
            align-items: center;
            gap: 8px;
            color: #c9d1d9;
            font-weight: 500;
        }
        .code-lang-tag {
            font-family: var(--font-mono);
            font-size: 0.68rem;
            padding: 1px 6px;
            background: rgba(255, 255, 255, 0.1);
            color: #e6edf3;
            border-radius: 4px;
        }
        .copy-code-btn {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid rgba(255, 255, 255, 0.12);
            color: #f0f6fc;
            font-size: 0.72rem;
            font-weight: 500;
            padding: 3px 8px;
            border-radius: var(--radius-sm);
            cursor: pointer;
            transition: all 0.15s ease;
        }
        .copy-code-btn:hover {
            background: rgba(255, 255, 255, 0.15);
        }
        .code-window-body {
            padding: 14px 18px;
            font-family: var(--font-mono);
            font-size: 0.84rem;
            line-height: 1.55;
            color: #e6edf3;
            overflow-x: auto;
            white-space: pre-wrap;
        }

        /* macOS Window Frame for Visual Media Captures */
        .macos-window-frame {
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            overflow: hidden;
            background: var(--surface-secondary);
        }
        .macos-titlebar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 14px;
            background: var(--surface);
            border-bottom: 1px solid var(--border);
        }
        .macos-window-title {
            font-size: 0.76rem;
            font-weight: 500;
            color: var(--text-secondary);
            max-width: 360px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        /* Apple Segmented Media Selector */
        .apple-segmented-picker {
            display: inline-flex;
            background: var(--surface-tertiary);
            padding: 2px;
            border-radius: var(--radius-sm);
            gap: 2px;
            border: 1px solid var(--border);
        }
        .segment-btn {
            background: transparent;
            border: none;
            color: var(--text-secondary);
            font-family: inherit;
            font-size: 0.72rem;
            font-weight: 600;
            padding: 3px 9px;
            border-radius: 4px;
            cursor: pointer;
            transition: all 0.12s var(--ease-apple);
        }
        .segment-btn:hover {
            color: var(--text);
        }
        .segment-btn.active {
            background: var(--surface);
            color: var(--text);
            box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
        }

        .macos-window-canvas {
            padding: 16px;
            display: flex;
            justify-content: center;
            align-items: center;
            background: var(--surface-secondary);
        }
        .media-view {
            width: 100%;
            display: flex;
            justify-content: center;
        }
        .media-view.hidden {
            display: none !important;
        }
        .media-wrapper {
            position: relative;
            max-width: 100%;
            display: flex;
            justify-content: center;
        }
        .media-wrapper img,
        .media-wrapper video {
            max-width: 100%;
            height: auto;
            border-radius: var(--radius-md);
            border: 1px solid var(--border);
            box-shadow: var(--shadow-subtle);
            display: block;
        }

        /* Clean In-Place Zoom & Focus Crop */
        .zoomable-wrapper {
            cursor: zoom-in;
            overflow: hidden;
            position: relative;
            border-radius: var(--radius-md);
        }
        .zoomable-wrapper.is-zoomed {
            cursor: zoom-out;
        }
        .zoom-target-img {
            transition: transform 0.35s cubic-bezier(0.16, 1, 0.3, 1);
            will-change: transform;
        }
        .zoom-indicator-pill {
            position: absolute;
            bottom: 12px;
            right: 12px;
            display: inline-flex;
            align-items: center;
            gap: 5px;
            padding: 4px 10px;
            background: rgba(15, 23, 42, 0.78);
            backdrop-filter: blur(8px);
            -webkit-backdrop-filter: blur(8px);
            border: 1px solid rgba(255, 255, 255, 0.15);
            border-radius: var(--radius-pill);
            color: #fff;
            font-size: 0.72rem;
            font-weight: 600;
            pointer-events: none;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
            transition: opacity 0.2s ease;
        }
        .zoomable-wrapper:hover .zoom-indicator-pill {
            background: rgba(15, 23, 42, 0.92);
        }
        .zoom-crop-wrapper {
            position: relative;
        }
        .zoom-crop-badge {
            position: absolute;
            top: 12px;
            left: 12px;
            display: inline-flex;
            align-items: center;
            gap: 5px;
            padding: 4px 10px;
            background: rgba(16, 185, 129, 0.9);
            color: #fff;
            border-radius: var(--radius-pill);
            font-size: 0.72rem;
            font-weight: 700;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        }
        .lightbox-trigger-btn {
            background: rgba(255, 255, 255, 0.08) !important;
            border: 1px solid var(--border) !important;
        }
        .lightbox-trigger-btn:hover {
            background: var(--surface) !important;
        }

        /* macOS Terminal Window Styling */
        .terminal-window-frame {
            background: #0d1117 !important;
            border: 1px solid rgba(255, 255, 255, 0.12) !important;
        }
        .terminal-titlebar {
            background: #161b22 !important;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08) !important;
        }
        .terminal-shell-badge {
            font-family: var(--font-mono);
            font-size: 0.74rem;
            font-weight: 600;
            color: #8b949e;
        }
        .terminal-body {
            padding: 16px 20px;
            background: #0d1117;
            font-family: var(--font-mono);
            font-size: 0.88rem;
            line-height: 1.6;
        }
        .terminal-line {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: 4px;
        }
        .terminal-prompt {
            color: #3fb950;
            font-weight: 700;
            user-select: none;
        }
        .terminal-cmd {
            color: #e6edf3;
            font-weight: 500;
        }
        .copy-cmd-btn {
            background: rgba(56, 189, 248, 0.15) !important;
            border: 1px solid rgba(56, 189, 248, 0.35) !important;
            color: #38bdf8 !important;
        }
        .copy-cmd-btn:hover {
            background: rgba(56, 189, 248, 0.25) !important;
        }

        /* Fullscreen Lightbox Modal */
        .lightbox-modal {
            position: fixed;
            top: 0;
            left: 0;
            width: 100vw;
            height: 100vh;
            background: rgba(0, 0, 0, 0.88);
            backdrop-filter: blur(14px);
            -webkit-backdrop-filter: blur(14px);
            z-index: 99999;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 24px;
            box-sizing: border-box;
        }
        .lightbox-modal.hidden {
            display: none !important;
        }
        .lightbox-dialog {
            width: 95vw;
            max-width: 1300px;
            height: 90vh;
            background: #0f172a;
            border: 1px solid rgba(255, 255, 255, 0.15);
            border-radius: var(--radius-lg);
            display: flex;
            flex-direction: column;
            overflow: hidden;
            box-shadow: 0 25px 60px rgba(0, 0, 0, 0.6);
        }
        .lightbox-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 20px;
            background: #1e293b;
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        }
        .lightbox-title {
            color: #f1f5f9;
            font-size: 0.92rem;
            font-weight: 600;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            max-width: 600px;
        }
        .lightbox-actions {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .lightbox-zoom-bar {
            display: inline-flex;
            align-items: center;
            background: #0f172a;
            border: 1px solid rgba(255, 255, 255, 0.15);
            border-radius: var(--radius-sm);
            padding: 2px 6px;
            gap: 6px;
            color: #94a3b8;
            font-size: 0.78rem;
            font-family: var(--font-mono);
        }
        .lightbox-btn {
            background: transparent;
            border: none;
            color: #f1f5f9;
            padding: 3px 8px;
            cursor: pointer;
            border-radius: 3px;
            font-weight: 700;
            font-size: 0.85rem;
        }
        .lightbox-btn:hover {
            background: rgba(255, 255, 255, 0.15);
        }
        .lightbox-btn.reset-btn {
            font-size: 0.72rem;
            font-family: inherit;
        }
        .lightbox-close-btn {
            background: rgba(239, 68, 68, 0.2);
            border: 1px solid rgba(239, 68, 68, 0.4);
            color: #f87171;
            padding: 4px 10px;
            border-radius: var(--radius-sm);
            cursor: pointer;
            font-weight: 700;
        }
        .lightbox-close-btn:hover {
            background: rgba(239, 68, 68, 0.4);
            color: #fff;
        }
        .lightbox-canvas {
            flex: 1;
            overflow: auto;
            display: flex;
            justify-content: center;
            align-items: center;
            background: #020617;
            padding: 20px;
            user-select: none;
        }
        .lightbox-canvas img {
            max-width: 100%;
            max-height: 100%;
            object-fit: contain;
            border-radius: var(--radius-md);
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
            transition: transform 0.2s ease;
            cursor: grab;
        }
        .lightbox-footer {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 20px;
            background: #1e293b;
            border-top: 1px solid rgba(255, 255, 255, 0.1);
            font-size: 0.78rem;
            color: #94a3b8;
        }
        .lightbox-tag {
            color: #38bdf8;
            font-family: var(--font-mono);
            font-weight: 600;
        }
        .lightbox-hint {
            color: #64748b;
        }

        /* Checklist Mode */
        body.checklist-mode-active .step-card {
            padding: 18px 24px;
        }
        body.checklist-mode-active .step-details,
        body.checklist-mode-active .macos-window-frame {
            display: none !important;
        }

        /* Footer Completion Card */
        .doc-footer {
            margin-top: 16px;
        }
        .footer-card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: var(--radius-xl);
            padding: 44px 28px;
            text-align: center;
            box-shadow: var(--shadow-subtle);
        }
        .footer-badge-icon {
            width: 44px;
            height: 44px;
            border-radius: 50%;
            background: var(--surface-tertiary);
            border: 1px solid var(--border);
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-bottom: 14px;
            color: var(--text);
        }
        .footer-title {
            font-size: 1.4rem;
            font-weight: 700;
            letter-spacing: -0.02em;
            margin-bottom: 6px;
            color: var(--text);
        }
        .footer-desc {
            color: var(--text-secondary);
            font-size: 0.95rem;
            margin-bottom: 22px;
            max-width: 460px;
            margin-left: auto;
            margin-right: auto;
        }
        .primary-btn {
            background: var(--text);
            color: var(--bg);
            border: none;
            padding: 9px 20px;
            border-radius: var(--radius-pill);
            font-weight: 600;
            font-size: 0.85rem;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            transition: all 0.15s var(--ease-apple);
        }
        .primary-btn:hover {
            opacity: 0.9;
            transform: translateY(-1px);
        }

        /* Responsive Breakpoints */
        @media (max-width: 1024px) {
            .sidebar-nav { display: none; }
            .layout-container { padding: 24px 20px; }
            .header-title { max-width: 220px; }
            .header-center { display: none; }
        }
        @media (max-width: 640px) {
            .hero-title { font-size: 1.8rem; }
            .step-card { padding: 20px; }
            .action-btn .btn-text { display: none; }
            .metadata-strip { gap: 14px; }
        }

        /* PDF Export Mode Styling (used during native headless PDF generation) */
        .pdf-export-mode .site-header,
        .pdf-export-mode .sidebar-nav,
        .pdf-export-mode .apple-segmented-picker,
        .pdf-export-mode .doc-footer,
        .pdf-export-mode #progress-bar-container,
        .pdf-export-mode .action-btn,
        .pdf-export-mode .copy-micro-btn,
        .pdf-export-mode .copy-code-btn,
        .pdf-export-mode .step-check-label,
        .pdf-export-mode .primary-btn {
            display: none !important;
        }
        .pdf-export-mode .print-header {
            display: flex !important;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border);
            padding: 12px 36px 14px 36px;
            margin-bottom: 20px;
        }
        .pdf-export-mode .print-logo {
            height: 24px;
            width: auto;
        }
        .pdf-export-mode .print-meta-right {
            font-size: 0.82rem;
            color: var(--text-muted);
            font-weight: 500;
        }
        .pdf-export-mode .layout-container {
            display: block !important;
            padding: 12px 36px 40px 36px !important;
            max-width: 100% !important;
            margin: 0 !important;
        }
        .pdf-export-mode .main-content {
            width: 100% !important;
        }
        .pdf-export-mode .media-view-gif,
        .pdf-export-mode .media-view-webm {
            display: none !important;
        }
        .pdf-export-mode .media-view-screenshot {
            display: block !important;
        }
        .pdf-export-mode .step-card {
            border: 1px solid var(--border) !important;
            box-shadow: none !important;
            margin-bottom: 24px !important;
            padding: 24px !important;
            background: #ffffff !important;
        }

        /* Native Print & PDF Styles */
        @media print {
            @page {
                size: a4 portrait;
                margin: 18mm 16mm 18mm 16mm;
            }
            body {
                background: #ffffff !important;
                color: #1d1d1f !important;
                font-size: 10pt !important;
                -webkit-print-color-adjust: exact !important;
                print-color-adjust: exact !important;
            }
            .site-header,
            .sidebar-nav,
            .apple-segmented-picker,
            .doc-footer,
            #progress-bar-container,
            .action-btn,
            .copy-micro-btn,
            .copy-code-btn,
            .step-check-label {
                display: none !important;
            }
            .print-header {
                display: flex !important;
                justify-content: space-between;
                align-items: center;
                border-bottom: 1px solid #e5e5ea;
                padding-bottom: 12px;
                margin-bottom: 24px;
            }
            .print-logo {
                height: 24px;
                width: auto;
            }
            .print-meta-right {
                font-size: 8.5pt;
                color: #6e6e73;
                font-weight: 500;
            }
            .layout-container {
                display: block !important;
                padding: 0 !important;
                max-width: 100% !important;
                margin: 0 !important;
            }
            .main-content {
                width: 100% !important;
            }
            .doc-hero {
                border-bottom: 1px solid #e5e5ea !important;
                padding-bottom: 16px !important;
                margin-bottom: 24px !important;
                page-break-after: avoid !important;
                break-after: avoid !important;
            }
            .hero-title {
                font-size: 20pt !important;
                margin-bottom: 8px !important;
            }
            .doc-summary {
                font-size: 10pt !important;
                margin-bottom: 14px !important;
            }
            .metadata-strip {
                margin-top: 12px !important;
                gap: 20px !important;
            }
            .step-card {
                page-break-inside: avoid !important;
                break-inside: avoid !important;
                border: 1px solid #e5e5ea !important;
                box-shadow: none !important;
                margin-bottom: 20px !important;
                padding: 18px !important;
                border-radius: 12px !important;
                background: #ffffff !important;
            }
            .step-title {
                font-size: 13pt !important;
            }
            .macos-window-frame {
                border: 1px solid #e5e5ea !important;
                box-shadow: none !important;
                border-radius: 8px !important;
            }
            .macos-titlebar {
                background: #fbfbfd !important;
                border-bottom: 1px solid #e5e5ea !important;
            }
            .macos-window-canvas {
                padding: 12px !important;
                background: #ffffff !important;
            }
            .media-view.hidden {
                display: none !important;
            }
            .media-view-screenshot {
                display: block !important;
            }
            .media-wrapper img {
                max-height: 380px !important;
                width: auto !important;
                max-width: 100% !important;
                border: 1px solid #e5e5ea !important;
            }
            .code-window-frame {
                border: 1px solid #e5e5ea !important;
                background: #fbfbfd !important;
            }
            .code-window-titlebar {
                background: #f5f5f7 !important;
                border-bottom: 1px solid #e5e5ea !important;
            }
            .code-window-title {
                color: #1d1d1f !important;
            }
            .code-window-body {
                color: #1d1d1f !important;
                background: #fbfbfd !important;
            }
        }
        """
    }
}
