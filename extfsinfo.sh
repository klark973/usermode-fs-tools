#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### extfsinfo {VERSION}
### Output information about extfs image

# Defaults
progname="${0##*/}"
option=
image=
blksize=
cache=


show_help() {
	cat <<-EOF
	Usage: $progname [<option>] [--] {<image>|<device>}

	Options:
	  -a, --allocated        Show allocated space only, in MiB.
	  -b, --blksize          Show block size only, in bytes.
	  -c, --check            Check only for extfs filesystem.
	  -f, --free             Show free space only, in MiB.
	  -i, --info             Show all information about image.
	  -L, --label            Show filesystem volume label only.
	  -r, --reserved         Show reserved space only, in MiB.
	  -s, --size             Show image size only, in MiB.
	  -t, --type             Show filesystem type only.
	  -U, --uuid             Show filesystem UUID only.
	  -u, --usage            Show percent of usage only.
	  -v, --version          Show this program version only.
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
	cut
	du
	dumpe2fs
	grep
	id
	lsblk
	realpath
	sed
}

fatal() {
	local fmt="$1"; shift

	printf "%s fatal: $fmt\n" "$progname" "$@" >&2
	exit 1
}

parse_args() {
	local msg="Invalid command-line usage, try '-h' for help."

	[ $# -ne 0 ] ||
		fatal "$msg"
	case "$1" in
	-v|--version)
		show_version;;
	-h|--help)
		show_help;;
	--)	shift;;
	-*)	option="$1"; shift
		[ "${1-}" != "--" ] || shift;;
	esac
	[ $# -eq 1 ] ||
		fatal "$msg"
	[ -e "$1" ] ||
		fatal "ExtFS image not found: '%s'." "$1"
	[ -n "$option" ] ||
		option="--info"
	image="$(realpath -- "$1")"
}

check_extfs_image() {
	[ -b "$image" -o -s "$image" ] ||
		fatal "ExtFS image must be block special device or regular file."
	[ ! -b "$image" -o "$(id -u)" = "0" ] ||
		return
	cache="$(dumpe2fs -h -- "$image" 2>&1 |sed 1d)"
	if echo "$cache" |grep -qs 'Bad magic number in super-block'; then
		fatal "Invalid ExtFS image: bad magic number in super-block."
	elif ! echo "$cache" |grep -qsE '^Filesystem state:\s+clean$'; then
		fatal "ExtFS image has no clean state."
	fi
}

extract_data() {
	field="$1"

	echo "$cache" |sed -E -e "/^$field:/!d" -e "s/^$field:\s+//"
}

require_cache() {
	[ -n "$cache" ] ||
		fatal "Permission denied while trying to open %s" "$image"
}

# Result of this function is very similar to:
# blkid -c /dev/null -o value -s TYPE -- "$image"
# but this code make diff's between ext4 and ext4new
#
get_fstype() {
	if [ -z "$cache" ]; then
		lsblk -dbno FSTYPE -- "$image"
		return
	fi

	local features="$(extract_data "Filesystem features")"

	[ -n "$features" ] ||
		fatal "ExtFS image has no features set."
	if   echo "$features" |grep -qws 64bit ||
	     echo "$features" |grep -qws metadata_csum
	then
		echo "ext4new"
	elif echo "$features" |grep -qws extent ||
	     echo "$features" |grep -qws huge_file ||
	     echo "$features" |grep -qws flex_bg ||
	     echo "$features" |grep -qws uninit_bg ||
	     echo "$features" |grep -qws dir_nlink ||
	     echo "$features" |grep -qws extra_isize
	then
		echo "ext4"
	elif echo "$features" |grep -qws has_journal; then
		echo "ext3"
	else
		echo "ext2"
	fi
}

# Result of this function absolute equal to:
# blkid -c /dev/null -o value -s LABEL -- "$image"
#
get_label() {
	if [ -z "$cache" ]; then
		lsblk -dbno LABEL -- "$image"
		return
	fi

	local label="$(extract_data "Filesystem volume name")"

	[ "$label" = "<none>" ] || echo "$label"
}

# Result of this function absolute equal to:
# blkid -c /dev/null -o value -s UUID -- "$image"
#
get_uuid() {
	if [ -z "$cache" ]; then
		lsblk -dbno UUID -- "$image"
	else
		extract_data "Filesystem UUID"
	fi
}

get_image_size() {
	if [ -s "$image" ]; then
		du -sm --apparent-size -- "$image" |cut -f1
		return
	fi

	# This way also not require root privileges
	local bytes="$(lsblk -dbno SIZE -- "$image")"
	local MiB="$((1024 * 1024))"
	local frac="$(($bytes % $MiB))"

	if [ "$frac" = "0" ]; then
		echo "$(($bytes / $MiB))"
	else
		echo "$(($bytes / $MiB + 1))"
	fi
}

get_block_size() {
	require_cache
	[ -n "$blksize" ] ||
		blksize="$(extract_data "Block size")"
	echo "$blksize"
}

get_free_space() {
	require_cache

	local bs="$(get_block_size)"
	local freeb="$(extract_data "Free blocks")"

	echo "$(($freeb * $bs / 1024 / 1024))"
}

get_reserved_space() {
	require_cache

	local bs="$(get_block_size)"
	local rblks="$(extract_data "Reserved block count")"

	echo "$(($rblks * $bs / 1024 / 1024))"
}

get_usage() {
	require_cache

	local total="$(extract_data "Block count")"
	local freeb="$(extract_data "Free blocks")"
	local usedb="$(($total - $freeb))"

	echo "$(($usedb * 100 / $total))"
}

get_allocated_space() {
	require_cache

	local bs="$(get_block_size)"
	local frees="$(get_free_space)"
	local total="$(extract_data "Block count")"

	total="$(($total * $bs / 1024 / 1024))"
	echo "$(($total - $frees))"
}

show_all_info() {
	printf "fstype:\t%s\n"		"$(get_fstype)"
	printf "label:\t%s\n"		"$(get_label)"
	printf "uuid:\t%s\n"		"$(get_uuid)"
	printf "imgsz:\t%s MiB\n"	"$(get_image_size)"
	[ -n "$cache" ] || return
	printf "blksz:\t%s bytes\n"	"$(get_block_size)"
	printf "alloc:\t%s MiB\n"	"$(get_allocated_space)"
	printf "free:\t%s MiB\n"	"$(get_free_space)"
	printf "rsrvd:\t%s MiB\n"	"$(get_reserved_space)"
	printf "usage:\t%s %%\n"	"$(get_usage)"
}


# Entry point
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

check_extfs_image

case "$option" in
-a|--allocated)	get_allocated_space;;
-b|--blksize)	get_block_size;;
-c|--check)	;; # already checked
-f|--free)	get_free_space;;
-i|--info)	show_all_info;;
-L|--label)	get_label;;
-r|--reserved)	get_reserved_space;;
-s|--size)	get_image_size;;
-t|--type)	get_fstype;;
-U|--uuid)	get_uuid;;
-u|--usage)	get_usage;;
*)		fatal "Unsupported option: '%s', try -h for help." "$option";;
esac

