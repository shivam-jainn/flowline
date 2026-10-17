//! Swift-compatible `Double` serialization.
//!
//! Swift's `JSONEncoder` emits integral doubles without a decimal point
//! (`100`, not `100.0`); `serde_json` always emits `100.0` for `f64`. This
//! `serialize_with` helper closes the gap so canonical JSON is byte-identical.

use serde::Serializer;

/// Serialize an `f64` the way Swift `JSONEncoder` does: whole values as
/// integers, everything else as doubles.
pub fn serialize_f64<S: Serializer>(value: &f64, serializer: S) -> Result<S::Ok, S::Error> {
    if value.is_finite()
        && value.fract() == 0.0
        && *value >= i64::MIN as f64
        && *value <= i64::MAX as f64
    {
        serializer.serialize_i64(*value as i64)
    } else {
        serializer.serialize_f64(*value)
    }
}
