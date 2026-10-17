//! Payload models — port of `MultimodalPayloadBuilder.swift` MODEL BUILDING.
//!
//! The image downsample itself is NATIVE (AppKit/ImageIO in Swift) and lives
//! outside this crate: [`build_request`] takes pre-encoded base64 PNG strings
//! (`images`) plus pre-resolved media decisions. Serde keys mirror the Swift
//! `Codable` keys EXACTLY (`image_url`, not `imageUrl`); `None` fields are
//! omitted just like Swift's synthesised `encodeIfPresent`.

use crate::{GatewaySettings, prompts};
use stepit_ir::StepSession;
use crate::prompts::DocumentationStyle;

/// Mirror of Swift `ImageURLPayload` (`{"url": ...}`).
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ImageUrlPayload {
    pub url: String,
}

/// Mirror of Swift `MultimodalContentPart`.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct MultimodalContentPart {
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_url: Option<ImageUrlPayload>,
}

impl MultimodalContentPart {
    /// Mirror of `MultimodalContentPart.init(text:)`.
    #[must_use]
    pub fn text(text: impl Into<String>) -> Self {
        Self {
            kind: "text".to_owned(),
            text: Some(text.into()),
            image_url: None,
        }
    }

    /// Mirror of `MultimodalContentPart.init(imageURL:)`.
    #[must_use]
    pub fn image_url(url: impl Into<String>) -> Self {
        Self {
            kind: "image_url".to_owned(),
            text: None,
            image_url: Some(ImageUrlPayload { url: url.into() }),
        }
    }
}

/// Mirror of Swift `ChatMessagePayload`.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ChatMessagePayload {
    pub role: String,
    pub content: Vec<MultimodalContentPart>,
}

impl ChatMessagePayload {
    /// Mirror of `ChatMessagePayload.init(role:text:)`.
    #[must_use]
    pub fn from_text(role: impl Into<String>, text: impl Into<String>) -> Self {
        Self {
            role: role.into(),
            content: vec![MultimodalContentPart::text(text)],
        }
    }
}

/// Mirror of Swift `ChatCompletionRequest`.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ChatCompletionRequest {
    pub model: String,
    pub messages: Vec<ChatMessagePayload>,
    pub temperature: f64,
    pub stream: bool,
}

/// Pure mirror of `MultimodalPayloadBuilder.buildRequest`.
///
/// `images` maps 1-based step index → pre-encoded base64 PNG (the NATIVE
/// downsample output). Vision branching mirrors Swift: gated on
/// `settings.vision_enabled`; steps without a screenshot asset — or without a
/// supplied image (mirrors Swift's silent skip of unreadable files) — are
/// skipped. Caption text and part order (text prompt, then per-step
/// caption + data-URL pairs) match Swift exactly. `stream` is hardcoded
/// `true`, mirroring Swift.
#[must_use]
pub fn build_request(
    session: &StepSession,
    settings: &GatewaySettings,
    style: DocumentationStyle,
    custom_instructions: Option<&str>,
    recorded_at_display: &str,
    images: &[(i64, &str)],
) -> ChatCompletionRequest {
    let system = prompts::system_prompt(style);
    let text_prompt = prompts::user_prompt(session, style, custom_instructions, recorded_at_display);

    let mut user_parts = vec![MultimodalContentPart::text(text_prompt)];

    if settings.vision_enabled {
        for step in &session.steps {
            if step.assets.screenshot.is_none() {
                continue;
            }
            let Some((_, base64)) = images.iter().find(|(index, _)| *index == step.index) else {
                continue;
            };
            user_parts.push(MultimodalContentPart::text(format!(
                "Screenshot for Step {} ({}):",
                step.index, step.action_description
            )));
            user_parts.push(MultimodalContentPart::image_url(format!(
                "data:image/png;base64,{base64}"
            )));
        }
    }

    ChatCompletionRequest {
        model: settings.model.clone(),
        messages: vec![
            ChatMessagePayload::from_text("system", system),
            ChatMessagePayload {
                role: "user".to_owned(),
                content: user_parts,
            },
        ],
        temperature: settings.temperature,
        stream: true,
    }
}
