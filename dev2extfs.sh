#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### dev2extfs {VERSION}
### Create /dev nodes on existing extfs image

# Defaults
progname="${0##*/}"
no_clean=0
image=
devtab=
minimal=0
cmdfile=


show_help() {
	cat <<-EOF
	Usage: $progname [<options>...] [--] [<device-table>] <image>

	Options:
	  -m, --minimal          Populate minimalistic /dev.
	  -n, --no-clean         Keep temporary files at exit.
	  -v, --version          Show this program version and exit.
	  -h, --help             Show this help message and exit.

	Device table format and examples:
	  <node>       <type> <major> <minor> <mode> <uid> <gid>
	  /dev             d       -       -      -     -   -
	  /dev/mem         c       1       1    640     0   0
	  /dev/tty         c       5       0    666     0   5
	  /dev/nvme0n1     b     259       1    660     0   6
	  /dev/initctl     p       -       -      -     -   -
	  /dev/stderr      l       -       -      -     -   /proc/self/fd/2
	  /etc/shadow      f       -       -    600     0   0
	  /usr/bin/passwd  f       -       -   2711     0   26

	Node types:
	  d  Directory,                 default mode: 0755
	  f  Regular file,              default mode: 0644
	  b  Block special device,      default mode: 0600
	  c  Character special device,  default mode: 0600
	  p  FIFO (named PIPE),         default mode: 0600
	  l  Symbolic link,             mode no changed

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
	debugfs
	getopt
	grep
	realpath
	sed
}

fatal() {
	local fmt="$1"; shift

	printf "%s fatal: $fmt\n" "$progname" "$@" >&2
	exit 1
}

parse_args() {
	local s_opts="+mnvh"
	local l_opts="minimal,no-clean,version,help"
	local msg="Invalid command-line usage, try '-h' for help."

	l_opts=$(getopt -n "$progname" -o "$s_opts" -l "$l_opts" -- "$@") ||
		fatal "$msg"
	eval set -- "$l_opts"
	while [ $# -gt 0 ]; do
		case "$1" in
		-m|--minimal)
			minimal=1
			;;
		-n|--no-clean)
			no_clean=1
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

	if [ $# -ge 2 ]; then
		[ -s "$1" ] ||
			fatal "Device table file not found: '%s'." "$1"
		devtab="$(realpath -- "$1")"
		shift
	fi
	[ $minimal -ne 0 -o -n "$devtab" ] ||
		fatal "Device table file not specified."
	[ $# -eq 1 ] ||
		fatal "$msg"
	[ -s "$1" ] ||
		fatal "ExtFS image file not found: '%s'." "$1"
	image="$(realpath -- "$1")"
	shift
}

is_dir_exists() {
	local dirspec="$1"
	local res="$(debugfs -R "cd \"$dirspec\"" -- "$image" 2>&1 |sed 1d)"

	[ -n "$res" ] ||
		return 0
	return 1
}

is_entry_exists() {
	local filespec="$1"

	debugfs -R "stat \"$filespec\"" -- "$image" 2>&1 |
		sed '2!d' |grep -q "File not found by ext" ||
			return 0
	return 1
}

