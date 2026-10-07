//! The application build number ("versionCode", e.g. `18` for `1.1.4+18`)
//! optionally exchanged by Aika devices during a transfer.
//!
//! It is purely informational (an "update available" hint) and comes from
//! an untrusted peer: a missing, malformed or out-of-range value is read as
//! `None` and must never make a request fail. Older Aika versions neither
//! send nor read it, so the protocol stays fully compatible.

use serde::{Deserialize, Deserializer};
use serde_json::Value;

/// Highest valid build number (Google Play's versionCode limit).
pub const MAX_APP_BUILD: u64 = 2_100_000_000;

/// Validates a build number received from another device.
pub fn sanitize(value: u64) -> Option<u32> {
    if (1..=MAX_APP_BUILD).contains(&value) {
        u32::try_from(value).ok()
    } else {
        None
    }
}

/// Lenient serde deserializer for `appBuild` fields: accepts a positive
/// integer (or a numeric string) and maps anything else to `None` instead
/// of rejecting the whole request.
///
/// Use together with `#[serde(default)]` so a missing field is `None` too.
pub fn deserialize<'de, D>(deserializer: D) -> Result<Option<u32>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    Ok(match value {
        Value::Number(n) => n.as_u64().and_then(sanitize),
        Value::String(s) if s.len() <= 10 => s.trim().parse::<u64>().ok().and_then(sanitize),
        _ => None,
    })
}

#[cfg(test)]
mod tests {
    use serde::Deserialize;

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Dto {
        #[serde(default, deserialize_with = "super::deserialize")]
        app_build: Option<u32>,
    }

    fn parse(json: &str) -> Option<u32> {
        serde_json::from_str::<Dto>(json).unwrap().app_build
    }

    #[test]
    fn valid_builds_are_read() {
        assert_eq!(parse(r#"{"appBuild":18}"#), Some(18));
        assert_eq!(parse(r#"{"appBuild":"20"}"#), Some(20));
    }

    #[test]
    fn missing_or_invalid_builds_never_fail() {
        assert_eq!(parse(r#"{}"#), None);
        assert_eq!(parse(r#"{"appBuild":null}"#), None);
        assert_eq!(parse(r#"{"appBuild":0}"#), None);
        assert_eq!(parse(r#"{"appBuild":-3}"#), None);
        assert_eq!(parse(r#"{"appBuild":1.5}"#), None);
        assert_eq!(parse(r#"{"appBuild":99999999999}"#), None);
        assert_eq!(parse(r#"{"appBuild":"abc"}"#), None);
        assert_eq!(parse(r#"{"appBuild":[18]}"#), None);
        assert_eq!(parse(r#"{"appBuild":{"x":1}}"#), None);
    }

    /// Messages of older Aika / LocalSend versions still parse, and messages
    /// without a build are byte-for-byte what those versions expect.
    #[test]
    fn compatible_with_older_versions() {
        use crate::http::dto_v2::{PrepareUploadResponseDtoV2, RegisterDtoV2};

        let old_response = r#"{"sessionId":"s","files":{"f":"t"}}"#;
        let response: PrepareUploadResponseDtoV2 = serde_json::from_str(old_response).unwrap();
        assert_eq!(response.app_build, None);
        assert!(!serde_json::to_string(&response)
            .unwrap()
            .contains("appBuild"));

        let old_info =
            r#"{"alias":"A","version":"2.1","fingerprint":"f","port":53317,"protocol":"https"}"#;
        let info: RegisterDtoV2 = serde_json::from_str(old_info).unwrap();
        assert_eq!(info.app_build, None);
        assert!(!serde_json::to_string(&info).unwrap().contains("appBuild"));

        let new_info = r#"{"alias":"A","version":"2.1","fingerprint":"f","port":53317,"protocol":"https","appBuild":20}"#;
        let info: RegisterDtoV2 = serde_json::from_str(new_info).unwrap();
        assert_eq!(info.app_build, Some(20));
        assert!(serde_json::to_string(&info)
            .unwrap()
            .contains(r#""appBuild":20"#));
    }
}
