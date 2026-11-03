#!/usr/bin/env tclsh
# Compatibility launcher for GMA Mapper 5.0.0-alpha.1 (Python/PySide6 port).
# Accepts legacy `wish` / `gma` CLI invocations (including `--`, `-geometry`, `-display`)
# and delegates to `gma-mapper` or `python -m gma_mapper`.
# Pass `--legacy-tk` to invoke the archived Tcl/Tk implementation (`bin/mapper_legacy.tcl`).

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file dirname $script_dir]

if {[lsearch -exact $argv "--legacy-tk"] >= 0} {
    set idx [lsearch -exact $argv "--legacy-tk"]
    set argv [lreplace $argv $idx $idx]
    source [file join $script_dir "mapper_legacy.tcl"]
    return
}

if {[auto_execok gma-mapper] ne ""} {
    exec {*}[auto_execok gma-mapper] {*}$argv >@stdout 2>@stderr <@stdin
    exit 0
}

set env(PYTHONPATH) [file join $repo_root "src"]
foreach py {python3 python} {
    if {[auto_execok $py] ne ""} {
        exec {*}[auto_execok $py] -m gma_mapper {*}$argv >@stdout 2>@stderr <@stdin
        exit 0
    }
}

puts stderr "Error: Neither 'gma-mapper' nor 'python3'/'python' was found in PATH."
exit 1
