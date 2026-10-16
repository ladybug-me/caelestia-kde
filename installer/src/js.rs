pub fn string(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for character in text.chars() {
        let code = character as u32;
        let plain =
            character.is_ascii_alphanumeric() || matches!(character, '/' | '.' | '_' | ':' | '-');
        if plain {
            out.push(character);
            continue;
        }

        if code > 0xFFFF {
            let value = code - 0x10000;
            out.push_str(&format!("\\u{:04x}", 0xD800 + (value >> 10)));
            out.push_str(&format!("\\u{:04x}", 0xDC00 + (value & 0x3FF)));
        } else {
            out.push_str(&format!("\\u{code:04x}"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_characters_javascript_reads_plainly_are_left_alone() {
        assert_eq!(
            string("file:///home/me/My_Walls.png"),
            "file:///home/me/My_Walls.png"
        );
        assert_eq!(string("abcXYZ019-._:/"), "abcXYZ019-._:/");
    }

    #[test]
    fn anything_else_becomes_an_escape() {
        assert_eq!(string("a b"), "a\\u0020b");
        assert_eq!(string("100%"), "100\\u0025");
        assert_eq!(string("it's"), "it\\u0027s");
    }

    #[test]
    fn a_character_outside_the_basic_plane_becomes_a_surrogate_pair() {
        assert_eq!(string("\u{1F600}"), "\\ud83d\\ude00");
    }

    #[test]
    fn an_empty_string_stays_empty() {
        assert_eq!(string(""), "");
    }
}
