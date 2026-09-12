//! `file: true` — spilling a tool result to disk instead of returning it inline.
//!
//! The bridge declares one extra boolean parameter on every tool it forwards.
//! When the caller sets it, the provider still runs unchanged (the flag is
//! stripped before the call is forwarded) but its result is written next to the
//! server's logs and replaced by a short summary: the path, the size, and a
//! preview. The caller then reads or greps only the part it needs.
//!
//! Everything here is a pure transformation except [`write_all`], which is the
//! single IO step; the caller supplies the directory and decides what to do
//! when the write fails.
//!
//! Readability of the spilled path is structural rather than configured: the
//! server runs as a stdio child of the agent, so it shares the agent's mount
//! namespace and uid, and anything it can write the agent can read.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use rmcp::model::{CallToolResult, ContentBlock, Tool};
use serde_json::{json, Map, Value};

/// The injected parameter name. A provider that already declares `file` keeps
/// its own meaning for it — see [`file_param_is_injected`].
pub const FILE_PARAM: &str = "file";

/// Subdirectory of the server's log dir that spilled results are written to.
pub const RESULTS_DIR: &str = "results";

const PREVIEW_LINES: usize = 20;
const PREVIEW_CHARS: usize = 2000;

fn file_param_schema() -> Value {
    json!({
        "type": "boolean",
        "description": "Write this call's result to a file instead of returning it inline. \
    The call then returns the file path plus a short preview, so you can read, grep or slice \
    only the parts you need. Set true when you expect output large enough that you would not \
    want all of it at once; default false returns the whole result inline.",
    })
}

fn declared_properties(schema: &Map<String, Value>) -> Option<&Map<String, Value>> {
    schema.get("properties").and_then(Value::as_object)
}

/// True when the bridge owns `file` for this tool, i.e. the provider does not
/// declare a parameter by that name itself. A provider that does keeps it: the
/// bridge neither advertises nor strips the flag, and forwards it untouched.
pub fn file_param_is_injected(tool: &Tool) -> bool {
    !declared_properties(&tool.input_schema)
        .is_some_and(|properties| properties.contains_key(FILE_PARAM))
}

/// The client-facing view of a registered tool: the provider's definition plus
/// the `file` parameter. Returned unchanged when the provider owns `file`, or
/// when the schema has a `properties` that isn't an object to merge into.
pub fn with_file_param(tool: &Tool) -> Tool {
    if !file_param_is_injected(tool) {
        return tool.clone();
    }

    let mut schema = tool.input_schema.as_ref().clone();
    let properties = schema
        .entry("properties")
        .or_insert_with(|| Value::Object(Map::new()));
    let Some(properties) = properties.as_object_mut() else {
        return tool.clone();
    };
    properties.insert(FILE_PARAM.to_string(), file_param_schema());

    let mut tool = tool.clone();
    tool.input_schema = Arc::new(schema);
    tool
}

