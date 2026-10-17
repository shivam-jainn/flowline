//! `SensitiveDataDetector` + `PrivacyRedactionEngine` port
//! (`Sources/StepItPipeline/SensitiveDataDetector.swift`,
//! `PrivacyRedactionEngine.swift`).
//!
//! Every Swift `NSRegularExpression` pattern is mirrored by a hand-rolled char
//! scanner with identical semantics on the seeded corpus: `\b` boundaries,
//! greedy quantifiers with the same backtracking outcomes, `{n,}`/`{n}`
//! counts, the case-insensitive bearer rule, and the Luhn validator.
//!
//! `customPatterns` compile as case-insensitive regexes (Swift parity:
//! `NSRegularExpression(pattern:options:[.caseInsensitive])`; invalid patterns
//! match nothing, as Swift's `try?` yields no rule). Offsets are char offsets
//! (identical to UTF-16 offsets on the ASCII corpus).

use stepit_ir::{ElementRect, OcrTextItem};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MatchKind {
    OpenAIApiKey,
    AwsAccessKey,
    GithubToken,
    BearerToken,
    JsonWebToken,
    CreditCard,
    Email,
    Custom,
}

impl MatchKind {
    /// Swift `SensitiveDataMatch.Kind` raw value (used in the golden).
    pub fn swift_name(self) -> &'static str {
        match self {
            Self::OpenAIApiKey => "openAIAPIKey",
            Self::AwsAccessKey => "awsAccessKey",
            Self::GithubToken => "githubToken",
            Self::BearerToken => "bearerToken",
            Self::JsonWebToken => "jsonWebToken",
            Self::CreditCard => "creditCard",
            Self::Email => "email",
            Self::Custom => "custom",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SensitiveDataMatch {
    pub kind: MatchKind,
    pub matched_text: String,
    /// Char offsets into the scanned string.
    pub start: usize,
    pub end: usize,
}

impl SensitiveDataMatch {
    pub fn overlaps(&self, other: &Self) -> bool {
        self.start < other.end && other.start < self.end
    }
}

#[derive(Debug, Clone)]
pub struct DetectorConfig {
    pub detect_api_keys: bool,
    pub detect_credit_cards: bool,
    pub detect_emails: bool,
    pub custom_patterns: Vec<String>,
}

impl Default for DetectorConfig {
    fn default() -> Self {
        Self {
            detect_api_keys: true,
            detect_credit_cards: true,
            detect_emails: false,
            custom_patterns: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct PrivacySettings {
    pub mask_secure_input_fields: bool,
    pub enable_offline_ocr_redaction: bool,
    pub auto_redact_api_keys: bool,
    pub auto_redact_credit_cards: bool,
    pub auto_redact_emails: bool,
    pub blur_radius: f64,
    pub frosted_glass: bool,
    pub custom_regex_patterns: Vec<String>,
}

impl PrivacySettings {
    pub fn defaults() -> Self {
        Self {
            mask_secure_input_fields: true,
            enable_offline_ocr_redaction: true,
            auto_redact_api_keys: true,
            auto_redact_credit_cards: true,
            auto_redact_emails: false,
            blur_radius: 12.0,
            frosted_glass: true,
            custom_regex_patterns: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct SensitiveDataDetector {
    pub config: DetectorConfig,
}

impl SensitiveDataDetector {
    pub fn new(config: DetectorConfig) -> Self {
        Self { config }
    }

    pub fn from_privacy(p: &PrivacySettings) -> Self {
        Self {
            config: DetectorConfig {
                detect_api_keys: p.auto_redact_api_keys,
                detect_credit_cards: p.auto_redact_credit_cards,
                detect_emails: p.auto_redact_emails,
                custom_patterns: p.custom_regex_patterns.clone(),
            },
        }
    }

    /// All sensitive tokens in `text`, ordered by position and de-overlapped.
    pub fn matches(&self, text: &str) -> Vec<SensitiveDataMatch> {
        if text.is_empty() {
            return Vec::new();
        }
        let chars: Vec<char> = text.chars().collect();
        let mut found: Vec<SensitiveDataMatch> = Vec::new();
        if self.config.detect_api_keys {
            scan_openai(&chars, &mut found);
            scan_aws(&chars, &mut found);
            scan_github(&chars, &mut found);
            scan_bearer(&chars, &mut found);
            scan_jwt(&chars, &mut found);
        }
        if self.config.detect_credit_cards {
            scan_credit_cards(&chars, &mut found);
        }
        if self.config.detect_emails {
            scan_emails(&chars, &mut found);
        }
        for pattern in &self.config.custom_patterns {
            if !pattern.is_empty() {
                scan_custom(&chars, pattern, &mut found);
            }
        }

        found.sort_by(|a, b| {
            a.start.cmp(&b.start).then(b.end.cmp(&a.end))
        });

        // Keep the widest match at any overlapping span.
        let mut deduped: Vec<SensitiveDataMatch> = Vec::new();
        for m in found {
            if !deduped.iter().any(|k: &SensitiveDataMatch| k.overlaps(&m)) {
                deduped.push(m);
            }
        }
        deduped
    }

    pub fn contains_sensitive_data(&self, text: &str) -> bool {
        !self.matches(text).is_empty()
    }
}

// MARK: - Scanner primitives (`\b` over ASCII word chars)

fn is_word(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

fn left_boundary(chars: &[char], i: usize) -> bool {
    i == 0 || !is_word(chars[i - 1])
}

fn right_boundary(chars: &[char], i: usize) -> bool {
    i == chars.len() || !is_word(chars[i])
}

fn literal_at(chars: &[char], i: usize, lit: &str) -> bool {
    let l: Vec<char> = lit.chars().collect();
    i + l.len() <= chars.len() && chars[i..i + l.len()] == l[..]
}

fn literal_at_ci(chars: &[char], i: usize, lit: &str) -> bool {
    let l: Vec<char> = lit.chars().collect();
    if i + l.len() > chars.len() {
        return false;
    }
    chars[i..i + l.len()]
        .iter()
        .zip(l.iter())
        .all(|(a, b)| a.to_ascii_lowercase() == *b)
}

fn push(out: &mut Vec<SensitiveDataMatch>, kind: MatchKind, chars: &[char], s: usize, e: usize) {
    out.push(SensitiveDataMatch {
        kind,
        matched_text: chars[s..e].iter().collect(),
        start: s,
        end: e,
    });
}

fn is_alnum(c: char) -> bool {
    c.is_ascii_alphanumeric()
}

// `\bsk-[a-zA-Z0-9]{32,}\b`
fn scan_openai(chars: &[char], out: &mut Vec<SensitiveDataMatch>) {
    let n = chars.len();
    let mut i = 0;
    while i + 3 <= n {
        if left_boundary(chars, i) && literal_at(chars, i, "sk-") {
            let mut k = i + 3;
            while k < n && is_alnum(chars[k]) {
                k += 1;
            }
            if k - (i + 3) >= 32 && right_boundary(chars, k) {
                push(out, MatchKind::OpenAIApiKey, chars, i, k);
                i = k;
                continue;
            }
        }
        i += 1;
    }
}

// `\bAKIA[0-9A-Z]{16}\b`
fn scan_aws(chars: &[char], out: &mut Vec<SensitiveDataMatch>) {
    let n = chars.len();
    let mut i = 0;
    while i + 4 <= n {
        if left_boundary(chars, i) && literal_at(chars, i, "AKIA") {
            let e = i + 20;
            if e <= n
                && chars[i + 4..e].iter().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
                && right_boundary(chars, e)
            {
                push(out, MatchKind::AwsAccessKey, chars, i, e);
                i = e;
                continue;
            }
        }
        i += 1;
    }
}

// `\bgh[pousr]_[a-zA-Z0-9]{36}\b`
fn scan_github(chars: &[char], out: &mut Vec<SensitiveDataMatch>) {
    let n = chars.len();
    let mut i = 0;
    while i + 5 <= n {
        if left_boundary(chars, i)
            && chars[i] == 'g'
            && chars[i + 1] == 'h'
            && matches!(chars[i + 2], 'p' | 'o' | 'u' | 's' | 'r')
            && chars[i + 3] == '_'
            && chars[i + 4].is_ascii_alphanumeric()
        {
            let mut k = i + 4;
            while k < n && is_alnum(chars[k]) {
                k += 1;
            }
            // Fixed `{36}`: exactly 36 alnum then a boundary. A longer run
            // cannot backtrack, so it is not a match (regex parity).
            if k - (i + 4) == 36 && right_boundary(chars, k) {
                push(out, MatchKind::GithubToken, chars, i, k);
                i = k;
                continue;
            }
        }
        i += 1;
    }
}

fn is_bearer_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '-' | '.' | '_' | '~' | '+' | '/')
}

// `\bBearer\s+[a-zA-Z0-9\-\._~\+/]+=*` (case-insensitive)
fn scan_bearer(chars: &[char], out: &mut Vec<SensitiveDataMatch>) {
    let n = chars.len();
    let mut i = 0;
    while i + 6 <= n {
        if left_boundary(chars, i) && literal_at_ci(chars, i, "bearer") {
            let mut j = i + 6;
            if j < n && chars[j].is_whitespace() {
                while j < n && chars[j].is_whitespace() {
                    j += 1;
                }
                let tok = j;
                while j < n && is_bearer_char(chars[j]) {
                    j += 1;
                }
                if j > tok {
                    while j < n && chars[j] == '=' {
                        j += 1;
                    }
                    push(out, MatchKind::BearerToken, chars, i, j);
                    i = j;
                    continue;
                }
            }
        }
        i += 1;
    }
}

fn is_jwt_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '-' || c == '_'
}

// `\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b`
fn scan_jwt(chars: &[char], out: &mut Vec<SensitiveDataMatch>) {
    let n = chars.len();
    let mut i = 0;
    while i + 3 <= n {
        if left_boundary(chars, i) && literal_at(chars, i, "eyJ") {
            let mut j = i + 3;
            while j < n && is_jwt_char(chars[j]) {
                j += 1;
            }
            if j < n && chars[j] == '.' {
                let mut k = j + 1;
                while k < n && is_jwt_char(chars[k]) {
                    k += 1;
                }
                if k > j + 1 && k < n && chars[k] == '.' {
                    let mut m = k + 1;
                    while m < n && is_jwt_char(chars[m]) {
                        m += 1;
                    }
                    if m > k + 1 && right_boundary(chars, m) {
                        push(out, MatchKind::JsonWebToken, chars, i, m);
                        i = m;
                        continue;
                    }
                }
            }
        }
        i += 1;
    }
}

// `\b(?:\d{4}[ -]?){3}\d{4}\b` + Luhn
fn cc_groups(chars: &[char], pos: usize, group: usize) -> Option<usize> {
    let n = chars.len();
    let need4 = |p: usize| {
        p + 4 <= n && chars[p..p + 4].iter().all(|c| c.is_ascii_digit())
    };
    if group == 3 {
        return if need4(pos) { Some(pos + 4) } else { None };
    }
    if !need4(pos) {
        return None;
    }
    let p2 = pos + 4;
    // Greedy optional separator first (regex backtracking parity).
    if p2 < n && (chars[p2] == ' ' || chars[p2] == '-') {
        if let Some(e) = cc_groups(chars, p2 + 1, group + 1) {
            return Some(e);
        }
    }
    cc_groups(chars, p2, group + 1)
}

fn scan_credit_cards(chars: &[char], out: &mut Vec<SensitiveDataMatch>) {
    let n = chars.len();
    let mut i = 0;
    while i + 4 <= n {
        if left_boundary(chars, i) && chars[i].is_ascii_digit() {
            if let Some(e) = cc_groups(chars, i, 0) {
                if right_boundary(chars, e) {
                    let text: String = chars[i..e].iter().collect();
                    if passes_luhn(&text) {
                        push(out, MatchKind::CreditCard, chars, i, e);
                        i = e;
                        continue;
                    }
                }
            }
        }
        i += 1;
    }
}

/// Standard Luhn checksum (rejects arbitrary 16-digit numbers).
pub fn passes_luhn(candidate: &str) -> bool {
    let digits: Vec<u32> = candidate.chars().filter_map(|c| c.to_digit(10)).collect();
    if digits.len() < 13 {
        return false;
    }
    let mut sum = 0u32;
    for (offset, d) in digits.iter().rev().enumerate() {
        if !offset.is_multiple_of(2) {
            let doubled = d * 2;
            sum += if doubled > 9 { doubled - 9 } else { doubled };
        } else {
            sum += d;
        }
    }
    sum.is_multiple_of(10)
}

fn is_email_local(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '%' | '+' | '-' )
}

fn is_email_domain(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '.' || c == '-'
}

// `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b`
fn scan_emails(chars: &[char], out: &mut Vec<SensitiveDataMatch>) {
    let n = chars.len();
    let mut i = 0;
    while i < n {
        if left_boundary(chars, i) && is_email_local(chars[i]) {
            let mut j = i;
            while j < n && is_email_local(chars[j]) {
                j += 1;
            }
            if j < n && chars[j] == '@' {
                let mut k = j + 1;
                while k < n && is_email_domain(chars[k]) {
                    k += 1;
                }
                if k > j + 1 {
                    // Greedy domain, backtrack over dots right-to-left for
                    // `\.[A-Za-z]{2,}` + boundary (regex parity).
                    let mut dots: Vec<usize> = (j + 1..k).filter(|&d| chars[d] == '.').collect();
                    dots.reverse();
                    let mut hit = None;
                    for d in dots {
                        let mut m = d + 1;
                        while m < n && chars[m].is_ascii_alphabetic() {
                            m += 1;
                        }
                        if m - (d + 1) >= 2 && right_boundary(chars, m) {
                            hit = Some(m);
                            break;
                        }
                    }
                    if let Some(e) = hit {
                        push(out, MatchKind::Email, chars, i, e);
                        i = e;
                        continue;
                    }
                }
            }
        }
        i += 1;
    }
}

// Custom patterns: case-insensitive regexes (Swift parity —
// `NSRegularExpression(pattern, [.caseInsensitive])`; an invalid pattern
// compiles to no rule, matching Swift's `try?` guard).
fn scan_custom(chars: &[char], pattern: &str, out: &mut Vec<SensitiveDataMatch>) {
    let Ok(re) = regex::RegexBuilder::new(pattern)
        .case_insensitive(true)
        .build()
    else {
        return;
    };
    let text: String = chars.iter().collect();
    // Byte → char index map (regex reports byte offsets; matches carry char
    // offsets, identical to UTF-16 offsets on the ASCII corpus).
    let mut byte_to_char = vec![0usize; text.len() + 1];
    let mut ci = 0;
    for (bi, _) in text.char_indices() {
        byte_to_char[bi] = ci;
        ci += 1;
    }
    byte_to_char[text.len()] = ci;
    for m in re.find_iter(&text) {
        let (s, e) = (byte_to_char[m.start()], byte_to_char[m.end()]);
        if s == e {
            continue;
        }
        push(out, MatchKind::Custom, chars, s, e);
    }
}

// MARK: - PrivacyRedactionEngine

#[derive(Debug, Clone)]
pub struct RedactionPlan {
    /// Normalized (`0…1`) regions to blur.
    pub regions: Vec<ElementRect>,
    /// Every sensitive token that triggered a region.
    pub matches: Vec<SensitiveDataMatch>,
}

impl RedactionPlan {
    pub fn is_redacted(&self) -> bool {
        !self.regions.is_empty()
    }
}

#[derive(Debug, Clone)]
pub struct PrivacyRedactionEngine {
    pub settings: PrivacySettings,
    detector: SensitiveDataDetector,
}

impl PrivacyRedactionEngine {
    pub fn new(settings: PrivacySettings) -> Self {
        let detector = SensitiveDataDetector::from_privacy(&settings);
        Self { settings, detector }
    }

    /// Empty when OCR redaction is disabled in settings.
    pub fn plan(&self, items: &[OcrTextItem]) -> RedactionPlan {
        if !self.settings.enable_offline_ocr_redaction {
            return RedactionPlan {
                regions: Vec::new(),
                matches: Vec::new(),
            };
        }
        let mut regions = Vec::new();
        let mut matches = Vec::new();
        for item in items {
            let item_matches = self.detector.matches(&item.text);
            if item_matches.is_empty() {
                continue;
            }
            matches.extend(item_matches);
            // OCR granularity is a text line: blur the whole observation box.
            regions.push(Self::padded(item.bounding_box));
        }
        RedactionPlan { regions, matches }
    }

    /// Small padding so glyphs are fully covered by the blur rectangle.
    pub fn padded(rect: ElementRect) -> ElementRect {
        Self::padded_ratio(rect, 0.08)
    }

    fn padded_ratio(rect: ElementRect, ratio: f64) -> ElementRect {
        let pad_x = rect.width * ratio;
        let pad_y = rect.height * ratio;
        let x = (rect.x - pad_x).max(0.0);
        let y = (rect.y - pad_y).max(0.0);
        ElementRect {
            x,
            y,
            width: (1.0 - x).min(rect.width + pad_x * 2.0),
            height: (1.0 - y).min(rect.height + pad_y * 2.0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds_sorted(det: &SensitiveDataDetector, text: &str) -> Vec<&'static str> {
        let mut k: Vec<&'static str> = det.matches(text).iter().map(|m| m.kind.swift_name()).collect();
        k.sort_unstable();
        k
    }

    #[test]
    fn golden_corpus() {
        let det = SensitiveDataDetector::default();
        assert_eq!(
            kinds_sorted(&det, "OPENAI_API_KEY=sk-1234567890abcdef1234567890abcdef12"),
            ["openAIAPIKey"]
        );
        assert_eq!(
            kinds_sorted(&det, "aws_access_key_id = AKIAIOSFODNN7EXAMPLE"),
            ["awsAccessKey"]
        );
        assert_eq!(
            kinds_sorted(&det, "token ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA end"),
            ["githubToken"]
        );
        assert_eq!(kinds_sorted(&det, "pay 4111 1111 1111 1111 now"), ["creditCard"]);
        // Emails off by default.
        assert!(kinds_sorted(&det, "mail me at jane@example.com please").is_empty());
        assert!(kinds_sorted(&det, "nothing sensitive here at all").is_empty());
    }

    #[test]
    fn matched_text_and_char_offsets() {
        let det = SensitiveDataDetector::default();
        let m = &det.matches("pay 4111 1111 1111 1111 now")[0];
        assert_eq!(m.matched_text, "4111 1111 1111 1111");
        assert_eq!((m.start, m.end), (4, 23));
        assert_eq!(&"pay 4111 1111 1111 1111 now"[m.start..m.end], "4111 1111 1111 1111");
    }

    #[test]
    fn luhn_rejects_arbitrary_numbers() {
        assert!(passes_luhn("4111 1111 1111 1111"));
        assert!(passes_luhn("4111111111111111"));
        assert!(!passes_luhn("4111 1111 1111 1112"));
        assert!(!passes_luhn("1234"));
    }

    #[test]
    fn bearer_and_jwt() {
        let det = SensitiveDataDetector::default();
        let b = det.matches("auth Bearer abcDEF123-._~+/==");
        assert_eq!(b.len(), 1);
        assert_eq!(b[0].kind, MatchKind::BearerToken);
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c";
        let j = det.matches(jwt);
        assert_eq!(j.len(), 1);
        assert_eq!(j[0].kind, MatchKind::JsonWebToken);
        assert_eq!(j[0].matched_text, jwt);
    }

    #[test]
    fn widest_match_wins_overlap() {
        // A bearer token embedding an sk-… key reports once (the widest).
        let det = SensitiveDataDetector::default();
        let text = "Bearer sk-1234567890abcdef1234567890abcdef12";
        let m = det.matches(text);
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].kind, MatchKind::BearerToken);
    }

    #[test]
    fn emails_when_enabled() {
        let det = SensitiveDataDetector::new(DetectorConfig {
            detect_emails: true,
            ..DetectorConfig::default()
        });
        let m = det.matches("mail me at jane@example.com please");
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].kind, MatchKind::Email);
        assert_eq!(m[0].matched_text, "jane@example.com");
    }

    #[test]
    fn disabled_categories_match_nothing() {
        let det = SensitiveDataDetector::new(DetectorConfig {
            detect_api_keys: false,
            detect_credit_cards: false,
            detect_emails: false,
            custom_patterns: Vec::new(),
        });
        assert!(!det.contains_sensitive_data("sk-1234567890abcdef1234567890abcdef12"));
        assert!(!det.contains_sensitive_data("pay 4111 1111 1111 1111 now"));
    }

    #[test]
    fn plan_blurs_only_sensitive_lines() {
        let engine = PrivacyRedactionEngine::new(PrivacySettings::defaults());
        let items = vec![
            OcrTextItem::new("hello", ElementRect::new(0.0, 0.0, 0.5, 0.1)),
            OcrTextItem::new(
                "pay 4111 1111 1111 1111 now",
                ElementRect::new(0.1, 0.1, 0.5, 0.1),
            ),
        ];
        let plan = engine.plan(&items);
        assert!(plan.is_redacted());
        assert_eq!(plan.regions.len(), 1);
        assert_eq!(plan.matches.len(), 1);
        // padded(0.1,0.1,0.5,0.1,0.08): padX=0.04 padY=0.008 →
        // (0.06, 0.092, 0.58, 0.116).
        let r = plan.regions[0];
        assert!((r.x - 0.06).abs() < 1e-12);
        assert!((r.y - 0.092).abs() < 1e-12);
        assert!((r.width - 0.58).abs() < 1e-12);
        assert!((r.height - 0.116).abs() < 1e-12);
    }

    #[test]
    fn plan_empty_when_disabled() {
        let mut s = PrivacySettings::defaults();
        s.enable_offline_ocr_redaction = false;
        let engine = PrivacyRedactionEngine::new(s);
        let items = vec![OcrTextItem::new(
            "pay 4111 1111 1111 1111 now",
            ElementRect::new(0.0, 0.0, 1.0, 1.0),
        )];
        let plan = engine.plan(&items);
        assert!(!plan.is_redacted());
        assert!(plan.regions.is_empty());
    }

    #[test]
    fn custom_patterns_are_case_insensitive_regexes() {
        let det = SensitiveDataDetector::new(DetectorConfig {
            detect_api_keys: false,
            detect_credit_cards: false,
            detect_emails: false,
            custom_patterns: vec!["secret-\\d+".to_string()],
        });
        let m = det.matches("leaked SECRET-42 today");
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].kind, MatchKind::Custom);
        assert_eq!(m[0].matched_text, "SECRET-42");
        assert_eq!((m[0].start, m[0].end), (7, 16));
    }

    #[test]
    fn custom_literal_still_matches() {
        let det = SensitiveDataDetector::new(DetectorConfig {
            detect_api_keys: false,
            detect_credit_cards: false,
            detect_emails: false,
            custom_patterns: vec!["confidential".to_string()],
        });
        assert!(det.contains_sensitive_data("this is CONFIDENTIAL ok"));
    }

    #[test]
    fn invalid_custom_pattern_matches_nothing() {
        // Swift `try? NSRegularExpression` parity: invalid regex = no rule.
        let det = SensitiveDataDetector::new(DetectorConfig {
            detect_api_keys: false,
            detect_credit_cards: false,
            detect_emails: false,
            custom_patterns: vec!["([unclosed".to_string()],
        });
        assert!(!det.contains_sensitive_data("([unclosed text here"));
    }
}
