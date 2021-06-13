#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020-2021, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### extfs2dir {VERSION}
### Unpack contents of the extfs image to directory

# Defaults
progname="${0##*/}"
prefix="fakeroot"
root="/"
image=
target=
quiet=0


show_help() {
	cat <<-EOF
	Usage: $progname [<options>...] [--] <image> [<target>]

	Options:
	  -q, --quiet            Suppress additional diagnostic.
	  -r, --root=<path>      Unpack specified directory only.
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
	/bin/true
	awk
	cat
	chroot
	debugfs
	fakeroot
	getopt
	realpath
	sed
}

verbose() {
	local fmt="$1"; shift

	[ $quiet -ne 0 ] || printf "$fmt\n" "$@" >&2
}

fatal() {
	local fmt="$1"; shift

	printf "%s fatal: $fmt\n" "$progname" "$@" >&2
	exit 1
}

parse_args() {
	local s_opts="+qr:vh"
	local l_opts="quiet,root,version,help"
	local msg="Invalid command-line usage, try '-h' for help."

	l_opts=$(getopt -n "$progname" -o "$s_opts" -l "$l_opts" -- "$@") ||
		fatal "$msg"
	eval set -- "$l_opts"
	while [ $# -gt 0 ]; do
		case "$1" in
		-q|--quiet)
			quiet=1
			;;
		-r|--root)
			root="${2-}"
			shift
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

	[ $# -eq 1 -o $# -eq 2 ] ||
		fatal "$msg"
	[ -s "$1" ] ||
		fatal "ExtFS image file not found: '%s'." "$1"
	image="$(realpath -- "$1")"; shift
	if [ $# -eq 0 ]; then
		target="$(realpath .)"
	else
		[ -d "$1" ] ||
			fatal "Invalid target directory: '%s'." "$1"
		target="$(realpath -- "$1")"; shift
	fi
}


# Entry point
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

if [ "$(id -u)" = "0" ]; then
	if chroot / /bin/true >/dev/null 2>&1; then
		fatal "This program can run without root privileges!"
	fi

	# Run inside hasher, it's nice: fakeroot already outside
	prefix=
fi

verbose "Option '-q' turns off verbose diagnostic."

verbose "progname='$progname'"
verbose "prefix='$prefix'"
verbose "image='$image'"
verbose "target='$target'"
verbose "quiet=$quiet"

verbose "Executing '%s'..." "debugfs -R 'rdump \"$root\" \"$target\"' -- \"$image\""
errors="$($prefix debugfs -R "rdump \"$root\" \"$target\"" -- "$image" 2>&1 |sed '1d')"
if [ "$root" != "/" -o "$errors" != "rdump: File exists while making directory $target/" ]; then
	if [ -n "$errors" ]; then
		echo "$errors" >&2
		exit 1
	fi
	exit 0
fi

# debugfs upstream commit ebb8b1aa045a0a43344c4ae581e1c342a9724d23
# fix situation for "rdump / /path/to/dir", but prior this commit
# (upstream e2fsprogs <= 1.43.0), we have fatal message at this
# point, need to use fallback...
#
verbose "Executing '%s'..." "debugfs -R 'ls -p /' -- \"$image\""
debugfs -R "ls -p /" -- "$image" 2>/dev/null |
	awk -F / '{print $3 "\t" $6;}' |
while read mode entry; do
	[ -n "$mode" -a -n "$entry" ] ||
		continue
	[ "$entry" != "." ] ||
		continue
	[ "$entry" != ".." ] ||
		continue
	verbose "Found entry: '/%s' (%s)" "$entry" "$mode"
	if [ "${mode:0:2}" = "10" ]; then
		# Unpack regular file
		cmd="dump -p \"/$entry\" \"$target/$entry\""
	elif [ "${mode:0:2}" = "04" ]; then
		# Recursively unpack directory
		cmd="rdump \"/$entry\" \"$target\""
	else
		# Symlinks, device nodes and sockets
		# in the root directory not supported
		continue
	fi
	verbose "Executing '%s'..." "debugfs -R '$cmd' -- \"$image\""
	errors="$($prefix debugfs -R "$cmd" -- "$image" 2>&1 |sed '1d')"
	if [ -n "$errors" ]; then
		echo "$errors" >&2
		exit 1
	fi
done

