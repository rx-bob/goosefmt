// Lexer and signature helpers used by Goose lint rules.
namespace linter;

import formatter;
import lexer;

struct Nesting {
    parens: i64,
    squares: i64,
    braces: i64,
    angles: i64,
}

fn nesting() -> Nesting {
    return Nesting {
        parens: 0,
        squares: 0,
        braces: 0,
        angles: 0
    };
}

fn at_top(depth: Nesting) -> bool {
    return depth.parens == 0 && depth.squares == 0 && depth.braces == 0 && depth.angles == 0;
}

fn advance_nesting(depth: Nesting&, token: lexer::Token, generic: bool) {
    let text = token.text;
    if text == "(" {
        depth.parens += 1;
    } else if text == ")" && depth.parens > 0 {
        depth.parens -= 1;
    } else if text == "[" {
        depth.squares += 1;
    } else if text == "]" && depth.squares > 0 {
        depth.squares -= 1;
    } else if text == "{" {
        depth.braces += 1;
    } else if text == "}" && depth.braces > 0 {
        depth.braces -= 1;
    } else if generic && text == "<" {
        depth.angles += 1;
    } else if generic && (text == ">" || text == ">>") && depth.angles > 0 {
        depth.angles -= if text == ">>" {
            2
        } else {
            1
        };
    }
}

fn rule_name(rule: i32) -> const u8[:] {
    if rule == 1 {
        return "G001";
    }
    if rule == 2 {
        return "G002";
    }
    if rule == 3 {
        return "G003";
    }
    if rule == 4 {
        return "G004";
    }
    if rule == 5 {
        return "G005";
    }
    if rule == 6 {
        return "G006";
    }
    if rule == 7 {
        return "G007";
    }
    if rule == 8 {
        return "G008";
    }
    if rule == 9 {
        return "G009";
    }
    if rule == 10 {
        return "G010";
    }
    if rule == 11 {
        return "G011";
    }
    if rule == 12 {
        return "G012";
    }
    if rule == 13 {
        return "G013";
    }
    if rule == 14 {
        return "G014";
    }
    if rule == 15 {
        return "G015";
    }
    if rule == 16 {
        return "G016";
    }
    if rule == 17 {
        return "G017";
    }
    if rule == 18 {
        return "G018";
    }
    return "G019";
}

fn description(rule: i32) -> const u8[:] {
    if rule == 1 {
        return "use the configured number of spaces for indentation";
    }
    if rule == 2 {
        return "put spaces around binary operators";
    }
    if rule == 3 {
        return "put a space after the comma";
    }
    if rule == 4 {
        return "use consistent spacing around the colon";
    }
    if rule == 5 {
        return "put each statement on its own line";
    }
    if rule == 6 {
        return "line exceeds configured maximum length";
    }
    if rule == 7 {
        return "file must end with a newline";
    }
    if rule == 8 {
        return "too many function parameters; group related values in a struct";
    }
    if rule == 9 {
        return "too many return values; use a named struct";
    }
    if rule == 10 {
        return "file exceeds the configured maximum line count";
    }
    if rule == 11 {
        return "use Goose naming conventions";
    }
    if rule == 12 {
        return "sort imports by origin and name; remove duplicate or misplaced imports";
    }
    if rule == 13 {
        return "remove redundant outer parentheses";
    }
    if rule == 14 {
        return "function body exceeds configured maximum length";
    }
    if rule == 15 {
        return "use const on read-only extern slice parameters";
    }
    if rule == 16 {
        return "top-level const names must use SCREAMING_SNAKE_CASE";
    }
    if rule == 17 {
        return "bind fixed-size push and alloc_ref results with .= when mutating or linking";
    }
    if rule == 18 {
        return "split compound assert conditions into separate assertions";
    }
    return "bound loop termination and avoid recursive functions in strict safety mode";
}

fn generic_angle_tokens(tokens: lexer::Token[:]) -> bool[>..] {
    return formatter::generic_angles(tokens);
}

fn function_name_index(tokens: lexer::Token[:], function_index: i64) -> i64 {
    var name = formatter::next_significant(tokens, function_index + 1);
    if name >= tokens.len {
        return -1;
    }
    if tokens[name].text == "::" {
        name = formatter::next_significant(tokens, name + 1);
    }
    if name < tokens.len && tokens[name].kind == lexer::IDENT {
        return name;
    }
    return -1;
}

fn matching_delimiter(
    tokens: lexer::Token[:],
    open_index: i64,
    open_text: const u8[:],
    close_text: const u8[:]
) -> i64 {
    var depth: i64 = 0;
    for i in open_index..tokens.len {
        if tokens[i].text == open_text {
            depth += 1;
        } else if tokens[i].text == close_text {
            depth -= 1;
            if depth == 0 {
                return i;
            }
        }
    }
    return -1;
}

