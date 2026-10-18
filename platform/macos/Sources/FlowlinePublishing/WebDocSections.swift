import Foundation
import FlowlineIR

extension WebDocGenerator {
    func generateSidebarNav(session: StepSession) -> String {
        var html = ""
        for step in session.steps {
            let actionLabel = escapeHTML(step.actionDescription)
            let formattedNum = String(format: "%02d", step.index)
            let appTag = step.appName.isEmpty ? "" : "<span class=\"nav-tag\">\(escapeHTML(step.appName))</span>"
            
            html += """
            <a href="#step-card-\(step.index)" class="nav-link" id="nav-item-\(step.index)">
                <span class="nav-indicator">
                    <span class="nav-num">\(formattedNum)</span>
                    <svg class="nav-check-svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>
                </span>
                <span class="nav-body">
                    <span class="nav-label">\(actionLabel)</span>
                    \(appTag)
                </span>
            </a>
            """
        }
        return html
    }
    
    func generateHeaderMetadata(session: StepSession, settings: PublishingSettings) -> String {
        let author = settings.authorName.isEmpty ? (settings.companyName.isEmpty ? "macOS User" : settings.companyName) : settings.authorName
        let dateFormatted = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        // includeTimestamp was previously persisted but never read — now wired.
        var recordedItem = ""
        if settings.includeTimestamp {
            recordedItem = """
                    <div class="meta-strip-item">
                        <span class="meta-strip-label">RECORDED</span>
                        <span class="meta-strip-val">\(dateFormatted)</span>
                    </div>
            """
        }

        let head = """
        <div class="metadata-strip">
            <div class="meta-strip-item">
                <span class="meta-strip-label">AUTHOR</span>
                <span class="meta-strip-val">\(escapeHTML(author))</span>
            </div>
        """
        let tail = """
            <div class="meta-strip-item">
                <span class="meta-strip-label">STEPS</span>
                <span class="meta-strip-val">\(session.steps.count) verified</span>
            </div>
            <div class="meta-strip-item">
                <span class="meta-strip-label">FORMAT</span>
                <span class="meta-strip-val">\(session.mediaMode.displayName)</span>
            </div>
        </div>
        """
        if recordedItem.isEmpty {
            return head + tail
        }
        return head + recordedItem + "\n" + tail
    }

