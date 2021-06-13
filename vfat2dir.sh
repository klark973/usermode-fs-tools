#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020-2021, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### vfat2dir {VERSION}
### Unpack contents of the vfat image

# Defaults
progname="${0##*/}"
options="-n -p -Q -m -i"
target=
image=
files=


show_help() {
	cat <<-EOF
	Usage: $progname [<options>...] [--] [<target>] <image> [<files>...]

	Options:
	  -s, --subdir           Recursive copy directories and their contents.
	  -q, --quiet            Suppress additional diagnostic.
	  -v, --version          Show this program version and exit.
	  -h, --help             Show this help message and exit.

	Please, report bugs to https://bugzilla.altlinux.org/
	EOF
	exit 0
}

show_version() {
	printf "%s %s\n" "$progname" "{VERSION}"
	exit 0
}

autoreq() {
	cat
	getopt
	mcopy
	realpath
}

fatal() {
	local fmt="$1"; shift

	printf "%s fatal: $fmt\n" "$progname" "$@" >&2
	exit 1
}

parse_args() {
	local s_opts="+qsvh"
	local l_opts="quiet,subdir,version,help"
	local msg="Invalid command-line usage, try '-h' for help."
	local verbose=1 subdir=0

	l_opts=$(getopt -n "$progname" -o "$s_opts" -l "$l_opts" -- "$@") ||
		fatal "$msg"
	target="$(realpath .)"
	eval set -- "$l_opts"
	while [ $# -gt 0 ]; do
		case "$1" in
		-q|--quiet)
			verbose=0
			;;
		-s|--subdir)
			subdir=1
			;;
		-v|--version)
			show_version
			;;
		-h|--help)
			show_help
			;;
		--)	shift
			break
			;;
		*)	break
			;;
		esac
		shift
	done

	if [ $# -gt 0 -a -d "${1-}" ]; then
		target="$(realpath -- "$1")"
		shift
	fi
	[ -s "${1-}" ] ||
		fatal "VFAT image not found: '%s'." "${1-}"
	[ $subdir -eq 0 ] ||
		options="-s $options"
	[ $verbose -eq 0 ] ||
		options="-v $options"
	image="$1"; shift
	if [ $# -eq 0 ]; then
		files="::"
	else
		while [ $# -gt 0 ]; do
			[ -z "$1" ] ||
				files="$files ::\"$1\""
			shift
		done
	fi
}


# Entry point
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

eval mcopy $options "$image" $files "$target"

