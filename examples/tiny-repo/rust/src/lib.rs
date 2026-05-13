//! Tiny Rust greeter — fixture for oracle-index tests.

pub fn greet(name: &str) -> String {
    format_greeting(name)
}

fn format_greeting(name: &str) -> String {
    format!("Hello, {name}!")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greets() {
        assert_eq!(greet("world"), "Hello, world!");
    }
}