    func generateStepsHTML(session: StepSession, assetBaseURL: String, settings: PublishingSettings? = nil) -> String {
        var html = ""
        let prefix = assetURLPrefix(assetBaseURL: assetBaseURL)
        
        for step in session.steps {
            let hasScreenshot = step.assets.screenshot != nil
            let hasGif = step.assets.gif != nil
            let hasWebm = step.assets.webm != nil
            let hasZoom = step.assets.zoomCrop != nil
            let hasMedia = hasScreenshot || hasGif || hasWebm || hasZoom
            
            let defaultView: String = {
                if let pref = step.preferredMedia?.lowercased() {
                    if pref == "gif", hasGif { return "gif" }
                    if pref == "static", hasScreenshot { return "screenshot" }
                }
                return (hasGif && session.mediaMode != .staticOnly) ? "gif" : (hasScreenshot ? "screenshot" : (hasZoom ? "zoom" : "webm"))
            }()
            let actionName = actionDisplayName(step.action)
            let winTitle = step.windowTitle.isEmpty ? (step.appName.isEmpty ? "Application Window" : step.appName) : step.windowTitle
            let formattedIndex = String(format: "%02d", step.index)
            
            let coordsX = step.coordinates?.x ?? 600.0
            let coordsY = step.coordinates?.y ?? 400.0
            let pctX = min(95.0, max(5.0, (coordsX / 1200.0) * 100.0))
            let pctY = min(95.0, max(5.0, (coordsY / 800.0) * 100.0))
            let isTerminalCmd = (step.appName == "Terminal" || step.codeLanguage == "bash" || step.codeLanguage == "zsh") && step.textBlob != nil
            let keyStyle = settings?.keycapStyle ?? .mac3D
            let pointerStyle = settings?.mouseStyle ?? .mac3D
            let keycapsRow: String = {
                if step.action == .keyPress {
                    let toks = KeyComboTokens.tokensForStep(combo: step.hotkeyCombo, elementTitle: step.elementTitle)
                    guard !toks.isEmpty else { return "" }
                    let caps = KeyComboTokens.webCapsHTML(tokens: toks, style: keyStyle)
                    let label = (step.hotkeyCombo?.isEmpty == false) ? "Shortcut" : "Key"
                    return """
                    <div class="keycombo-row">
                        <span class="keycombo-label">\(label)</span>
                        <span class="keycombo">\(caps)</span>
                    </div>
                    """
                }
                if step.action == .typing, let blob = step.textBlob,
                   let toks = KeyComboTokens.typedTokens(text: blob) {
                    let caps = KeyComboTokens.webCapsHTML(tokens: toks, style: keyStyle)
                    return """
                    <div class="keycombo-row">
                        <span class="keycombo-label">Typed</span>
                        <span class="keycombo">\(caps)</span>
                    </div>
                    """
                }
                return ""
            }()
            let mouseRow: String = {
                guard step.action != .keyPress, step.action != .typing,
                      let label = KeyComboTokens.mouseLabel(action: step.action.rawValue) else { return "" }
                return """
                <div class="mouse-row \(pointerStyle.cssClass)">
                    <span class="mouse-ptr" aria-hidden="true"><svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M6 3.5 6 16.6 10.2 13.4 12.3 17.8 14.4 16.9 12.3 12.5 16.4 12.5 Z"/></svg></span>
                    <span class="mouse-label">\(label)</span>
                </div>
                """
            }()
            
            let checklistsEnabled = settings?.enableInteractiveChecklists ?? true
            var checklistHTML = ""
            if checklistsEnabled {
                checklistHTML = "<label class=\"step-check-label\" title=\"Mark step \(step.index) completed\">"
                    + "<input type=\"checkbox\" class=\"step-check\" data-step=\"\(step.index)\">"
                    + "<span class=\"custom-checkbox\">"
                    + "<svg width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\"><polyline points=\"20 6 9 17 4 12\"></polyline></svg>"
                    + "</span></label>"
            }
            let cardClass = checklistsEnabled ? "step-card" : "step-card no-checklist"
            html += "<article class=\"\(cardClass)\" id=\"step-card-\(step.index)\">"
                + "<div class=\"step-header\"><div class=\"step-header-left\">"
                + checklistHTML
                + "<div class=\"step-header-text\">"
                + "<div class=\"step-top-meta\">"
                + "<span class=\"step-num-tag\">STEP \(formattedIndex)</span>"
                + "<span class=\"chip action-chip\">\(actionName)</span>"
                + (step.appName.isEmpty ? "" : "<span class=\"chip app-chip\">\(escapeHTML(step.appName))</span>")
                + "</div>"
                + "<h2 class=\"step-title\">\(escapeHTML(step.actionDescription))</h2>"
                + "</div></div></div>"
            html += """
                <!-- Step Inspector Data Bar -->
                <div class="step-details">
                    <div class="step-info-bar">
                        \(step.windowTitle.isEmpty ? "" : """
                        <div class="info-pill">
                            <span class="info-pill-label">Window</span>
                            <span class="info-pill-val" title="\(escapeHTML(step.windowTitle))">\(escapeHTML(step.windowTitle))</span>
                        </div>
                        """)
                        \(step.elementTitle != nil ? """
                        <div class="info-pill highlight-pill">
                            <span class="info-pill-label">Target</span>
                            <code class="info-pill-code">\(escapeHTML(step.elementTitle!))</code>
                            <button class="copy-micro-btn" onclick="copyText('\(escapeJS(step.elementTitle!))', this)" title="Copy Target Element">
                                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                                <span>Copy</span>
                            </button>
                        </div>
                        """ : "")
                        \(step.coordinates != nil ? """
                        <div class="info-pill">
                            <span class="info-pill-label">Coordinates</span>
                            <code class="info-pill-code">(\(Int(coordsX)), \(Int(coordsY)))</code>
                        </div>
                        """ : "")
                    </div>
                    \(keycapsRow)\(mouseRow)

                    <!-- Apple Style User Note Callout -->
                    \(step.userNotes != nil && !step.userNotes!.isEmpty ? """
                    <div class="step-callout note-callout">
                        <div class="callout-body">
                            <div class="callout-title">Note</div>
                            <div class="callout-text">\(escapeHTML(step.userNotes!))</div>
                        </div>
                    </div>
                    """ : "")

                    <!-- macOS Terminal / Code Snippet Card -->
                    \(step.textBlob != nil && !step.textBlob!.isEmpty ? """
                    <div class="code-window-frame \(isTerminalCmd ? "terminal-window-frame" : "") code-blob-container">
                        <div class="code-window-titlebar terminal-titlebar code-blob-header">
                            <div class="traffic-lights">
                                <span class="traffic-dot close"></span>
                                <span class="traffic-dot minimize"></span>
                                <span class="traffic-dot maximize"></span>
                            </div>
                            <div class="code-window-title code-blob-meta">
                                \(isTerminalCmd ? "<span class=\"terminal-shell-badge\">zsh — 80×24</span><span class=\"code-lang-tag\">CLI Command</span>" : "<span class=\"code-label\">\(step.isCode ? "Code Snippet" : "Captured Text")</span>\(step.codeLanguage != nil ? "<span class=\"code-lang-tag\">\(escapeHTML(step.codeLanguage!))</span>" : "")")
                            </div>
                            <button class="copy-code-btn \(isTerminalCmd ? "copy-cmd-btn" : "")" onclick="copyText('\(escapeJS(step.textBlob!))', this)">
                                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                                <span>\(isTerminalCmd ? "Copy Command" : "Copy")</span>
                            </button>
                        </div>
                        \(isTerminalCmd ? """
                        <div class="code-window-body terminal-body">
                            <div class="terminal-line"><span class="terminal-prompt">$ </span><span class="terminal-cmd">\(escapeHTML(step.textBlob!))</span></div>
                        </div>
                        """ : """
                        <pre class="code-window-body code-blob-body"><code>\(escapeHTML(step.textBlob!))</code></pre>
                        """)
                    </div>
                    """ : "")
                </div>

                <!-- macOS Framed Visual Media Viewport -->
                \(hasMedia ? """
                <div class="macos-window-frame">
                    <div class="macos-titlebar">
                        <div class="traffic-lights">
                            <span class="traffic-dot close"></span>
                            <span class="traffic-dot minimize"></span>
                            <span class="traffic-dot maximize"></span>
                        </div>
                        <div class="macos-window-title" title="\(escapeHTML(winTitle))">
                            <span>\(escapeHTML(winTitle))</span>
                        </div>
                        
                        <!-- Apple Segmented Media & Clean Zoom Selector — text-only, no emoji -->
                        <div class="apple-segmented-picker">
                            \(hasScreenshot ? "<button class=\"segment-btn \(defaultView == "screenshot" ? "active" : "")\" data-mode=\"screenshot\" onclick=\"switchMediaView(\(step.index), 'screenshot')\">Overview</button>" : "")
                            \(hasZoom ? "<button class=\"segment-btn \(defaultView == "zoom" ? "active" : "")\" data-mode=\"zoom\" onclick=\"switchMediaView(\(step.index), 'zoom')\">Zoom (2.4×)</button>" : "")
                            \(hasGif ? "<button class=\"segment-btn \(defaultView == "gif" ? "active" : "")\" data-mode=\"gif\" onclick=\"switchMediaView(\(step.index), 'gif')\">Animation</button>" : "")
                            \(hasWebm ? "<button class=\"segment-btn\" data-mode=\"webm\" onclick=\"switchMediaView(\(step.index), 'webm')\">Video</button>" : "")
                            \(hasScreenshot ? "<button class=\"segment-btn lightbox-trigger-btn\" onclick=\"openLightbox('\(prefix)\(step.assets.screenshot!)', '\(escapeJS(step.actionDescription))', \(Int(coordsX)), \(Int(coordsY)))\" title=\"Open Fullscreen Retina Zoom Lightbox\"><span>Lightbox</span></button>" : "")
                        </div>
                    </div>

                    <div class="macos-window-canvas">
                        \(hasScreenshot ? """
                        <div class=\"media-view media-view-screenshot \(defaultView == "screenshot" ? "" : "hidden")\">
                            <div class=\"media-wrapper zoomable-wrapper\" id=\"zoom-wrapper-\(step.index)\" onclick=\"toggleInPlaceZoom(\(step.index), \(pctX), \(pctY))\" title=\"Click to toggle clean zoom at target coordinates\">
                                <img src=\"\(prefix)\(step.assets.screenshot!)\" alt=\"\(escapeHTML(step.actionDescription))\" loading=\"lazy\" id=\"zoom-img-\(step.index)\" class=\"zoom-target-img\">
                                <div class=\"zoom-indicator-pill\">
                                    <svg width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\"><circle cx=\"11\" cy=\"11\" r=\"8\"></circle><line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"></line><line x1=\"11\" y1=\"8\" x2=\"11\" y2=\"14\"></line><line x1=\"8\" y1=\"11\" x2=\"14\" y2=\"11\"></line></svg>
                                    <span>Click to Zoom</span>
                                </div>
                            </div>
                        </div>
                        """ : "")

                        \(hasZoom ? """
                        <div class=\"media-view media-view-zoom \(defaultView == "zoom" ? "" : "hidden")\">
                            <div class=\"media-wrapper zoom-crop-wrapper\">
                                <img src=\"\(prefix)\(step.assets.zoomCrop!)\" alt=\"2.4x Zoom of \(escapeHTML(step.actionDescription))\" loading=\"lazy\">
                                <div class=\"zoom-crop-badge\">
                                    <svg width=\"12\" height=\"12\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.2\"><circle cx=\"11\" cy=\"11\" r=\"8\"></circle><line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"></line><line x1=\"11\" y1=\"8\" x2=\"11\" y2=\"14\"></line><line x1=\"8\" y1=\"11\" x2=\"14\" y2=\"11\"></line></svg>
                                    <span>2.4× Focused Live DOM Crop</span>
                                </div>
                            </div>
                        </div>
                        """ : "")

                        \(hasGif ? """
                        <div class=\"media-view media-view-gif \(defaultView == "gif" ? "" : "hidden")\">
                            <div class=\"media-wrapper\">
                                <img src=\"\(prefix)\(step.assets.gif!)\" alt=\"Animated \(escapeHTML(step.actionDescription))\" loading=\"lazy\">
                            </div>
                        </div>
                        """ : "")

                        \(hasWebm ? """
                        <div class=\"media-view media-view-webm hidden\">
                            <div class=\"media-wrapper\">
                                <video src=\"\(prefix)\(step.assets.webm!)\" autoplay loop muted playsinline controls></video>
                            </div>
                        </div>
                        """ : "")
                    </div>
                </div>
                """ : "")
            </article>
            """
        }
        return html
    }
}
