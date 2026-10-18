//! Copy-paste skeleton for `m2-01…m2-06` (R/M2-00).
//!
//! Steps: copy this dir to `core/crates/flowline_<module>/`, rename the package
//! in `Cargo.toml`, replace `not_implemented` with the ported logic, and add
//! `tests/parity.rs` using `parity_harness` + the `shared/goldens/` corpus.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error("not implemented: {0}")]
    NotImplemented(&'static str),
}

pub fn not_implemented(feature: &'static str) -> Error {
    Error::NotImplemented(feature)
}
