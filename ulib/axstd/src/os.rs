//! OS-specific functionality.

/// ArceOS-specific definitions.
pub mod arceos {
    pub use arceos_api as api;
    #[doc(no_inline)]
    pub use arceos_api::modules;
}
