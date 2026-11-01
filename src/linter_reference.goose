// Detect value bindings that are later used as pool references.
namespace linter;

import config;
import formatter;
import lexer;

fn containing_block_end(tokens: lexer::Token[:], index: i64) -> i64 {
    var nested: i64 = 0;
    var i = index - 1;
    while i >= 0 {
        if tokens[i].text == "}" {
            nested += 1;
        } else if tokens[i].text == "{" {
            if nested == 0 {
                return matching_delimiter(tokens, i, "{", "}");
            }
            nested -= 1;
        }
        i -= 1;
    }
    return tokens.len;
}

fn assignment_operator(text: const u8[:]) -> bool {
    return text == "=" || text == ".=" || text == "+=" || text == "-="
        || text == "*=" || text == "/=" || text == "%=" || text == "&="
        || text == "|=" || text == "^=" || text == "<<=" || text == ">>=";
}

fn binding_statement_end(tokens: lexer::Token[:], start: i64, end: i64) -> i64 {
    var depth = nesting();
    for i in start..end {
        if at_top(depth) && tokens[i].text == ";" {
            return i;
        }
        advance_nesting(depth, tokens[i], false);
    }
    return end;
}

fn nonfixed_storage(tokens: lexer::Token[:], start: i64, end: i64) -> bool {
    var i = start;
    while i < end {
        let next = formatter::next_significant(tokens, i + 1);
        if (tokens[i].text == "varint" || tokens[i].text == "..")
            && (next >= end || tokens[next].text != "&") {
            return true;
        }
        if tokens[i].text != "[" {
            i += 1;
            continue;
        }
        let close = matching_delimiter(tokens, i, "[", "]");
        if close < 0 || close >= end {
            return false;
        }
        let after = formatter::next_significant(tokens, close + 1);
        let inner = formatter::next_significant(tokens, i + 1);
        if (after >= end || tokens[after].text != "&")
            && (inner == close || tokens[inner].text == ">" || tokens[inner].text == "varint") {
            return true;
        }
        i = close + 1;
    }
    return false;
}

fn nonfixed_struct(tokens: lexer::Token[:], name: const u8[:]) -> bool {
    for i in tokens.len {
        if tokens[i].text != "struct" {
            continue;
        }
        let declared = formatter::next_significant(tokens, i + 1);
        if declared >= tokens.len || tokens[declared].text != name {
            continue;
        }
        let open = loop_body_open(tokens, declared, tokens.len);
        if open < 0 {
            return false;
        }
        let close = matching_delimiter(tokens, open, "{", "}");
        var field = open + 1;
        while field < close {
            if tokens[field].text != ":" {
                field += 1;
                continue;
            }
            var end = field + 1;
            while end < close && tokens[end].text != "," && tokens[end].text != "=" {
                end += 1;
            }
            if nonfixed_storage(tokens, field + 1, end) {
                return true;
            }
            field = end + 1;
        }
    }
    return false;
}

fn nonfixed_initializer(tokens: lexer::Token[:], start: i64, end: i64) -> bool {
    if tokens[start].text == "[" {
        return formatter::next_significant(tokens, start + 1) < end
            && tokens[formatter::next_significant(tokens, start + 1)].text == "]";
    }
    if tokens[start].kind != lexer::IDENT {
        return false;
    }
    if nonfixed_struct(tokens, tokens[start].text) {
        return true;
    }
    // Resolve explicit local annotations when the inserted value is a variable.
    for i in start {
        if tokens[i].text != tokens[start].text {
            continue;
        }
        let colon = formatter::next_significant(tokens, i + 1);
        if colon >= start || tokens[colon].text != ":" {
            continue;
        }
        var type_end = colon + 1;
        while type_end < start && tokens[type_end].text != "=" && tokens[type_end].text != ";"
            && tokens[type_end].text != "," && tokens[type_end].text != ")" {
            type_end += 1;
        }
        if nonfixed_storage(tokens, colon + 1, type_end) {
            return true;
        }
    }
    return false;
}

fn find_binding_operator(
    tokens: lexer::Token[:],
    name_index: i64,
    limit: i64,
    generic: bool[:]
) -> i64 {
    var depth = nesting();
    var i = name_index + 1;
    while i < limit {
        let text = tokens[i].text;
        if assignment_operator(text) && at_top(depth) {
            return i;
        } else if (text == ";" || text == ",") && at_top(depth) {
            return -1;
        }
        advance_nesting(depth, tokens[i], generic[i]);
        i += 1;
    }
    return -1;
}

fn allocator_initializer(tokens: lexer::Token[:], assign: i64, end: i64) -> bool {
    let first, last = unwrapped_expression(tokens, assign + 1, end);
    var depth = nesting();
    for i in first..last + 1 {
        if tokens[i].kind == lexer::IDENT && (tokens[i].text == "push"
            || tokens[i].text == "alloc_ref") && at_top(depth) {
            let previous = formatter::previous_significant(tokens, i);
            let next = formatter::next_significant(tokens, i + 1);
            if previous >= 0 && tokens[previous].text == "." && next < end
                && tokens[next].text == "(" && matching_delimiter(tokens, next, "(", ")") == last {
                let value = formatter::next_significant(tokens, next + 1);
                return value < last && !nonfixed_initializer(tokens, value, last);
            }
        }
        advance_nesting(depth, tokens[i], false);
    }
    return false;
}

