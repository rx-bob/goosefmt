// .goosefmt.toml loading and defaults.
namespace config;

import os;
import std;

struct Options {
    indent_width: i64,
    max_line_length: i64,
    max_file_lines: i64,
    max_function_parameters: i64,
    max_function_returns: i64,
    max_function_lines: i64,
    final_newline: bool,
    lint_indentation: bool,
    lint_spacing: bool,
    lint_statement_lines: bool,
    lint_line_length: bool,
    lint_final_newline: bool,
    lint_naming: bool,
    lint_signatures: bool,
    lint_file_length: bool,
    lint_import_order: bool,
    lint_redundant_condition_parens: bool,
    lint_function_length: bool,
    lint_extern_const_slice: bool,
    lint_const_global_naming: bool,
    lint_reference_bind_push: bool,
    lint_split_compound_assert: bool,
    lint_bounded_control_flow: bool,
    strict_safety: bool,
}

fn defaults() -> Options {
    return Options {
        indent_width: 4,
        max_line_length: 120,
        max_file_lines: 500,
        max_function_parameters: 6,
        max_function_returns: 3,
        max_function_lines: 70,
        final_newline: true,
        lint_indentation: true,
        lint_spacing: true,
        lint_statement_lines: true,
        lint_line_length: true,
        lint_final_newline: true,
        lint_naming: true,
        lint_signatures: true,
        lint_file_length: true,
        lint_import_order: true,
        lint_redundant_condition_parens: true,
        lint_function_length: true,
        lint_extern_const_slice: true,
        lint_const_global_naming: true,
        lint_reference_bind_push: true,
        lint_split_compound_assert: true,
        lint_bounded_control_flow: true,
        strict_safety: false,
    };
}

fn set_integer(options: Options&, section: const u8[:], key: const u8[:], value: const u8[:]) -> const u8[:] {
    let parsed,
    ok = parse_int(value);
    if !ok || parsed < 1 {
        return "expected a positive integer";
    }
    if section == "format" && key == "indent_width" {
        if parsed > 16 {
            return "format.indent_width must be at most 16";
        }
        options.indent_width = parsed;
        return "";
    }
    if section == "format" && key == "max_line_length" {
        options.max_line_length = parsed;
        return "";
    }
    if section == "lint" && key == "max_line_length" {
        options.max_line_length = parsed;
        return "";
    }
    if section == "lint" && key == "max_file_lines" {
        options.max_file_lines = parsed;
        return "";
    }
    if section == "lint" && key == "max_function_parameters" {
        options.max_function_parameters = parsed;
        return "";
    }
    if section == "lint" && key == "max_function_returns" {
        options.max_function_returns = parsed;
        return "";
    }
    if section == "lint" && key == "max_function_lines" {
        options.max_function_lines = parsed;
        return "";
    }
    return "unknown setting";
}

fn set_boolean(options: Options&, section: const u8[:], key: const u8[:], value: const u8[:]) -> const u8[:] {
    let enabled = value == "true";
    if !enabled && value != "false" {
        return "expected true or false";
    }
    if section == "format" && key == "final_newline" {
        options.final_newline = enabled;
        return "";
    }
    if section != "lint" {
        return "unknown setting";
    }
    if key == "indentation" {
        options.lint_indentation = enabled;
        return "";
    }
    if key == "spacing" {
        options.lint_spacing = enabled;
        return "";
    }
    if key == "one_statement_per_line" {
        options.lint_statement_lines = enabled;
        return "";
    }
    if key == "line_length" {
        options.lint_line_length = enabled;
        return "";
    }
    if key == "final_newline" {
        options.lint_final_newline = enabled;
        return "";
    }
    if key == "naming" {
        options.lint_naming = enabled;
        return "";
    }
    if key == "signature_size" {
        options.lint_signatures = enabled;
        return "";
    }
    if key == "file_length" {
        options.lint_file_length = enabled;
        return "";
    }
    return set_extended_boolean(options, key, enabled);
}

fn set_extended_boolean(options: Options&, key: const u8[:], enabled: bool) -> const u8[:] {
    if key == "import_order" {
        options.lint_import_order = enabled;
        return "";
    }
    if key == "redundant_condition_parens" {
        options.lint_redundant_condition_parens = enabled;
        return "";
    }
    if key == "function_length" {
        options.lint_function_length = enabled;
        return "";
    }
    if key == "extern_const_slice" {
        options.lint_extern_const_slice = enabled;
        return "";
    }
    if key == "const_global_naming" {
        options.lint_const_global_naming = enabled;
        return "";
    }
    if key == "reference_bind_push" {
        options.lint_reference_bind_push = enabled;
        return "";
    }
    if key == "split_compound_assert" {
        options.lint_split_compound_assert = enabled;
        return "";
    }
    if key == "bounded_control_flow" {
        options.lint_bounded_control_flow = enabled;
        return "";
    }
    if key == "strict_safety" {
        options.strict_safety = enabled;
        return "";
    }
    return "unknown setting";
}

fn load(path: const u8[:]) -> Options, const u8[:] {
    var options = defaults();
    if path.len == 0 || !file_exists(path) {
        return options,
        "";
    }

    var contents: u8[>..] = [];
    if !read_file(path, contents) {
        return options,
        "cannot read config file";
    }
    var section: const u8[:] = "";
    var line_number: i64 = 0;
    var start: i64 = 0;
    while start <= contents.len {
        var end = start;
        while end < contents.len && contents[end] != '\n' {
            end += 1;
        }
        line_number += 1;
        let line = trim(contents[start..end]);
        start = end + 1;
        if line.len == 0 || line[0] == '#' {
            continue;
        }
        if line == "[format]" {
            section = "format";
            continue;
        }
        if line == "[lint]" {
            section = "lint";
            continue;
        }

        let equals = find(line, "=");
        if equals < 0 {
            return options,
            "invalid config syntax: expected key = value";
        }
        let key = trim(line[0..equals]);
        let value = trim(line[equals + 1..]);
        var error: const u8[:] = "";
        if value == "true" || value == "false" {
            error = set_boolean(options, section, key, value);
        } else {
            error = set_integer(options, section, key, value);
        }
        if error.len > 0 {
            return options,
            "invalid or unknown config setting";
        }
    }
    return options,
    "";
}
