pub fn info(message: &str) {
    println!("  [INFO]  {message}");
}

pub fn ok(message: &str) {
    println!("  [OK]    {message}");
}

pub fn warn(message: &str) {
    println!("  [WARN]  {message}");
}

pub fn skip(message: &str) {
    println!("  [SKIP]  {message}");
}

pub fn err(message: &str) {
    eprintln!("  [ERR]   {message}");
}
