//! MCP projection — serialize steps as MCP tool-call JSON for replay.
//!
//! Same placeholder rule: secret values are replaced with
//! `{{secret:<kind>}}` BEFORE serialization, so raw secrets never reach the
//! JSON payload.

use crate::ScriptStep;
use serde::Serialize;

/// One replayable tool call.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ToolCall {
    pub tool: String,
    pub args: serde_json::Value,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub description: String,
}

impl ToolCall {
    pub fn new(tool: &str, args: serde_json::Value, description: &str) -> Self {
        Self {
            tool: tool.to_string(),
            args,
            description: description.to_string(),
        }
    }
}

/// Map steps to tool calls (redacted).
pub fn to_tool_calls(steps: &[ScriptStep]) -> Vec<ToolCall> {
    steps
        .iter()
        .map(|step| {
            let redacted = step.redacted_text();
            match step.action.as_str() {
                "click" | "right_click" | "double_click" => ToolCall::new(
                    &step.action,
                    serde_json::json!({}),
                    &step.description,
                ),
                "typing" => ToolCall::new(
                    "type_text",
                    serde_json::json!({ "text": redacted }),
                    &step.description,
                ),
                "terminal" | "write_code" => ToolCall::new(
                    "run_command",
                    serde_json::json!({ "command": redacted }),
                    &step.description,
                ),
                "key_press" => ToolCall::new(
                    "press_hotkey",
                    serde_json::json!({ "combo": redacted }),
                    &step.description,
                ),
                other => ToolCall::new(
                    "note",
                    serde_json::json!({ "action": other }),
                    &step.description,
                ),
            }
        })
        .collect()
}

/// Render steps as pretty MCP tool-call JSON.
pub fn render(steps: &[ScriptStep]) -> String {
    serde_json::to_string_pretty(&to_tool_calls(steps)).unwrap_or_else(|_| "[]".to_string())
}
