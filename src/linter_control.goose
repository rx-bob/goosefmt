// Compound assertions and bounded-control-flow lint rules.
namespace linter;

import config;
import formatter;
import lexer;

fn unwrapped_expression(tokens: lexer::Token[:], start: i64, end: i64) -> i64, i64 {
    var first = formatter::next_significant(tokens, start);
    var last = formatter::previous_significant(tokens, end);
    while first < last && tokens[first].text == "("
        && matching_delimiter(tokens, first, "(", ")") == last {
        first = formatter::next_significant(tokens, first + 1);
        last = formatter::previous_significant(tokens, last);
    }
    return first, last;
}

fn conjunction_index(tokens: lexer::Token[:], start: i64, end: i64) -> i64 {
    let first, last = unwrapped_expression(tokens, start, end);
    var result = -1;
    var depth = nesting();
    for i in first..last + 1 {
        if at_top(depth) {
            if tokens[i].text == "||" || tokens[i].text == "," {
                return -1;
            }
            if tokens[i].text == "&&" {
                result = i;
            }
        }
        advance_nesting(depth, tokens[i], false);
    }
    return result;
}

fn lint_compound_asserts(tokens: lexer::Token[:], options: config::Options, issues: Issue[>..]&) {
    if !options.lint_split_compound_assert {
        return;
    }
    for i in tokens.len {
        if tokens[i].kind != lexer::IDENT || tokens[i].text != "assert" {
            continue;
        }
        let open = formatter::next_significant(tokens, i + 1);
        if open >= tokens.len || tokens[open].text != "(" {
            continue;
        }
        let close = matching_delimiter(tokens, open, "(", ")");
        if close < 0 {
            continue;
        }
        let conjunction = conjunction_index(tokens, open + 1, close);
        if conjunction >= 0 {
            add(issues, tokens[conjunction].line, tokens[conjunction].column, 18);
        }
    }
}

fn loop_body_open(tokens: lexer::Token[:], loop_index: i64, end: i64) -> i64 {
    var i = formatter::next_significant(tokens, loop_index + 1);
    while i < end && tokens[i].text != "{" && tokens[i].text != ";" {
        i = formatter::next_significant(tokens, i + 1);
    }
    if i < end && tokens[i].text == "{" {
        return i;
    }
    return -1;
}

fn asserted_counter_bound(tokens: lexer::Token[:], name: const u8[:], start: i64, end: i64) -> bool {
    var skip_until = -1;
    for i in start..end {
        if i < skip_until {
            continue;
        }
        if tokens[i].text == "fn" {
            let open, close = function_body(tokens, i);
            if open >= 0 && close > open {
                skip_until = close + 1;
                continue;
            }
        }
        if tokens[i].text == "for" || tokens[i].text == "while" || tokens[i].text == "loop" {
            let open = loop_body_open(tokens, i, end);
            if open >= 0 {
                skip_until = matching_delimiter(tokens, open, "{", "}") + 1;
                continue;
            }
        }
        if tokens[i].text != "assert" {
            continue;
        }
        let open = formatter::next_significant(tokens, i + 1);
        if open >= end || tokens[open].text != "(" {
            continue;
        }
        let close = matching_delimiter(tokens, open, "(", ")");
        if close < 0 || close >= end {
            continue;
        }
        let first, last = unwrapped_expression(tokens, open + 1, close);
        if first >= last || tokens[first].text != name {
            continue;
        }
        let comparison = formatter::next_significant(tokens, first + 1);
        let text = tokens[comparison].text;
        if text != "<" && text != "<=" && text != ">" && text != ">=" {
            continue;
        }
        let bound = formatter::next_significant(tokens, comparison + 1);
        if bound == last && (tokens[bound].kind == lexer::NUMBER || tokens[bound].kind == lexer::IDENT) {
            return true;
        }
    }
    return false;
}

fn visible_step_bound(tokens: lexer::Token[:], index: i64, start: i64, end: i64) -> bool {
    let token = tokens[index];
    if token.kind != lexer::IDENT {
        return false;
    }
    let next = formatter::next_significant(tokens, index + 1);
    if next >= end || tokens[next].text != "+=" && tokens[next].text != "-=" {
        return false;
    }
    let step = formatter::next_significant(tokens, next + 1);
    if step >= end || tokens[step].kind != lexer::NUMBER || tokens[step].text == "0" {
        return false;
    }
    return asserted_counter_bound(tokens, token.text, start, end);
}

fn loop_has_visible_exit(tokens: lexer::Token[:], open: i64, close: i64) -> bool {
    var i = open + 1;
    var nested_loop_end = -1;
    while i < close {
        let token = tokens[i];
        if token.kind == lexer::IDENT && (token.text == "for" || token.text == "while"
            || token.text == "loop") {
            let nested_open = loop_body_open(tokens, i, close);
            if nested_open >= 0 && i > nested_loop_end {
                let nested_close = matching_delimiter(tokens, nested_open, "{", "}");
                if nested_close > nested_open {
                    nested_loop_end = nested_close;
                }
            }
        }
        if token.kind == lexer::IDENT && token.text == "fn" && function_name_index(tokens, i) >= 0 {
            let nested_open,
            nested_close = function_body(tokens, i);
            if nested_open >= 0 && nested_close > nested_open {
                i = nested_close + 1;
                continue;
            }
        }
        if token.kind == lexer::IDENT && (token.text == "break" && i > nested_loop_end
            || token.text == "return") {
            return true;
        }
        let next = formatter::next_significant(tokens, i + 1);
        if token.kind == lexer::IDENT && token.text == "abort"
            && next < close && tokens[next].text == "(" {
            return true;
        }
        if i > nested_loop_end && visible_step_bound(tokens, i, open + 1, close) {
            return true;
        }
        i += 1;
    }
    return false;
}

fn lint_bounded_control_flow(
    tokens: lexer::Token[:],
    options: config::Options,
    issues: Issue[>..]&
) {
    if !options.lint_bounded_control_flow {
        return;
    }
    for i in tokens.len {
        if tokens[i].kind != lexer::IDENT || tokens[i].text != "loop"
            && tokens[i].text != "while" {
            continue;
        }
        let open = loop_body_open(tokens, i, tokens.len);
        if open < 0 {
            continue;
        }
        if tokens[i].text == "while" {
            let first, last = unwrapped_expression(tokens, i + 1, open);
            if first != last || first >= open || tokens[first].text != "true" {
                continue;
            }
        }
        let close = matching_delimiter(tokens, open, "{", "}");
        if close > open && !loop_has_visible_exit(tokens, open, close) {
            add(issues, tokens[i].line, tokens[i].column, 19);
        }
    }
}