fn function_parameters(tokens: lexer::Token[:], function_index: i64) -> i64, i64 {
    let name = function_name_index(tokens, function_index);
    if name < 0 {
        return -1, -1;
    }
    var open = formatter::next_significant(tokens, name + 1);
    while open < tokens.len && tokens[open].text != "(" && tokens[open].text != "{"
        && tokens[open].text != ";" {
        open = formatter::next_significant(tokens, open + 1);
    }
    if open >= tokens.len || tokens[open].text != "(" {
        return -1, -1;
    }
    return open, matching_delimiter(tokens, open, "(", ")");
}

fn function_body(tokens: lexer::Token[:], function_index: i64) -> i64, i64 {
    let open_params,
    close_params = function_parameters(tokens, function_index);
    if close_params < 0 {
        return -1, -1;
    }
    var open = formatter::next_significant(tokens, close_params + 1);
    while open < tokens.len && tokens[open].text != "{" && tokens[open].text != ";" {
        open = formatter::next_significant(tokens, open + 1);
    }
    if open >= tokens.len || tokens[open].text != "{" {
        return -1, -1;
    }
    return open, matching_delimiter(tokens, open, "{", "}");
}

fn function_has_modifier(
    tokens: lexer::Token[:],
    function_index: i64,
    modifier: const u8[:]
) -> bool {
    var previous = formatter::previous_significant(tokens, function_index);
    if previous >= 0 && tokens[previous].kind == lexer::STRING {
        previous = formatter::previous_significant(tokens, previous);
    }
    while previous >= 0 && formatter::is_function_modifier(tokens[previous].text) {
        if tokens[previous].text == modifier {
            return true;
        }
        previous = formatter::previous_significant(tokens, previous);
    }
    return false;
}

fn top_level_count(
    tokens: lexer::Token[:],
    start: i64,
    end: i64,
    generic: bool[:]
) -> i64 {
    var parens: i64 = 0;
    var squares: i64 = 0;
    var braces: i64 = 0;
    var angles: i64 = 0;
    var values: i64 = 0;
    var has_value = false;
    for i in start..end {
        if tokens[i].kind == lexer::NEWLINE || tokens[i].kind == lexer::COMMENT {
            continue;
        }
        let text = tokens[i].text;
        if text == "," && parens == 0 && squares == 0 && braces == 0 && angles == 0 {
            if has_value {
                values += 1;
            }
            has_value = false;
            continue;
        }
        has_value = true;
        if text == "(" {
            parens += 1;
        } else if text == ")" {
            if parens > 0 {
                parens -= 1;
            }
        } else if text == "[" {
            squares += 1;
        } else if text == "]" {
            if squares > 0 {
                squares -= 1;
            }
        } else if text == "{" {
            braces += 1;
        } else if text == "}" {
            if braces > 0 {
                braces -= 1;
            }
        } else if text == "<" && generic[i] {
            angles += 1;
        } else if (text == ">" || text == ">>") && generic[i] && angles > 0 {
            angles -= if text == ">>" {
                2
            } else {
                1
            };
        }
    }
    if has_value {
        values += 1;
    }
    return values;
}

fn unary(tokens: lexer::Token[:], index: i64) -> bool {
    return formatter::is_unary(tokens, index);
}

fn binary_operator(text: const u8[:]) -> bool {
    return text == "=" || text == ".=" || text == "+" || text == "-" || text == "&"
        || text == "*" || text == "/" || text == "%" || text == "=="
        || text == "!=" || text == "<" || text == ">" || text == "<="
        || text == ">=" || text == "&&" || text == "||" || text == "|"
        || text == "^" || text == "<<" || text == ">>" || text == "+="
        || text == "-=" || text == "*=" || text == "/=" || text == "%="
        || text == "&=" || text == "|=" || text == "^=" || text == "<<="
        || text == ">>=" || text == "->" || text == "=>";
}

fn protected_lines(tokens: lexer::Token[:], line_count: i64) -> bool[>..] {
    var protected: bool[>..] = [];
    for _ in line_count {
        protected.push(false);
    }
    for i in tokens.len {
        let token = tokens[i];
        if (token.kind == lexer::STRING || token.kind == lexer::COMMENT)
            && token.end_line > token.line {
            var line = token.line + 1;
            while line <= token.end_line && line <= line_count {
                protected[line - 1] = true;
                line += 1;
            }
        }
    }
    return protected;
}

fn long_literal_lines(
    tokens: lexer::Token[:],
    line_count: i64,
    max_line_length: i64
) -> bool[>..] {
    var long: bool[>..] = [];
    for _ in line_count {
        long.push(false);
    }
    for token in tokens {
        if token.kind == lexer::STRING && token.text.len > max_line_length {
            var line = token.line;
            while line <= token.end_line && line <= line_count {
                long[line - 1] = true;
                line += 1;
            }
        }
    }
    return long;
}
