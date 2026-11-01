// goosefmt: a command-line formatter and linter for Goose source files.

import os;
import std;

import config;
import formatter;
import linter;

struct Totals {
    issues: i64,
    changed: i64,
    errors: i64,
}

struct PathRef {
    start: i64,
    len: i64,
}

fn enqueue(paths: PathRef[>..]&, pool: u8[>..]&, value: const u8[:]) {
    let start = pool.len;
    pool.append(value);
    pool.push(0);
    paths.push(PathRef {
            start: start,
            len: value.len
        });
}

fn print_issue(path: const u8[:], issue: linter::Issue) {
    print(path, ":", issue.line, ":", issue.column, ": error: [",
        linter::rule_name(issue.rule), "] ", linter::description(issue.rule), "\n");
}

fn excluded_directory(name: const u8[:]) -> bool {
    return name.len == 0 || name[0] == '.' || name == "node_modules"
        || name == "target" || name == "build" || name == "dist"
        || name == "vendor" || name == "coverage";
}

fn join_path(directory: const u8[:], name: const u8[:]) -> u8[>..] {
    if directory.len > 0 && directory[directory.len - 1] == '/' {
        return str(directory, name);
    }
    return str(directory, "/", name);
}

fn visit_file(
    path: const u8[:],
    action: const u8[:],
    check_only: bool,
    options: config::Options
) -> i64, i64, i64 {
    var issues_total: i64 = 0;
    var changed_total: i64 = 0;
    var errors_total: i64 = 0;

    if !ends_with(path, ".goose") {
        return 0,
        0,
        0;
    }
    var source: u8[>..] = [];
    if !read_file(path, source) {
        write_stderr(str("goosefmt: cannot read file: ", path, "\n"));
        return 0,
        0,
        1;
    }

    if action == "lint" || action == "check" {
        let found = linter::lint(source, options);
        for issue in found {
            print_issue(path, issue);
            issues_total += 1;
        }
    }

    if action == "format" || action == "check" {
        let format_options = formatter::FormatConfig {
            indent_width: options.indent_width,
            final_newline: options.final_newline,
        };
        let formatted = formatter::format_source(source, format_options);
        if formatted != source {
            changed_total += 1;
            if action == "format" && !check_only {
                if !write_file_atomic(path, formatted) {
                    write_stderr(str("goosefmt: cannot write file: ", path, "\n"));
                    errors_total += 1;
                }
            } else {
                print(path, ": needs formatting\n");
            }
        }
    }
    return issues_total,
    changed_total,
    errors_total;
}

fn run_stdin(action: const u8[:], check_only: bool, options: config::Options) -> i64 {
    var source: u8[>..] = [];
    read_stdin(source);
    if action == "lint" || action == "check" {
        let found = linter::lint(source, options);
        for issue in found {
            print_issue("stdin", issue);
        }
        if found.len > 0 {
            return 1;
        }
    }
    if action == "format" || action == "check" {
        let format_options = formatter::FormatConfig {
            indent_width: options.indent_width,
            final_newline: options.final_newline,
        };
        let formatted = formatter::format_source(source, format_options);
        if action == "format" && !check_only {
            write_stdout(formatted);
        } else if formatted != source {
            print("stdin: needs formatting\n");
            return 1;
        }
    }
    return 0;
}

fn help() {
    print("goosefmt - format and lint Goose source files\n\n");
    print("Usage: goosefmt [format|lint|check] [options] [path ...]\n\n");
    print("Commands:\n");
    print("  format   Format .goose files in place (default command)\n");
    print("  lint     Report style issues\n");
    print("  check    Report lint issues and files that need formatting\n\n");
    print("Options:\n");
    print("  --check         Do not write files; return failure when formatting differs\n");
    print("  --config FILE   Read settings from .goosefmt.toml or FILE\n");
    print("  --help          Show this help\n");
    print("  -               Read Goose source from stdin\n\n");
    print("With no paths, the current directory is scanned recursively.\n");
}