/// Remove the injected flag from the arguments and report whether it asked for
/// a spill. Always removes: the provider declared `additionalProperties: false`
/// in the common case and must not see a parameter it never advertised.
pub fn take_file_flag(arguments: &mut Map<String, Value>) -> bool {
    arguments
        .remove(FILE_PARAM)
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    /// The result's text blocks, verbatim — the form worth grepping.
    Text,
    /// The whole result as JSON, for structured content and non-text blocks.
    Json,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannedFile {
    pub path: PathBuf,
    pub body: String,
    pub kind: FileKind,
}

/// What to write for `result`, in the order the caller should read it.
///
/// Text blocks go to `<call_id>.txt` verbatim: a result whose text is command
/// output is useless once JSON-escaped, and that is the case this exists for.
/// `<call_id>.json` carries the whole result, and is written whenever the text
/// file alone would lose something — structured content, a non-text block, or
/// no text at all. Both are written when both apply, so nothing is dropped.
pub fn plan(result: &CallToolResult, dir: &Path, call_id: &str) -> Vec<PlannedFile> {
    let text = text_body(result);
    let needs_json = text.is_none()
        || result.structured_content.is_some()
        || result.content.iter().any(|block| block.as_text().is_none());

    let text_file = text.map(|body| PlannedFile {
        path: dir.join(format!("{call_id}.txt")),
        body,
        kind: FileKind::Text,
    });
    let json_file = needs_json.then(|| PlannedFile {
        path: dir.join(format!("{call_id}.json")),
        body: json_body(result),
        kind: FileKind::Json,
    });

    text_file.into_iter().chain(json_file).collect()
}

fn text_body(result: &CallToolResult) -> Option<String> {
    let body = result
        .content
        .iter()
        .filter_map(|block| block.as_text())
        .map(|text| text.text.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    (!body.is_empty()).then_some(body)
}

fn json_body(result: &CallToolResult) -> String {
    serde_json::to_string_pretty(result)
        .unwrap_or_else(|error| json!({ "serializationError": error.to_string() }).to_string())
}

/// The one IO step: create the results directory and write each planned file.
pub fn write_all(files: &[PlannedFile]) -> io::Result<()> {
    for file in files {
        if let Some(parent) = file.path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&file.path, &file.body)?;
    }
    Ok(())
}

/// The result to return in place of the spilled one: where it went, how big it
/// is, and enough of the head that a small result often needs no read at all.
/// `is_error` is carried over so a failed call still looks failed.
pub fn spilled_result(files: &[PlannedFile], is_error: Option<bool>) -> CallToolResult {
    let mut result = CallToolResult::success(vec![ContentBlock::text(summary(files, is_error))]);
    result.is_error = is_error;
    result
}

/// Fallback when [`write_all`] fails: the caller asked for a file and there
/// isn't one, so return the result inline rather than losing it, with the
/// reason in front so the caller knows why its request went unhonoured.
pub fn write_failed_result(result: CallToolResult, error: &io::Error) -> CallToolResult {
    let mut result = result;
    result.content.insert(
        0,
        ContentBlock::text(format!(
            "Note: `{FILE_PARAM}: true` could not be honoured ({error}); \
the full result is inline below."
        )),
    );
    result
}

fn summary(files: &[PlannedFile], is_error: Option<bool>) -> String {
    let listing = files
        .iter()
        .map(|file| format!("  {} — {}", file.path.display(), describe(file)))
        .collect::<Vec<_>>()
        .join("\n");

    let mut sections = vec![
        "Result written to file instead of being returned inline:".to_string(),
        listing,
    ];
    if is_error == Some(true) {
        sections.push("The tool reported an error for this call.".to_string());
    }
    if let Some(file) = files.first() {
        sections.push(preview(file));
    }
    sections.join("\n\n")
}

fn describe(file: &PlannedFile) -> String {
    let size = format_size(file.body.len());
    match file.kind {
        FileKind::Text => format!("text content, {size}, {} lines", line_count(&file.body)),
        FileKind::Json => {
            format!("whole result as JSON (structured content, non-text blocks), {size}")
        }
    }
}

fn preview(file: &PlannedFile) -> String {
    let total = line_count(&file.body);
    let head = file
        .body
        .lines()
        .take(PREVIEW_LINES)
        .collect::<Vec<_>>()
        .join("\n");
    let (head, clipped) = clip(&head, PREVIEW_CHARS);
    let shown = line_count(&head);

    let header = if clipped {
        format!("Preview — first {PREVIEW_CHARS} characters of {total} lines:")
    } else if shown < total {
        format!("Preview — first {shown} of {total} lines:")
    } else {
        format!("Content ({total} lines), also written to the file above:")
    };
    let ellipsis = if clipped || shown < total {
        "\n…"
    } else {
        ""
    };
    format!("{header}\n{head}{ellipsis}")
}

fn line_count(text: &str) -> usize {
    text.lines().count()
}

/// Truncate on a character boundary, reporting whether anything was cut.
fn clip(text: &str, max_chars: usize) -> (String, bool) {
    match text.char_indices().nth(max_chars) {
        Some((index, _)) => (text[..index].to_string(), true),
        None => (text.to_string(), false),
    }
}

fn format_size(bytes: usize) -> String {
    const KIB: f64 = 1024.0;
    const MIB: f64 = KIB * KIB;
    let size = bytes as f64;
    if size < KIB {
        format!("{bytes} B")
    } else if size < MIB {
        format!("{:.1} KiB", size / KIB)
    } else {
        format!("{:.1} MiB", size / MIB)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::borrow::Cow;

    fn tool_with_schema(schema: Value) -> Tool {
        let mut tool = Tool::default();
        tool.name = Cow::Borrowed("demo");
        tool.input_schema =
            Arc::new(serde_json::from_value(schema).expect("schema should be an object"));
        tool
    }

    fn schema_of(tool: &Tool) -> Value {
        Value::Object(tool.input_schema.as_ref().clone())
    }

    #[test]
    fn file_param_is_declared_alongside_the_providers_own_parameters() {
        let tool = tool_with_schema(json!({
            "type": "object",
            "properties": { "message": { "type": "string" } },
            "additionalProperties": false
        }));

        let schema = schema_of(&with_file_param(&tool));
        assert_eq!(schema["properties"][FILE_PARAM]["type"], json!("boolean"));
        // The provider's own schema must survive intact: `additionalProperties:
        // false` means a client would reject the call if `file` were undeclared.
        assert_eq!(schema["properties"]["message"]["type"], json!("string"));
        assert_eq!(schema["additionalProperties"], json!(false));
    }

    #[test]
    fn a_provider_that_declares_file_itself_keeps_it() {
        let tool = tool_with_schema(json!({
            "type": "object",
            "properties": { "file": { "type": "string", "description": "path to read" } }
        }));

        assert!(!file_param_is_injected(&tool));
        // Untouched, so the provider still receives the argument it declared.
        assert_eq!(schema_of(&with_file_param(&tool)), schema_of(&tool));
    }

    #[test]
    fn taking_the_flag_always_removes_it() {
        let mut arguments = match json!({"file": true, "message": "hi"}) {
            Value::Object(map) => map,
            _ => unreachable!(),
        };
        assert!(take_file_flag(&mut arguments));
        assert!(!arguments.contains_key(FILE_PARAM));
        assert_eq!(arguments["message"], json!("hi"));

        // A non-boolean is not a request to spill, but still must not reach a
        // provider that declared `additionalProperties: false`.
        let mut arguments = match json!({"file": "yes"}) {
            Value::Object(map) => map,
            _ => unreachable!(),
        };
        assert!(!take_file_flag(&mut arguments));
        assert!(arguments.is_empty());
    }

    #[test]
    fn text_only_results_spill_to_a_single_verbatim_file() {
        let result = CallToolResult::success(vec![ContentBlock::text("line one\nline two")]);
        let files = plan(&result, Path::new("/spill"), "7");

        assert_eq!(files.len(), 1);
        assert_eq!(files[0].kind, FileKind::Text);
        assert_eq!(files[0].path, PathBuf::from("/spill/7.txt"));
        // Verbatim, not JSON-escaped — the point is that grep still works.
        assert_eq!(files[0].body, "line one\nline two");
    }

    #[test]
    fn structured_content_is_kept_in_a_sibling_json_file() {
        let mut result = CallToolResult::success(vec![ContentBlock::text("stdout here")]);
        result.structured_content = Some(json!({"exitCode": 0, "stdout": "stdout here"}));
        let files = plan(&result, Path::new("/spill"), "7");

        assert_eq!(files.len(), 2);
        assert_eq!(files[0].kind, FileKind::Text);
        assert_eq!(files[1].kind, FileKind::Json);
        assert_eq!(files[1].path, PathBuf::from("/spill/7.json"));
        let written = serde_json::from_str::<Value>(&files[1].body).expect("valid JSON");
        assert_eq!(written["structuredContent"]["exitCode"], json!(0));
    }

    #[test]
    fn a_result_without_text_still_produces_a_file() {
        let mut result = CallToolResult::success(Vec::new());
        result.structured_content = Some(json!({"rows": []}));
        let files = plan(&result, Path::new("/spill"), "7");

        assert_eq!(files.len(), 1);
        assert_eq!(files[0].kind, FileKind::Json);
    }

    #[test]
    fn the_summary_names_the_path_and_previews_the_head() {
        let body = (1..=100)
            .map(|index| format!("line {index}"))
            .collect::<Vec<_>>()
            .join("\n");
        let files = vec![PlannedFile {
            path: PathBuf::from("/spill/7.txt"),
            body,
            kind: FileKind::Text,
        }];

        let summary = match spilled_result(&files, Some(false)).content.first() {
            Some(block) => block.as_text().expect("text block").text.clone(),
            None => panic!("summary should have content"),
        };

        assert!(summary.contains("/spill/7.txt"), "got {summary}");
        assert!(summary.contains("100 lines"), "got {summary}");
        assert!(summary.contains("line 1\n"), "got {summary}");
        assert!(summary.contains(&format!("first {PREVIEW_LINES} of 100 lines")));
        // The preview is a head, not the whole thing — otherwise spilling saved
        // the caller nothing.
        assert!(!summary.contains("line 100"), "got {summary}");
    }

    #[test]
    fn a_failed_call_still_reads_as_failed_after_spilling() {
        let files = vec![PlannedFile {
            path: PathBuf::from("/spill/7.txt"),
            body: "boom".to_string(),
            kind: FileKind::Text,
        }];
        let result = spilled_result(&files, Some(true));

        assert_eq!(result.is_error, Some(true));
        assert!(result.content[0]
            .as_text()
            .expect("text block")
            .text
            .contains("reported an error"));
    }

    #[test]
    fn an_unwritable_path_falls_back_to_the_inline_result() {
        let result = CallToolResult::success(vec![ContentBlock::text("the real output")]);
        let error = io::Error::new(io::ErrorKind::PermissionDenied, "denied");
        let result = write_failed_result(result, &error);

        assert!(result.content[0]
            .as_text()
            .expect("text block")
            .text
            .contains("could not be honoured"));
        // The output itself is never lost just because the spill failed.
        assert_eq!(
            result.content[1].as_text().expect("text block").text,
            "the real output"
        );
    }

    #[test]
    fn sizes_are_reported_in_readable_units() {
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(2048), "2.0 KiB");
        assert_eq!(format_size(3 * 1024 * 1024), "3.0 MiB");
    }

    #[test]
    fn write_all_creates_the_results_directory() {
        let dir = std::env::temp_dir().join(format!("htm-spill-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);

        let files = vec![PlannedFile {
            path: dir.join(RESULTS_DIR).join("7.txt"),
            body: "written".to_string(),
            kind: FileKind::Text,
        }];
        write_all(&files).expect("write should create the directory");
        assert_eq!(fs::read_to_string(&files[0].path).unwrap(), "written");

        let _ = fs::remove_dir_all(&dir);
    }
}
