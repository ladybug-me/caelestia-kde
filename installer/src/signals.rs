#[cfg(unix)]
static TERMINATED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

#[cfg(unix)]
extern "C" fn on_signal(_signal: libc::c_int) {
    TERMINATED.store(true, std::sync::atomic::Ordering::Relaxed);
}

#[cfg(unix)]
pub fn install() {
    let handler: extern "C" fn(libc::c_int) = on_signal;
    unsafe {
        for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP, libc::SIGQUIT] {
            libc::signal(signal, handler as libc::sighandler_t);
        }
    }
}

#[cfg(unix)]
pub fn terminated() -> bool {
    TERMINATED.load(std::sync::atomic::Ordering::Relaxed)
}

#[cfg(not(unix))]
pub fn install() {}

#[cfg(not(unix))]
pub fn terminated() -> bool {
    false
}
