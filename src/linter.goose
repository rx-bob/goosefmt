// Configurable Goose style diagnostics.
namespace linter;

import config;
import formatter;
import lexer;
import linter_extra;
import linter_layout;
import linter_rules;
import linter_signatures;

struct Issue {
    line: i64,
    column: i64,
    rule: i32,
}

fn add(issues: Issue[>..]&, line: i64, column: i64, rule: i32) {
    issues.push(Issue {
            line: line,
            column: column,
            rule: rule
        });
}

fn pascal_case(name: const u8[:]) -> bool {
    if name.len == 0 || name[0] < 'A' || name[0] > 'Z' {
        return false;
    }
    for i in name.len {
        let c = name[i];
        if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9')) {
            return false;
        }
    }
    return true;
}

fn check_enum_variants(tokens: lexer::Token[:], enum_index: i64, issues: Issue[>..]&) {
    var open = enum_index + 1;
    while open < tokens.len && tokens[open].text != "{" && tokens[open].text != ";" {
        open += 1;
    }
    if open >= tokens.len || tokens[open].text != "{" {
        return;
    }
    var depth: i64 = 1;
    var expect_variant = true;
    var i = open + 1;
    while i < tokens.len && depth > 0 {
        let token = tokens[i];
        if depth == 1 && expect_variant && token.kind == lexer::IDENT {
            if !pascal_case(token.text) {
                add(issues, token.line, token.column, 11);
            }
            expect_variant = false;
        }
        if token.text == "{" {
            depth += 1;
        } else if token.text == "}" {
            depth -= 1;
        }
        if depth == 1 && token.text == "," {
            expect_variant = true;
        }
        i += 1;
    }
}

fn check_parameter_name(
    tokens: lexer::Token[:],
    start: i64,
    end: i64,
    issues: Issue[>..]&
) {
    for i in start..end {
        if tokens[i].kind == lexer::IDENT && tokens[i].text != "const" {
            if tokens[i].text != "_" && !snake_case(tokens[i].text) {
                add(issues, tokens[i].line, tokens[i].column, 11);
            }
            return;
        }
    }
}

fn check_parameter_names(
    tokens: lexer::Token[:],
    start: i64,
    end: i64,
    generic: bool[:],
    issues: Issue[>..]&
) {
    var segment = start;
    var parens: i64 = 0;
    var squares: i64 = 0;
    var angles: i64 = 0;
    for i in start..end {
        let text = tokens[i].text;
        if text == "(" {
            parens += 1;
        } else if text == ")" && parens > 0 {
            parens -= 1;
        } else if text == "[" {
            squares += 1;
        } else if text == "]" && squares > 0 {
            squares -= 1;
        } else if text == "<" && generic[i] {
            angles += 1;
        } else if (text == ">" || text == ">>") && generic[i] && angles > 0 {
            angles -= if text == ">>" {
                2
            } else {
                1
            };
        } else if text == "," && parens == 0 && squares == 0 && angles == 0 {
            check_parameter_name(tokens, segment, i, issues);
            segment = i + 1;
        }
    }
    check_parameter_name(tokens, segment, end, issues);
}

fn snake_case(name: const u8[:]) -> bool {
    if name.len == 0 || name[0] == '_' {
        return false;
    }
    for i in name.len {
        let c = name[i];
        if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') {
            return false;
        }
        if c == '_' && i + 1 < name.len && name[i + 1] == '_' {
            return false;
        }
    }
    return true;
}

fn screaming_snake_case(name: const u8[:]) -> bool {
    if name.len == 0 || name[0] == '_' {
        return false;
    }
    for i in name.len {
        let c = name[i];
        if !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') {
            return false;
        }
        if c == '_' && i + 1 < name.len && name[i + 1] == '_' {
            return false;
        }
    }
    return true;
}

fn lint_binding_names(tokens: lexer::Token[:], index: i64, global: bool, issues: Issue[>..]&) {
    let constant = global && tokens[index].text == "let";
    var binding = formatter::next_significant(tokens, index + 1);
    while binding < tokens.len {
        if tokens[binding].text == "&" {
            binding = formatter::next_significant(tokens, binding + 1);
        }
        if binding >= tokens.len || tokens[binding].kind != lexer::IDENT {
            return;
        }
        let valid = if constant {
            screaming_snake_case(tokens[binding].text)
        } else {
            snake_case(tokens[binding].text)
        };
        if tokens[binding].text != "_" && !valid {
            add(issues, tokens[binding].line, tokens[binding].column, 11);
        }
        binding = formatter::next_significant(tokens, binding + 1);
        if binding >= tokens.len || tokens[binding].text != "," {
            return;
        }
        binding = formatter::next_significant(tokens, binding + 1);
    }
}

fn lint_declaration_name(tokens: lexer::Token[:], index: i64, global: bool, issues: Issue[>..]&) {
    let token = tokens[index];
    if token.kind != lexer::IDENT {
        return;
    }
    if token.text == "let" || token.text == "var" {
        lint_binding_names(tokens, index, global, issues);
    }
    let name = formatter::next_significant(tokens, index + 1);
    if name >= tokens.len {
        return;
    }
    if token.text == "namespace" && !snake_case(tokens[name].text) {
        add(issues, tokens[name].line, tokens[name].column, 11);
    }
    if token.text == "fn" {
        let function_name = function_name_index(tokens, index);
        if function_name >= 0 && !snake_case(tokens[function_name].text) {
            add(issues, tokens[function_name].line, tokens[function_name].column, 11);
        }
    }
    if (token.text == "struct" || token.text == "enum" || token.text == "type")
        && !pascal_case(tokens[name].text) {
        add(issues, tokens[name].line, tokens[name].column, 11);
    }
    if token.text == "enum" {
        check_enum_variants(tokens, index, issues);
    }
}

fn lint(source: const u8[:], options: config::Options) -> Issue[>..] {
    let tokens = lexer::lex(source);
    let generic = generic_angle_tokens(tokens);
    var issues: Issue[>..] = [];
    lint_lines(source, tokens, options, issues);
    var depth = nesting();
    for i in tokens.len {
        if options.lint_naming {
            lint_declaration_name(tokens, i, at_top(depth), issues);
        }
        advance_nesting(depth, tokens[i], generic[i]);
        lint_spacing(tokens, i, depth.squares, options, issues);
        if options.lint_spacing {
            lint_operator_spacing(tokens, i, depth.squares, generic, issues);
        }
        lint_signature(tokens, i, generic, options, issues);
    }
    lint_extended(tokens, generic, options, issues);
    return issues;
}