fn parse_arguments(
    start: i64, action: const u8[:], paths: PathRef[>..]&, path_pool: u8[>..]&
) -> const u8[:], bool, bool {
    let argv = args();
    var config_path: const u8[:] = ".goosefmt.toml";
    var config_explicit = false;
    var check_only = action == "check";
    var i = start;
    while i < argv.len {
        if argv[i] == "--help" || argv[i] == "-h" {
            help();
            exit(0);
        }
        if argv[i] == "--check" {
            check_only = true;
            i += 1;
            continue;
        }
        if argv[i] == "--config" {
            if i + 1 >= argv.len {
                write_stderr("goosefmt: --config requires a path\n");
                exit(2);
            }
            config_path = argv[i + 1];
            config_explicit = true;
            i += 2;
            continue;
        }
        if argv[i].starts_with("--config=") {
            config_path = argv[i][9..];
            config_explicit = true;
            i += 1;
            continue;
        }
        if argv[i].starts_with("-") && argv[i] != "-" {
            write_stderr(str("goosefmt: unknown option: ", argv[i], "\n"));
            exit(2);
        }
        enqueue(paths, path_pool, argv[i]);
        i += 1;
    }

    return config_path, config_explicit, check_only;
}

fn visit_paths(
    paths: PathRef[>..]&, path_pool: u8[>..]&, action: const u8[:],
    check_only: bool, options: config::Options
) -> Totals {
    var totals = Totals {
        issues: 0,
        changed: 0,
        errors: 0
    };
    var cursor: i64 = 0;
    while cursor < paths.len {
        let path_ref = paths[cursor];
        var path: u8[>..] = [];
        path.append(path_pool[path_ref.start..path_ref.start + path_ref.len]);
        cursor += 1;
        if is_dir(path) {
            var listing: u8[>..] = [];
            if !list_dir(path, listing) {
                write_stderr(str("goosefmt: cannot list directory: ", path, "\n"));
                totals.errors += 1;
                continue;
            }
            each_split(listing, '\n') {
                name =>
                if !excluded_directory(name) {
                    let child = join_path(path, name);
                    enqueue(paths, path_pool, child);
                }
            };
        } else {
            let issues,
            changed,
            errors = visit_file(path, action, check_only, options);
            totals.issues += issues;
            totals.changed += changed;
            totals.errors += errors;
        }
    }

    return totals;
}

fn main() {
    let argv = args();
    if argv.len <= 1 {
        help();
        return;
    }

    var action: const u8[:] = "format";
    var start: i64 = 1;
    if argv.len > 1 && (argv[1] == "format" || argv[1] == "lint" || argv[1] == "check") {
        action = argv[1];
        start = 2;
    }

    var paths: PathRef[>..] = [];
    var path_pool: u8[>..] = [];
    var config_path, config_explicit, check_only = parse_arguments(start, action, paths, path_pool);
    if config_explicit && !file_exists(config_path) {
        write_stderr(str("goosefmt: config file does not exist: ", config_path, "\n"));
        exit(2);
    }
    if !config_explicit && !file_exists(config_path) {
        config_path = "";
    }
    let options,
    config_error = config::load(config_path);
    if config_error.len > 0 {
        write_stderr(str("goosefmt: ", config_error, "\n"));
        exit(2);
    }

    if paths.len == 0 {
        enqueue(paths, path_pool, ".");
    }
    if paths.len == 1 && path_pool[paths[0].start..paths[0].start + paths[0].len] == "-" {
        exit(run_stdin(action, check_only, options));
    }

    let totals = visit_paths(paths, path_pool, action, check_only, options);
    if action == "format" && check_only && totals.changed > 0 {
        print("goosefmt: ", totals.changed, " file(s) need formatting\n");
    }
    if action == "lint" && totals.issues == 0 {
        print("goosefmt: no lint issues\n");
    }
    if totals.errors > 0 || totals.issues > 0 || (check_only && totals.changed > 0) {
        exit(1);
    }
}
