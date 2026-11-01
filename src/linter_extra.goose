// Goose-specific diagnostics added by the formatter evolution roadmap.
namespace linter;

import config;
import formatter;
import lexer;
import linter_control;
import linter_reference;

fn lint_import_order(tokens: lexer::Token[:], issues: Issue[>..]&) {
    let problems = formatter::import_problems(tokens);
    for problem in problems {
        add(issues, problem.line, problem.column, 12);
    }
}

fn redundant_parentheses(tokens: lexer::Token[:], keyword_index: i64) -> bool {
    let open = formatter::next_significant(tokens, keyword_index + 1);
    if open >= tokens.len || tokens[open].text != "(" {
        return false;
    }
    let close = matching_delimiter(tokens, open, "(", ")");
    if close < 0 {
        return false;
    }
    let next = formatter::next_significant(tokens, close + 1);
    let keyword = tokens[keyword_index].text;
    if keyword == "return" {
        return next < tokens.len && (tokens[next].text == ";" || tokens[next].text == "}");
    }
    if keyword == "guard" {
        if next >= tokens.len || tokens[next].text != "else" {
            return false;
        }
        let brace = formatter::next_significant(tokens, next + 1);
        return brace < tokens.len && tokens[brace].text == "{";
    }
    return next < tokens.len && tokens[next].text == "{";
}

fn lint_redundant_parentheses(tokens: lexer::Token[:], issues: Issue[>..]&) {
    for i in tokens.len {
        if tokens[i].kind == lexer::IDENT && (tokens[i].text == "if"
            || tokens[i].text == "while" || tokens[i].text == "for"
            || tokens[i].text == "guard" || tokens[i].text == "match"
            || tokens[i].text == "return") && redundant_parentheses(tokens, i) {
            let open = formatter::next_significant(tokens, i + 1);
            add(issues, tokens[open].line, tokens[open].column, 13);
        }
    }
}

fn extern_parameter_has_nonconst_slice(
    tokens: lexer::Token[:],
    start: i64,
    end: i64,
    generic: bool[:]
) -> bool {
    var colon = -1;
    for i in start..end {
        if tokens[i].text == ":" {
            colon = i;
            break;
        }
    }
    if colon < 0 {
        return false;
    }
    let type_start = formatter::next_significant(tokens, colon + 1);
    if type_start >= end || tokens[type_start].text == "const" || tokens[type_start].text == "fn" {
        return false;
    }
    var depth = nesting();
    var i = type_start;
    while i < end {
        if tokens[i].text == "[" && at_top(depth) {
            let inner = formatter::next_significant(tokens, i + 1);
            if inner < end && tokens[inner].text == ":" {
                let close = formatter::next_significant(tokens, inner + 1);
                if close < end && tokens[close].text == "]" {
                    return true;
                }
            }
        }
        advance_nesting(depth, tokens[i], generic[i]);
        i += 1;
    }
    return false;
}

fn lint_extern_parameters(
    tokens: lexer::Token[:],
    open: i64,
    close: i64,
    generic: bool[:],
    issues: Issue[>..]&
) {
    var segment = open + 1;
    var parens: i64 = 0;
    var squares: i64 = 0;
    var braces: i64 = 0;
    var angles: i64 = 0;
    for i in open + 1..close {
        let text = tokens[i].text;
        if text == "(" {
            parens += 1;
        } else if text == ")" && parens > 0 {
            parens -= 1;
        } else if text == "[" {
            squares += 1;
        } else if text == "]" && squares > 0 {
            squares -= 1;
        } else if text == "{" {
            braces += 1;
        } else if text == "}" && braces > 0 {
            braces -= 1;
        } else if text == "<" && generic[i] {
            angles += 1;
        } else if (text == ">" || text == ">>") && generic[i] && angles > 0 {
            angles -= if text == ">>" {
                2
            } else {
                1
            };
        } else if text == "," && parens == 0 && squares == 0 && braces == 0 && angles == 0 {
            if extern_parameter_has_nonconst_slice(tokens, segment, i, generic) {
                add(issues, tokens[segment].line, tokens[segment].column, 15);
            }
            segment = i + 1;
        }
    }
    if segment < close && extern_parameter_has_nonconst_slice(tokens, segment, close, generic) {
        add(issues, tokens[segment].line, tokens[segment].column, 15);
    }
}

fn lint_function_rules(
    tokens: lexer::Token[:],
    generic: bool[:],
    options: config::Options,
    issues: Issue[>..]&
) {
    for i in tokens.len {
        if tokens[i].kind != lexer::IDENT || tokens[i].text != "fn"
            || function_name_index(tokens, i) < 0 {
            continue;
        }
        let open_params,
        close_params = function_parameters(tokens, i);
        if close_params < 0 {
            continue;
        }
        if options.lint_extern_const_slice && function_has_modifier(tokens, i, "extern") {
            lint_extern_parameters(tokens, open_params, close_params, generic, issues);
        }
        if options.lint_function_length {
            let open_body,
            close_body = function_body(tokens, i);
            if open_body >= 0 && close_body >= 0 {
                let body_lines = tokens[close_body].end_line - tokens[open_body].line + 1;
                if body_lines > options.max_function_lines {
                    add(issues, tokens[i].line, tokens[i].column, 14);
                }
            }
        }
        if options.lint_bounded_control_flow && options.strict_safety
            && function_has_modifier(tokens, i, "recursive") {
            add(issues, tokens[i].line, tokens[i].column, 19);
        }
    }
}

fn lint_const_global_names(
    tokens: lexer::Token[:], generic: bool[:], options: config::Options, issues: Issue[>..]&
) {
    if !options.lint_const_global_naming {
        return;
    }
    var depth = nesting();
    for i in tokens.len {
        let token = tokens[i];
        if at_top(depth) && token.kind == lexer::IDENT && token.text == "const" {
            var name = formatter::next_significant(tokens, i + 1);
            while name < tokens.len && tokens[name].kind == lexer::IDENT {
                let delimiter = formatter::next_significant(tokens, name + 1);
                if delimiter >= tokens.len || tokens[delimiter].text != ":"
                    && tokens[delimiter].text != "=" && tokens[delimiter].text != "," {
                    break;
                }
                if !screaming_snake_case(tokens[name].text) {
                    add(issues, tokens[name].line, tokens[name].column, 16);
                }
                if tokens[delimiter].text != "," {
                    break;
                }
                name = formatter::next_significant(tokens, delimiter + 1);
            }
        }
        advance_nesting(depth, token, generic[i]);
    }
}

fn lint_extended(
    tokens: lexer::Token[:],
    generic: bool[:],
    options: config::Options,
    issues: Issue[>..]&
) {
    if options.lint_import_order {
        lint_import_order(tokens, issues);
    }
    if options.lint_redundant_condition_parens {
        lint_redundant_parentheses(tokens, issues);
    }
    lint_function_rules(tokens, generic, options, issues);
    lint_const_global_names(tokens, generic, options, issues);
    lint_reference_bind_push(tokens, generic, options, issues);
    lint_compound_asserts(tokens, options, issues);
    lint_bounded_control_flow(tokens, options, issues);
}