fn member_write_after(tokens: lexer::Token[:], name_index: i64, end: i64) -> bool {
    var next = formatter::next_significant(tokens, name_index + 1);
    while next < end {
        if tokens[next].text == "." {
            let member = formatter::next_significant(tokens, next + 1);
            if member >= end {
                return false;
            }
            next = formatter::next_significant(tokens, member + 1);
            continue;
        }
        if tokens[next].text == "[" {
            let close = matching_delimiter(tokens, next, "[", "]");
            if close < 0 || close >= end {
                return false;
            }
            next = formatter::next_significant(tokens, close + 1);
            continue;
        }
        return assignment_operator(tokens[next].text);
    }
    return false;
}

fn linked_assignment_before(tokens: lexer::Token[:], name_index: i64) -> bool {
    let assignment = formatter::previous_significant(tokens, name_index);
    if assignment < 0 || !assignment_operator(tokens[assignment].text) {
        return false;
    }
    let left = formatter::previous_significant(tokens, assignment);
    if left < 0 {
        return false;
    }
    let left_prefix = formatter::previous_significant(tokens, left);
    return tokens[left].text == "]" || left_prefix >= 0 && tokens[left_prefix].text == ".";
}

fn shadows_binding(tokens: lexer::Token[:], index: i64, name: const u8[:]) -> bool {
    let keyword = tokens[index].text;
    if keyword != "let" && keyword != "var" && keyword != "const" && keyword != "for" {
        return false;
    }
    var i = formatter::next_significant(tokens, index + 1);
    while i < tokens.len {
        if tokens[i].text == "&" {
            i = formatter::next_significant(tokens, i + 1);
        }
        if i >= tokens.len || tokens[i].kind != lexer::IDENT {
            return false;
        }
        if tokens[i].text == name {
            return true;
        }
        i = formatter::next_significant(tokens, i + 1);
        if i >= tokens.len || tokens[i].text != "," {
            return false;
        }
        i = formatter::next_significant(tokens, i + 1);
    }
    return false;
}

fn later_reference_mutation(
    tokens: lexer::Token[:],
    name: const u8[:],
    start: i64,
    end: i64
) -> bool {
    var i = start;
    while i < end {
        if tokens[i].text == "fn" {
            let open, close = function_body(tokens, i);
            if open >= 0 && close > open {
                i = close + 1;
                continue;
            }
        }
        if shadows_binding(tokens, i, name) {
            var shadow_end = containing_block_end(tokens, i);
            if tokens[i].text == "for" {
                let open = loop_body_open(tokens, i, end);
                if open >= 0 {
                    shadow_end = matching_delimiter(tokens, open, "{", "}");
                }
            }
            if shadow_end >= end || shadow_end < i {
                return false;
            }
            i = shadow_end + 1;
            continue;
        }
        if tokens[i].kind == lexer::IDENT && tokens[i].text == name {
            let previous = formatter::previous_significant(tokens, i);
            let next = formatter::next_significant(tokens, i + 1);
            let is_local = previous < 0 || tokens[previous].text != "." && tokens[previous].text != "::";
            if is_local && next < end {
                if tokens[next].text == "=" || tokens[next].text == ".=" {
                    return false;
                }
                if member_write_after(tokens, i, end) {
                    return true;
                }
                if tokens[next].text != "." && tokens[next].text != "["
                    && linked_assignment_before(tokens, i) {
                    return true;
                }
            }
        }
        i += 1;
    }
    return false;
}

fn lint_reference_bind_push(
    tokens: lexer::Token[:],
    generic: bool[:],
    options: config::Options,
    issues: Issue[>..]&
) {
    if !options.lint_reference_bind_push {
        return;
    }
    for i in tokens.len {
        if tokens[i].text != "let" && tokens[i].text != "var" {
            continue;
        }
        let name = formatter::next_significant(tokens, i + 1);
        if name >= tokens.len || tokens[name].kind != lexer::IDENT {
            continue;
        }
        let scope_end = containing_block_end(tokens, i);
        let assign = find_binding_operator(tokens, name, scope_end, generic);
        if assign < 0 || tokens[assign].text != "=" {
            continue;
        }
        let statement_end = binding_statement_end(tokens, assign + 1, scope_end);
        if !allocator_initializer(tokens, assign, statement_end) {
            continue;
        }
        let after_statement = if statement_end < scope_end {
            statement_end + 1
        } else {
            statement_end
        };
        if later_reference_mutation(tokens, tokens[name].text, after_statement, scope_end) {
            add(issues, tokens[name].line, tokens[name].column, 17);
        }
    }
}
