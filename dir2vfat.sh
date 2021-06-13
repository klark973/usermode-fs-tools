#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020-2021, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### dir2vfat {VERSION}
### Pack directory contents into vfat image

# Defaults
progname="${0##*/}"
capacity=
reserved=
image=
srcdir=
append=0
quiet=0
passthrough=
pad_space=0


show_help() {
	cat <<-EOF
	Usage: $progname [<options>...] [--] [<srcdir>] <image> [<size>]

	mkfs.fat pass through options (not used in append mode):
	  -A                     Use Atari variation of the MS-DOS filesystem.
	  -b  <backup-sector>    Location of the backup boot sector for FAT32.
	  -D  <drive-number>     Specify the BIOS drive number.
	  -F  <FAT-size>         Select the FAT type used (12, 16 or 32 bit).
	  -f  <number-of-FATs>   Specify the number of file allocation tables.
	  -H  <hidden-sectors>   Select the number of hidden sectors in the volume.
	  -i  <volume-id>        Sets the volume ID of the newly created filesystem.
	  -M  <FAT-media-type>   Media type to be stored in the FAT boot sector.
	  -m  <message-file>     Sets the message the user receives on attempts
	                         to boot this filesystem without having properly
	                         installed an operating system.
	  -n  <volume-name>      Sets the volume name (label) of the filesystem.
	  -R  <reserved-sects>   Select the number of reserved sectors.
	  -r  <root-entries>     Select the number of entries available in the
	                         root directory.
	  -S  <log-sect-size>    Specify the number of bytes per logical sector.
	  -s  <sects-per-clust>  Specify the number of disk sectors per cluster.
	  --invariant            Use constants for normally randomly generated or
	                         time based data such as volume ID and creation time.

	See man 8 mkfs.fat for more details.

	Common options:
	  -a, --append           Add files to an existing VFAT image file,
	                         mkfs.fat options can't be used in append mode.
	  -p  <reserved-space>   Reserve specified free space, in MiB.
	  -P, --pad-space        Fill all free space by zero's.
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
	cut
	dd
	du
	getopt
	mcopy
	mtype
	mkfs.fat
	realpath
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

human2size() {
	local input="$1" rv=
	local slen="${#input}"
	slen="$(($slen - 1))"
	local data="${input:0:$slen}"
	local lchar="${input:$slen:1}"

	case "$lchar" in
	K) rv="$(($data / 1024))";;
	M) rv="$data";;
	G) rv="$(($data * 1024))";;
	T) rv="$(($data * 1024 * 1024))";;
	[0-9]) rv="$input";;
	esac

	[ -n "$rv" -a "$rv" -gt 0 ] 2>/dev/null ||
		fatal "Invalid size: '%s'." "$input"
	printf "%s" "$rv"
}

