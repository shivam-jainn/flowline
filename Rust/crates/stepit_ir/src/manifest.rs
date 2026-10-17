//! Port of `PluginManifest.swift`.
//!
//! Every capture driver, exporter and AI provider ships one; hosts assert
//! minimum versions at startup.

use serde::{Deserialize, Serialize};

/// Shared plugin manifest.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginManifest {
    /// Plugin identifier.
    pub id: String,
    /// Plugin version.
    pub version: String,
    /// Advertised capabilities.
    #[serde(default)]
    pub capabilities: Vec<String>,
    /// Minimum accepted host version.
    #[serde(default = "default_minimum_host_version")]
    pub minimum_host_version: String,
}

fn default_minimum_host_version() -> String {
    "r-m1".to_string()
}

impl PluginManifest {
    /// Build a manifest.
    pub fn new(
        id: String,
        version: String,
        capabilities: Vec<String>,
        minimum_host_version: String,
    ) -> Self {
        Self {
            id,
            version,
            capabilities,
            minimum_host_version,
        }
    }

    /// `true` when `host_version` satisfies the minimum, using numeric-aware
    /// comparison mirroring `NSString.compare(_, options: .numeric)`.
    pub fn validate_host(&self, host_version: &str) -> bool {
        compare_numeric(host_version, &self.minimum_host_version)
            != std::cmp::Ordering::Less
    }

    /// `true` when the manifest advertises `capability`.
    pub fn supports(&self, capability: &str) -> bool {
        self.capabilities.iter().any(|c| c == capability)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Token<'a> {
    Digits(&'a str),
    Other(&'a str),
}

fn tokenize(s: &str) -> Vec<Token<'_>> {
    let bytes = s.as_bytes();
    let mut tokens = Vec::new();
    let mut start = 0;
    while start < bytes.len() {
        let is_digit = bytes[start].is_ascii_digit();
        let mut end = start + 1;
        while end < bytes.len() && bytes[end].is_ascii_digit() == is_digit {
            end += 1;
        }
        let slice = &s[start..end];
        tokens.push(if is_digit {
            Token::Digits(slice)
        } else {
            Token::Other(slice)
        });
        start = end;
    }
    tokens
}

fn compare_digit_runs(a: &str, b: &str) -> std::cmp::Ordering {
    let a_trim = a.trim_start_matches('0');
    let b_trim = b.trim_start_matches('0');
    a_trim
        .len()
        .cmp(&b_trim.len())
        .then_with(|| a_trim.cmp(b_trim))
}

/// Numeric-aware string comparison (`NSString` `.numeric` semantics for
/// version strings: digit runs compare by numeric value, other text
/// compares lexicographically).
pub fn compare_numeric(a: &str, b: &str) -> std::cmp::Ordering {
    let ta = tokenize(a);
    let tb = tokenize(b);
    for pair in ta.iter().zip(tb.iter()) {
        let ord = match pair {
            (Token::Digits(x), Token::Digits(y)) => compare_digit_runs(x, y),
            (Token::Other(x), Token::Other(y)) => x.cmp(y),
            (Token::Digits(x), Token::Other(y)) => (*x).cmp(*y),
            (Token::Other(x), Token::Digits(y)) => (*x).cmp(*y),
        };
        if ord != std::cmp::Ordering::Equal {
            return ord;
        }
    }
    ta.len().cmp(&tb.len())
}
