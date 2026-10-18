//! Millisecond timestamp helpers for the post-hoc repair passes.
//!
//! The repair passes (`coalesce`, `split`) order `Step`s by their wire
//! timestamps (`YYYY-MM-DDTHH:MM:SS[.mmm]Z`, the same subset
//! `flowline_engine` parses — no chrono dependency). Unparseable timestamps
//! yield `None` and the passes conservatively refuse to merge/split across
//! them.

/// Parse `YYYY-MM-DDTHH:MM:SS[.mmm]Z` to epoch millis.
///
/// Returns `None` (instead of erroring) so the repair passes can treat a bad
/// timestamp as "unknown gap" and decline to repair across it.
pub fn parse_timestamp_millis(timestamp: &str) -> Option<u64> {
    if timestamp.len() < 20 || !timestamp.ends_with('Z') {
        return None;
    }
    let num =
        |range: std::ops::Range<usize>| timestamp.get(range).and_then(|s| s.parse::<i64>().ok());
    if &timestamp[4..5] != "-" || &timestamp[7..8] != "-" || &timestamp[10..11] != "T" {
        return None;
    }
    let year = num(0..4)?;
    let month = num(5..7)?;
    let day = num(8..10)?;
    let hour = num(11..13)?;
    let minute = num(14..16)?;
    let second = num(17..19)?;
    let millis = if timestamp.len() > 21 && &timestamp[19..20] == "." {
        let frac = timestamp
            .get(20..timestamp.len() - 1)
            .and_then(|s| s.parse::<i64>().ok())?;
        let width = (timestamp.len() - 21) as u32;
        if width > 3 {
            frac / 10_i64.pow(width - 3)
        } else {
            frac * 10_i64.pow(3 - width)
        }
    } else if timestamp.len() != 20 {
        return None;
    } else {
        0
    };

    const MILLIS_PER_DAY: i64 = 86_400_000;
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    let total = days * MILLIS_PER_DAY + hour * 3_600_000 + minute * 60_000 + second * 1000 + millis;
    u64::try_from(total).ok()
}

/// Format epoch millis as `YYYY-MM-DDTHH:MM:SSZ` (or `.mmmZ` when sub-second).
pub fn format_millis(millis: u64) -> String {
    const MILLIS_PER_DAY: i64 = 86_400_000;
    let days = (millis / MILLIS_PER_DAY as u64) as i64;
    let rem = (millis % MILLIS_PER_DAY as u64) as i64;
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    let hour = rem / 3_600_000;
    let minute = (rem % 3_600_000) / 60_000;
    let second = (rem % 60_000) / 1000;
    let ms = rem % 1000;
    if ms == 0 {
        format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}Z")
    } else {
        format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}.{ms:03}Z")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_whole_and_fractional() {
        for ts in [
            "2026-03-01T10:00:00Z",
            "2026-03-01T10:00:01.800Z",
            "2026-03-01T10:00:02.050Z",
        ] {
            let ms = parse_timestamp_millis(ts).expect("parses");
            assert_eq!(format_millis(ms), ts);
        }
    }

    #[test]
    fn rejects_malformed() {
        assert_eq!(parse_timestamp_millis("not a timestamp"), None);
        assert_eq!(parse_timestamp_millis("2026-03-01 10:00:00Z"), None);
        assert_eq!(parse_timestamp_millis("2026-03-01T10:00:00"), None);
    }

    #[test]
    fn gap_arithmetic() {
        let a = parse_timestamp_millis("2026-03-01T10:00:00Z").expect("a");
        let b = parse_timestamp_millis("2026-03-01T10:00:01.800Z").expect("b");
        assert_eq!(b.saturating_sub(a), 1800);
    }
}