parse_args() {
	local s_opts="+Aab:D:F:f:H:i:M:m:n:Pp:R:r:S:s:qvh"
	local l_opts="append,invariant,pad-space,quiet,version,help"
	local msg="Invalid command-line usage, try '-h' for help."

	l_opts=$(getopt -n "$progname" -o "$s_opts" -l "$l_opts" -- "$@") ||
		fatal "$msg"
	eval set -- "$l_opts"
	while [ $# -gt 0 ]; do
		case "$1" in
		-A|--invariant)
			passthrough="$passthrough $1"
			;;
		-b|-D|-F|-f|-M|-R|-r|-S|-s)
			[ -n "${2-}" ] ||
				fatal "$msg"
			passthrough="$passthrough $1 $2"
			shift
			;;
		-H)	[ -n "${2-}" ] ||
				fatal "$msg"
			passthrough="$passthrough -h $2"
			shift
			;;
		-i|-m|-n)
			[ -n "${2-}" ] ||
				fatal "$msg"
			passthrough="$passthrough $1 \"$2\""
			shift
			;;
		-a|--append)
			append=1
			;;
		-P|--pad-space)
			pad_space=1
			;;
		-p)	[ -n "${2-}" ] ||
				fatal "$msg"
			reserved="$(human2size "$2")"
			shift
			;;
		-q|--quiet)
			quiet=1
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

	if [ $# -eq 2 -o $# -eq 3 ] && [ -d "${1-}" ]; then
		srcdir="$(realpath -- "$1")"
		shift
	fi
	[ $# -eq 1 -o $# -eq 2 ] ||
		fatal "$msg"
	[ -n "$1" ] ||
		fatal "VFAT image file name not specified."
	[ -n "$srcdir" ] ||
		srcdir="$(realpath .)"
	image="$1"; shift
	[ ! -f "$image" ] ||
		image="$(realpath -- "$image")"
	[ $append -eq 0 -o -s "$image" ] ||
		fatal "In append mode existing image file required."
	[ $append -eq 0 -o -z "$passthrough" ] ||
		fatal "In append mode mkfs.fat options can't be used."
	[ $append -eq 0 -o -z "$reserved" ] ||
		fatal "In append mode '-p' option can't be used."
	[ $quiet -ne 0 ] ||
		passthrough="$passthrough -v"
	if [ $# -eq 1 ]; then
		capacity="$(human2size "$1")"
		shift
	fi
}

create_image() {
	local opts="-p -Q -m -s -i"

	# Create filesystem
	if [ $append -eq 0 ]; then
		verbose "Initializing VFAT filesystem..."
		rm -f -- "$image"
		verbose "Executing: 'dd if=/dev/zero of=\"$image\" bs=32k count=$imgsize'"
		dd if=/dev/zero of="$image" bs=32k count=$imgsize >/dev/null 2>&1
		verbose "Executing: 'mkfs.fat $passthrough -- \"$image\"'"
		eval mkfs.fat $passthrough -- "$image"
		image="$(realpath -- "$image")"
	fi

	# Fill image
	[ $quiet -ne 0 ] ||
		opts="-v $opts"
	verbose "Executing: 'mcopy $opts \"$image\" * ::'"
	(set +f; cd "$srcdir/" && mcopy $opts "$image" * ::)
}

fill_free_space() {
	verbose "Executing: 'dd if=/dev/zero bs=4k |mcopy -Q -i \"$image\" - ::.pad'"
	dd if=/dev/zero bs=4k |mcopy -Q -i "$image" - ::.pad >/dev/null 2>&1 ||:
}


# Entry point
export TMPDIR="${TMPDIR:-/tmp}"
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

verbose "Option '-q' turns off verbose diagnostic."

verbose "progname='$progname'"
verbose "capacity=$capacity"
verbose "reserved=$reserved"
verbose "image='$image'"
verbose "srcdir='$srcdir'"
verbose "append=$append"
verbose "quiet=$quiet"
verbose "passthrough='$passthrough'"

# Calculate image size
if [ -n "$capacity" -a "$capacity" -gt 0 ] 2>/dev/null; then
	imgsize="$((32 * $capacity))"
	reserved=
else
	imgsize="$(du -lxsLB32k -- "$srcdir" |cut -f1)"
	imgsize="$(($imgsize / 10 + $imgsize + 10))"
	capacity=
fi
verbose "imgsize=($imgsize * 32KiB)"

create_image

# Correct image size
if [ $append -eq 0 -a -z "$capacity" ]; then
	verbose "Trying to optimize image size..."
	fill_free_space
	tmpfile="$(mktemp -t "$progname-XXXXXXXX.pad")"
	verbose "Executing: 'mtype -i \"$image\" ::.pad'"
	mtype -i "$image" ::.pad > "$tmpfile"
	padsize="$(du -lxsLB32k -- "$tmpfile" |cut -f1)"
	verbose "padsize=($padsize * 32KiB)"
	rm -f -- "$tmpfile"
	unset tmpfile

	if [ -n "$reserved" -a "$reserved" -gt 0 ] 2>/dev/null; then
		newimgsz="$((32 * $reserved + $imgsize + 1 - $padsize))"
	else
		newimgsz="$(($imgsize + 1 - $padsize))"
		reserved=
	fi
	verbose "newimgsz=($newimgsz * 32KiB)"
	unset padsize

	if [ "$imgsize" -gt "$newimgsz" ]; then
		imgsize="$newimgsz"; create_image
		if [ $pad_space -ne 0 -a -z "$reserved" ]; then
			fill_free_space
		fi
	fi
	unset newimgsz
fi

# Display result
imgsize="$(du -sxh --apparent-size -- "$image" |cut -f1)"
verbose "VFAT image file created: '$image' ($imgsize)."

