#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Outcome {
    Ok,
    Failed,
    Usage,
    Canceled,
    Environment,
    Internal,
    Interrupted,
}

impl Outcome {
    pub fn code(self) -> u8 {
        match self {
            Outcome::Ok => 0,
            Outcome::Failed => 1,
            Outcome::Usage => 2,
            Outcome::Canceled => 3,
            Outcome::Environment => 4,
            Outcome::Internal => 5,
            Outcome::Interrupted => 130,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Outcome;

    const ALL: [Outcome; 7] = [
        Outcome::Ok,
        Outcome::Failed,
        Outcome::Usage,
        Outcome::Canceled,
        Outcome::Environment,
        Outcome::Internal,
        Outcome::Interrupted,
    ];

    #[test]
    fn codes_are_distinct() {
        for (i, a) in ALL.iter().enumerate() {
            for b in &ALL[i + 1..] {
                assert_ne!(a.code(), b.code(), "{a:?} and {b:?} share an exit code");
            }
        }
    }

    #[test]
    fn success_is_zero_and_interrupt_is_the_shell_convention() {
        assert_eq!(Outcome::Ok.code(), 0);
        assert_eq!(Outcome::Interrupted.code(), 130);
    }
}
