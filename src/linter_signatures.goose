// Parameter and return-value limits, independent of function modifiers.
namespace linter;

import config;
import formatter;
import lexer;

fn signature_returns(tokens: lexer::Token[:], close: i64, generic: bool[:]) -> i64 {
    let arrow = formatter::next_significant(tokens, close + 1);
    if arrow >= tokens.len || tokens[arrow].text != "->" {
        return 0;
    }
    var end = arrow + 1;
    var depth = nesting();
    while end < tokens.len {
        if at_top(depth) && (tokens[end].text == "{" || tokens[end].text == ";") {
            break;
        }
        advance_nesting(depth, tokens[end], generic[end]);
        end += 1;
    }
    return top_level_count(tokens, arrow + 1, end, generic);
}

fn lint_signature(
    tokens: lexer::Token[:], index: i64, generic: bool[:],
    options: config::Options, issues: Issue[>..]&
) {
    let token = tokens[index];
    if token.kind != lexer::IDENT || token.text != "fn" || function_name_index(tokens, index) < 0 {
        return;
    }
    let open, close = function_parameters(tokens, index);
    if close < 0 {
        return;
    }
    if options.lint_naming {
        check_parameter_names(tokens, open + 1, close, generic, issues);
    }
    if !options.lint_signatures {
        return;
    }
    if top_level_count(tokens, open + 1, close, generic) > options.max_function_parameters {
        add(issues, token.line, token.column, 8);
    }
    if signature_returns(tokens, close, generic) > options.max_function_returns {
        add(issues, token.line, token.column, 9);
    }
}
