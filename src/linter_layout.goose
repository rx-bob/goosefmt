// Whitespace and physical line diagnostics.
namespace linter;

import config;
import formatter;
import lexer;

struct LineState {
    depth: Nesting,
    token_index: i64,
    line_number: i64,
}

fn check_indent(
    line: const u8[:], tokens: lexer::Token[:], state: LineState,
    options: config::Options, issues: Issue[>..]&
) {
    var actual: i64 = 0;
    var has_tab = false;
    while actual < line.len && (line[actual] == ' ' || line[actual] == '\t') {
        if line[actual] == '\t' {
            has_tab = true;
        }
        actual += 1;
    }
    var expected_depth = state.depth.braces;
    if line[actual] == '}' && expected_depth > 0 {
        expected_depth -= 1;
    }
    let parens = state.depth.parens;
    let squares = state.depth.squares;
    var continuation = parens > 0 || squares > 0;
    if line[actual] == ')' {
        continuation = parens > 1 || squares > 0;
    }
    if line[actual] == ']' {
        continuation = parens > 0 || squares > 1;
    }
    if continuation {
        expected_depth += 1;
    }
    let index = state.token_index;
    if index < tokens.len && tokens[index].line == state.line_number
        && binary_operator(tokens[index].text) && !unary(tokens, index)
        && parens == 0 && squares == 0 {
        expected_depth += 1;
    }
    if has_tab || actual != expected_depth * options.indent_width {
        add(issues, state.line_number, 1, 1);
    }
}

fn lint_lines(source: const u8[:], tokens: lexer::Token[:], options: config::Options, issues: Issue[>..]&) {
    let lines = split(source, '\n');
    let protected = protected_lines(tokens, lines.len);
    let long_literals = long_literal_lines(tokens, lines.len, options.max_line_length);
    var state = LineState {
        depth: nesting(),
        token_index: 0,
        line_number: 1
    };
    for i in lines.len {
        var line = lines[i];
        if line.len > 0 && line[line.len - 1] == '\r' {
            line = line[0..line.len - 1];
        }
        state.line_number = i + 1;
        if options.lint_line_length && line.len > options.max_line_length
            && !protected[i] && !long_literals[i] {
            add(issues, i + 1, options.max_line_length + 1, 6);
        }
        if options.lint_indentation && trim(line).len > 0 && !protected[i] {
            check_indent(line, tokens, state, options, issues);
        }
        while state.token_index < tokens.len && tokens[state.token_index].line == state.line_number {
            advance_nesting(state.depth, tokens[state.token_index], false);
            state.token_index += 1;
        }
    }
    let missing_newline = source.len > 0 && source[source.len - 1] != '\n';
    if options.lint_final_newline && missing_newline {
        add(issues, lines.len, lines[lines.len - 1].len + 1, 7);
    }
    let counted_lines = lines.len - (if missing_newline {
            0
        } else {
            1
        });
    if options.lint_file_length && counted_lines > options.max_file_lines {
        add(issues, options.max_file_lines + 1, 1, 10);
    }
}

fn lint_spacing(
    tokens: lexer::Token[:], i: i64, square_depth: i64,
    options: config::Options, issues: Issue[>..]&
) {
    let token = tokens[i];
    if options.lint_statement_lines && token.text == ";" && square_depth == 0 {
        let next = formatter::next_significant(tokens, i + 1);
        if next < tokens.len && tokens[next].text != "}" && tokens[next].line == token.line {
            add(issues, token.line, token.column, 5);
        }
    }
    let next = i + 1;
    if options.lint_spacing && token.text == "," && next < tokens.len
        && tokens[next].kind != lexer::NEWLINE && tokens[next].text != ")"
        && tokens[next].text != "]" && tokens[next].text != "}"
        && tokens[next].start == token.end {
        add(issues, token.line, token.column, 3);
    }
    if options.lint_spacing && token.text == ":" && square_depth == 0 {
        if next < tokens.len && tokens[next].kind != lexer::NEWLINE && tokens[next].text != ")"
            && tokens[next].text != "," && tokens[next].text != "}" && token.end == tokens[next].start {
            add(issues, token.line, token.column, 4);
        }
        if i > 0 && tokens[i - 1].end != token.start {
            add(issues, token.line, token.column, 4);
        }
    }
    if options.lint_naming && token.text == ":" {
        let name = formatter::previous_significant(tokens, i);
        let before = formatter::previous_significant(tokens, name);
        if name >= 0 && before >= 0 && tokens[name].kind == lexer::IDENT
            && (tokens[before].text == "{" || tokens[before].text == ",")
            && !snake_case(tokens[name].text) {
            add(issues, tokens[name].line, tokens[name].column, 11);
        }
    }
}

fn lint_operator_spacing(
    tokens: lexer::Token[:], i: i64, square_depth: i64, generic: bool[:], issues: Issue[>..]&
) {
    let token = tokens[i];
    if token.kind != lexer::OPERATOR || !binary_operator(token.text) || unary(tokens, i) || generic[i]
        || formatter::is_array_bound(tokens, i, square_depth)
        || token.text == "&" && formatter::is_type_reference(tokens, i) {
        return;
    }
    let missing_before = i > 0 && tokens[i - 1].kind != lexer::NEWLINE && tokens[i - 1].end == token.start;
    let missing_after = i + 1 < tokens.len && tokens[i + 1].kind != lexer::NEWLINE
        && tokens[i + 1].start == token.end;
    if missing_before || missing_after {
        add(issues, token.line, token.column, 2);
    }
}