parse_device_table() {
	local node type major minor mode uid gid target
	local nodedir nodename filemode lineno=0
	local old_IFS="$IFS" lastdir="/" parent=1

	IFS="	 
"
	while read node type major minor mode uid gid
	do
		lineno=$((1 + $lineno))
		[ -n "$node" -a "${node:0:1}" = "/" ] ||
			fatal "Invalid node path (%s, #%d)." "$node" $lineno
		case "$type" in
		c) # Character special device
		   [ "x$mode" != "x-" ] ||
			mode=600
		   filemode="02"
		   ;;
		b) # Block special device
		   [ "x$mode" != "x-" ] ||
			mode=600
		   filemode="06"
		   ;;
		d) # Directory
		   [ "x$mode" != "x-" ] ||
			mode=755
		   filemode="04"
		   ;;
		l) # Symbolic link
		   [ -n "$gid" ] ||
			fatal "Target required for symlink (%s, #%d)." "$node" $lineno
		   filemode="012"
		   target="$gid"
		   ;;
		f) # Regular file
		   [ "x$mode" != "x-" ] ||
			mode=644
		   filemode="010"
		   ;;
		p) # FIFO (named PIPE)
		   [ "x$mode" != "x-" ] ||
			mode=600
		   filemode="014"
		   ;;
		*) # Valid type required
		   fatal "Unexpected node type: '%s' (%s, #%d)." \
					"$type" "$node" $lineno
		   ;;
		esac

		[ "x$major" != "x-" ] ||
			major=
		[ "x$minor" != "x-" ] ||
			minor=
		[ "x$uid" != "x-" -a "x$uid" != "x0" ] ||
			uid=
		[ "x$gid" != "x-" -a "x$gid" != "x0" ] ||
			gid=
		nodedir="${node%/*}"
		nodedir="${nodedir:-/}"
		nodename="${node##*/}"
		if [ "$lastdir" != "$nodedir" ]; then
			is_dir_exists "$nodedir" &&
				parent=1 || parent=0
			printf "cd \"%s\"\n" "$nodedir"
			lastdir="$nodedir"
		fi

		case "$type" in
		d) # Directory
		   if [ $parent -eq 0 ] || ! is_dir_exists "$node"; then
			printf "mkdir \"%s\"\n" "$nodename"
		   fi
		   ;;
		p) # FIFO (named PIPE)
		   if [ $parent -ne 0 ] && is_entry_exists "$node"; then
			printf "rm \"%s\"\n" "$nodename"
		   fi
		   printf "mknod \"%s\" p\n" "$nodename"
		   ;;
		l) # Symbolic link
		   if [ $parent -ne 0 ] && is_entry_exists "$node"; then
			printf "rm \"%s\"\n" "$nodename"
		   fi
		   printf "symlink \"%s\" \"%s\"\n" "$nodename" "$target"
		   continue
		   ;;
		b|c) # Special device
		   [ -n "$major" ] ||
			fatal "Major number required for special device (%s, #%d)." \
								"$node" $lineno
		   [ -n "$minor" ] ||
			fatal "Minor number required for special device (%s, #%d)." \
								"$node" $lineno
		   if [ $parent -ne 0 ] && is_entry_exists "$node"; then
			printf "rm \"%s\"\n" "$nodename"
		   fi
		   printf "mknod \"%s\" %s %s %s\n" "$nodename" "$type" "$major" "$minor"
		   ;;
		esac

		[ -z "$gid" ] ||
			printf "sif \"%s\" gid %s\n" "$node" "$gid"
		[ -z "$uid" ] ||
			printf "sif \"%s\" uid %s\n" "$node" "$uid"
		[ "$type" = "d" -a "x$(printf '%04d' $mode)" = "x0755" ] ||
			printf "sif \"%s\" mode %s%04d\n" "$node" "$filemode" $mode
	done

	IFS="$old_IFS"
}

minimal_device_table() {
	cat <<-EOF
	/dev		d - -   755  0 0
	/dev/pts	d - -   755  0 0
	/dev/shm	d - -  1777  0 0
	/dev/ram        b 1 1   644  0 0
	/dev/null       c 1 3   666  0 0
	/dev/zero       c 1 5   666  0 0
	/dev/full       c 1 7   666  0 0
	/dev/random     c 1 8   644  0 0
	/dev/urandom	c 1 9   644  0 0
	/dev/console	c 5 1   600  0 0
	/dev/pts/ptmx	c 5 2   666  0 5
	/dev/tty0	c 4 0   620  0 5
	/dev/tty1	c 4 1   620  0 5
	/dev/tty	c 5 0   666  0 5
	/dev/ttyS0	c 4 64  660  0 14
	/dev/ttyS1	c 4 64  660  0 14
	/dev/ttyS2	c 4 64  660  0 14
	/dev/ttyS3	c 4 64  660  0 14
	/dev/ptmx	l - -     -  - pts/ptmx
	/dev/core	l - -     -  - /proc/kcore
	/dev/fd		l - -     -  - /proc/self/fd
	/dev/stdin	l - -     -  - /proc/self/fd/0
	/dev/stdout	l - -     -  - /proc/self/fd/1
	/dev/stderr	l - -     -  - /proc/self/fd/2
	EOF
}

cleanup() {
	local rc=$?

	trap - EXIT; cd /
	[ -z "$cmdfile" -o $no_clean -ne 0 ] ||
		rm -f -- "$cmdfile"
	exit $rc
}


# Entry point
export TMPDIR="${TMPDIR:-/tmp}"
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

trap cleanup EXIT
cmdfile="$(mktemp -t "$progname-XXXXXXXX.cmd")"
( [ $minimal -eq 0 ] ||
	minimal_device_table
  [ -z "$devtab" ] ||
	cat -- "$devtab"
) |parse_device_table >"$cmdfile"

# There is no fine way to determinate exit status
# inside this script, parse /dev/stderr instead.
#
debugfs -w -f "$cmdfile" -- "$image"

