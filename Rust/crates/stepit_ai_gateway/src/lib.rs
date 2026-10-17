//! StepIt AI gateway — PURE part port (R/M2-06).
//!
//! Swift twins: `Sources/StepItAIGateway/PromptTemplates.swift`,
//! `MultimodalPayloadBuilder.swift` (model building only),
//! `GatewayProvider.swift`, `GatewaySettings.swift`.
//!
//! The PURE part is prompt templates + payload models. Network transport
//! stays host-provided via [`Transport`]; image downsampling stays native
//! ([`payload::build_request`] takes pre-encoded base64 strings).
//!

pub mod payload;
pub mod prompts;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error("transport error: {0}")]
    Transport(String),
    #[error("gateway error: {0}")]
    Gateway(String),
}

/// Host-provided network transport (sync). Pure crate performs no I/O.
pub trait Transport {
    fn post_json(&self, url: &str, headers: &[(&str, &str)], body: &str) -> Result<String, Error>;
}

pub use stepit_ir::{ActionType, ScreenCoordinates, Step, StepSession};

// ---------------------------------------------------------------------------
// Gateway models (Swift twin: GatewayProvider.swift / GatewaySettings.swift)
// ---------------------------------------------------------------------------

/// Mirror of `GatewayProviderType` (raw values identical).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum GatewayProviderType {
    #[serde(rename = "openrouter")]
    OpenRouter,
    #[serde(rename = "custom_openai")]
    CustomOpenAI,
    #[serde(rename = "ollama")]
    Ollama,
    #[serde(rename = "lm_studio")]
    LmStudio,
    #[serde(rename = "cli")]
    Cli,
}

impl GatewayProviderType {
    #[must_use]
    pub const fn display_name(self) -> &'static str {
        match self {
            Self::OpenRouter => "OpenRouter (Cloud Gateway)",
            Self::CustomOpenAI => "OpenAI / Portkey / LiteLLM",
            Self::Ollama => "Ollama (Local Offline)",
            Self::LmStudio => "LM Studio (Local Offline)",
            Self::Cli => "Local CLI Pipeline",
        }
    }

    /// Mirror of `GatewayProviderType.defaultBaseURL`.
    #[must_use]
    pub const fn default_base_url(self) -> &'static str {
        match self {
            Self::OpenRouter => "https://openrouter.ai/api/v1",
            Self::CustomOpenAI => "https://api.openai.com/v1",
            Self::Ollama => "http://localhost:11434/v1",
            Self::LmStudio => "http://localhost:1234/v1",
            Self::Cli => "",
        }
    }

    /// Mirror of `GatewayProviderType.defaultModel`.
    #[must_use]
    pub const fn default_model(self) -> &'static str {
        match self {
            Self::OpenRouter => "anthropic/claude-3.5-sonnet",
            Self::CustomOpenAI => "gpt-4o",
            Self::Ollama => "llama3.2-vision",
            Self::LmStudio => "meta-llama-3.2-11b-vision-instruct",
            Self::Cli => "ollama run llama3.2-vision",
        }
    }
}

/// Mirror of `GatewaySettings` (Swift `Codable` keys preserved verbatim).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct GatewaySettings {
    pub provider: GatewayProviderType,
    #[serde(rename = "baseURL")]
    pub base_url: String,
    #[serde(rename = "apiKey")]
    pub api_key: String,
    pub model: String,
    #[serde(rename = "visionEnabled")]
    pub vision_enabled: bool,
    pub temperature: f64,
}

impl Default for GatewaySettings {
    /// Mirrors Swift's `GatewaySettings.init` defaults (openRouter).
    fn default() -> Self {
        Self::for_provider(GatewayProviderType::OpenRouter)
    }
}

impl GatewaySettings {
    /// Defaults for a provider: per-provider base URL + model, `apiKey ""`,
    /// `visionEnabled true`, `temperature 0.2` — mirroring Swift `init`.
    #[must_use]
    pub fn for_provider(provider: GatewayProviderType) -> Self {
        Self {
            base_url: provider.default_base_url().to_owned(),
            model: provider.default_model().to_owned(),
            provider,
            api_key: String::new(),
            vision_enabled: true,
            temperature: 0.2,
        }
    }
}

/// Defaults for a provider — mirrors Swift `init` + per-provider
/// `defaultBaseURL` / `defaultModel`.
#[must_use]
pub fn settings_for_provider(provider: GatewayProviderType) -> GatewaySettings {
    GatewaySettings::for_provider(provider)
}

/// Mirror of `GatewayRequest` (pure model; payload bytes stay opaque).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GatewayRequest {
    pub prompt: String,
    pub model: String,
    pub payload: Option<Vec<u8>>,
}

/// Mirror of `GatewayResponse`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GatewayResponse {
    pub text: String,
}
