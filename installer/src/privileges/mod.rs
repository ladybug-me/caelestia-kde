#[cfg(unix)]
mod unix;

#[cfg(unix)]
pub use unix::*;

#[cfg(not(unix))]
mod other;

#[cfg(not(unix))]
pub use other::*;
