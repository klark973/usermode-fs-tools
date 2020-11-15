#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### dir2extfs {VERSION}
### Pack directory contents to an extfs image

# Defaults
progname="${0##*/}"
prefix="fakeroot"
no_clean=0
capacity=
reserved=
image=
srcdir=
devtab=
mindev=0
append=0
fstype=
quiet=0
passthrough=
ext4new=0
m_opt=
inodes=


show_help() {
	cat <<-EOF
	Usage: $progname [<options>...] [--] [<srcdir>] <image> [<size>]

	mke2fs pass through options (not used in append mode):
	  -C  <number>           Specify the size of cluster, in bytes.
	  -f  <number>           Specify the size of fragment, in bytes.
	  -G  <number>           Specify the number of block groups.
	  -g  <number>           Specify the number of blocks in a block group.
	  -I  <number>           Specify the size of each inode, in bytes.
	  -i  <number>           Specify the bytes/inode ratio.
	  -L  <label>            Specify the filesystem volume label.
	  -m  <number>           Specify the percentage of the filesystem
	                         blocks, reserved for the super-user.
	                         The default percentage is 5%.
	  -N  <number>           Overrides the default calculation
	                         of the number of inodes that should
	                         be reserved for the filesystem.
	  -o  <creator-os>       Overrides the default value of the
	                         "creator operating system" field.
	  -T  <usage-type...>    Specify one or more usage types, using a
	                         comma separated list and /etc/mke2fs.conf.
	  -U  <UUID>             Specify the filesystem volume UUID.

	See man 8 mke2fs for more details.

	Common options:
	  -a, --append           Add files to an existing extfs image file,
	                         mke2fs options can't be used in append mode.
	  -d  <filename>         Specify devices table for populate /dev nodes.
	  -M, --mindev           Populate minimalistic /dev nodes.
	  -n, --no-clean         Keep temporary files on exit.
	  -q, --quiet            Suppress additional diagnostic.
	  -r  <number>           Reserve specified free space, in MiB.
	  -t  <fstype>           Specify the filesystem type (ext2, ext3,
	                         ext4 or ext4new - last is alias for ext4
	                         with some additional features).
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
	cut
	debugfs
	dev2extfs
	du
	dumpe2fs
	fakeroot
	getopt
	head
	id
	readlink
	realpath
	resize2fs
	mke2fs
	mktemp
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
	local s_opts="+aC:d:f:G:g:I:i:L:MnN:o:qr:T:t:U:vh"
	local l_opts="append,mindev,no-clean,quiet,version,help"
	local msg="Invalid command-line usage, try '-h' for help."

	l_opts=$(getopt -n "$progname" -o "$s_opts" -l "$l_opts" -- "$@") ||
		fatal "$msg"
	eval set -- "$l_opts"
	while [ $# -gt 0 ]; do
		case "$1" in
		-C|-f|-G|-g|-I|-i)
			[ -n "${2-}" ] ||
				fatal "$msg"
			passthrough="$passthrough $1 $2"
			shift
			;;
		-o|-L|-T|-U)
			[ -n "${2-}" ] ||
				fatal "$msg"
			passthrough="$passthrough $1 \"$2\""
			shift
			;;
		-a|--append)
			append=1
			;;
		-d)	[ -n "${2-}" ] ||
				fatal "$msg"
			[ -s "$2" ] ||
				fatal "File with device table not found: '%s'." "$2"
			devtab="$(realpath -- "$2")"
			shift
			;;
		-M|--mindev)
			mindev=1
			;;
		-m)	[ -n "${2-}" ] ||
				fatal "$msg"
			passthrough="$passthrough -m $2"
			m_opt="$2"
			shift
			;;
		-N)	[ -n "${2-}" ] ||
				fatal "$msg"
			passthrough="$passthrough -N $2"
			inodes="$2"
			shift
			;;
		-n|--no-clean)
			no_clean=1
			;;
		-q|--quiet)
			quiet=1
			;;
		-r)	[ -n "${2-}" ] ||
				fatal "$msg"
			reserved="$(human2size "$2")"
			shift
			;;
		-t)	case "${2-}" in
			ext2|ext3|ext4)
				fstype="$2"
				;;
			ext4new)
				fstype="ext4"
				ext4new=1
				;;
			*)	fatal "Only ext2/3/4 filesystem type expected."
				;;
			esac
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

	if [ $# -eq 2 -o $# -eq 3 ] && [ -d "${1-}" ]; then
		srcdir="$(realpath -- "$1")"
		shift
	fi
	[ $# -eq 1 -o $# -eq 2 ] ||
		fatal "$msg"
	[ -n "$1" ] ||
		fatal "ExtFS image file name not specified."
	[ -n "$srcdir" ] ||
		srcdir="$(realpath .)"
	[ -n "$fstype" ] ||
		fstype="ext2"
	image="$1"; shift
	[ ! -f "$image" ] ||
		image="$(realpath -- "$image")"
	[ $append -eq 0 -o -s "$image" ] ||
		fatal "In append mode existing image file required."
	[ $append -eq 0 -o -z "$passthrough" ] ||
		fatal "In append mode mke2fs options can't be used."
	if [ $# -eq 1 ]; then
		capacity="$(human2size "$1")"
		shift
	fi
}

# cp -r
rpush() {
	local entry= target=

	for entry in *; do
		[ "$entry" != '*' ] ||
			continue
		if [ -L "$entry" ]; then
			if [ $quiet -ne 0 ]; then
				target="$(readlink -ns -- "$entry")"
			else
				target="$(readlink -nv -- "$entry")"
			fi
			echo "symlink \"$entry\" \"$target\""
		elif [ -f "$entry" ]; then
			echo "write \"$entry\" \"$entry\""
		elif [ -d "$entry" ]; then
			echo "mkdir \"$entry\""
			echo "lcd \"$entry\""
			echo "cd \"$entry\""
			cd "$entry/"
			rpush
			cd ..
			echo "cd .."
			echo "lcd .."
		fi
	done
}

# fallback
append_files() {
	local tmpfile= redirect= args=

	[ $quiet -eq 0 ] ||
		redirect=">/dev/null 2>&1"

	if [ $use_fallback -ne 0 ]; then
		tmpfile="$(mktemp -t "$progname-XXXXXXXX.cmd")"
		verbose "tmpfile='$tmpfile'"
		[ $no_clean -ne 0 ] ||
			trap "rm -f -- \"$tmpfile\"" EXIT
		verbose "Creating debugfs script..."
		( echo "lcd \"$srcdir\""
		  cd "$srcdir/"
		  set +f
		  rpush
		  echo "quit"
		) > "$tmpfile"

		verbose "Executing debugfs script..."
		eval $prefix debugfs -w -f "$tmpfile" -- "$image" $redirect

		if [ $no_clean -eq 0 ]; then
			rm -f -- "$tmpfile"
			trap - EXIT
		fi
	fi

	if [ $mindev -ne 0 -o -n "$devtab" ]; then
		verbose "Populating /dev nodes..."
		[ $mindev -eq 0 ] ||
			args="-m"
		[ $no_clean -eq 0 ] ||
			args="$args -n"
		if [ -n "$devtab" ]; then
			eval dev2extfs $args -- "$devtab" "$image" $redirect
		else
			eval dev2extfs $args -- "$image" $redirect
		fi
	fi
}

reserve_space() {
	local addsize="$(($imgsize / 20))"

	if [ $ext4new -ne 0 ]; then
		[ $addsize -ge 10 ] ||
			addsize=10
	elif [ "$fstype" = "ext2" ]; then
		[ $addsize -ge 5 ] ||
			addsize=5
	else
		[ $addsize -ge 8 ] ||
			addsize=8
	fi

	imgsize="$(($imgsize + $addsize))"
}


# Entry point
export TMPDIR="${TMPDIR:-/tmp}"
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

if [ "$(id -u)" = "0" ]; then
	if chroot / /bin/true >/dev/null 2>&1; then
		fatal "This program can run without root privileges!"
	fi

	# Run inside hasher, it's nice: fakeroot already outside
	prefix=
fi

verbose "Option '-q' turn off verbose diagnostic."

verbose "progname='$progname'"
verbose "prefix='$prefix'"
verbose "no_clean=$no_clean"
verbose "capacity=$capacity"
verbose "reserved=$reserved"
verbose "image='$image'"
verbose "srcdir='$srcdir'"
verbose "devtab='$devtab'"
verbose "mindev=$mindev"
verbose "append=$append"
verbose "fstype='$fstype'"
verbose "quiet=$quiet"
verbose "passthrough='$passthrough'"
verbose "ext4new=$ext4new"
verbose "m_opt=$m_opt"
verbose "inodes=$inodes"

# In append mode or if e2fsprogs < 1.43, using fallback
mkfs_version="$(mke2fs -V 2>&1 |head -n1 |awk '{print $2;}')"
verbose "mkfs_version='$mkfs_version'"
major="$(echo "$mkfs_version" |cut -f1 -d.)"
minor="$(echo "$mkfs_version" |cut -f2 -d.)"
if [ "$major" -gt 1 ] 2>/dev/null; then
	new_mke2fs=1
elif [ "$major" = 1 -a "$minor" -gt 42 ] 2>/dev/null; then
	new_mke2fs=1
else
	new_mke2fs=0
fi
unset major minor
verbose "new_mke2fs=$new_mke2fs"
[ $ext4new -eq 0 -o $new_mke2fs -ne 0 ] ||
	fatal "ext4new requre e2fsprogs >= 1.43, try ext4 instead."
if [ $append -ne 0 -o $new_mke2fs -eq 0 ]; then
	use_fallback=1
else
	use_fallback=0
fi
verbose "use_fallback=$use_fallback"

# Build mke2fs options
mkfs_opts="-t $fstype -F -r1"
[ $quiet -eq 0 ] &&
	mkfs_opts="$mkfs_opts -v" ||
	mkfs_opts="$mkfs_opts -q"
[ "$fstype" = "ext2" ] ||
	mkfs_opts="$mkfs_opts -j"
[ -n "$m_opt" ] ||
	mkfs_opts="$mkfs_opts -m0"
if [ $use_fallback -eq 0 ]; then
	[ -n "$inodes" ] ||
		mkfs_opts="$mkfs_opts -N0"
	mkfs_opts="$mkfs_opts -d \"$srcdir\""
fi
if [ $new_mke2fs -eq 0 ]; then
	mkfs_opts="$mkfs_opts -E root_owner"
else
	[ $ext4new -ne 0 ] ||
		mkfs_opts="$mkfs_opts -O ^64bit"
	mkfs_opts="$mkfs_opts -E no_copy_xattrs,root_owner"
fi
verbose "mkfs_opts='$mkfs_opts'"
unset new_mke2fs

# Calculate minimal image size
if [ -n "$capacity" -a "$capacity" -gt 0 ] 2>/dev/null; then
	imgsize="$capacity"
else
	imgsize="$(du -sxm -- "$srcdir" |cut -f1)"
	reserve_space
	capacity=
fi
verbose "imgsize=$imgsize"

# Create filesystem
if [ $append -eq 0 ]; then
	rm -f -- "$image"
	verbose "Initializing $fstype filesystem..."
	eval $prefix mke2fs $mkfs_opts $passthrough -- "$image" "${imgsize}M"
fi

# Fill image
append_files

# Resize ExtFS image file
if [ -z "$capacity" -o -n "$reserved" ]; then
	verbose "Shrinking $fstype image..."
	n_blocks="$(dumpe2fs -h -- "$image" 2>&1 |
			grep 'Block count:' |
			awk '{print $3;}')"
	verbose "n_blocks=$n_blocks"

	while $prefix resize2fs -f -M -- "$image"; do
		r_blocks="$(dumpe2fs -h -- "$image" 2>&1 |
				grep 'Block count:' |
				awk '{print $3;}')"
		verbose "n_blocks=$r_blocks"
		[ "$r_blocks" != "$n_blocks" ] ||
			break
		n_blocks="$r_blocks"
	done

	imgsize="$(du -sxm --apparent-size -- "$image" |cut -f1)"

	if [ -n "$reserved" ]; then
		verbose "Resizing $fstype image..."
		imgsize="$(($imgsize + $reserved))"
		reserve_space
		if [ $quiet -eq 0 ]; then
			$prefix resize2fs -f -p -- "$image" "${imgsize}M"
		else
			$prefix resize2fs -f -- "$image" "${imgsize}M"
		fi
		imgsize="$(du -sxm --apparent-size -- "$image" |cut -f1)"
	fi
fi

verbose "$fstype image file created: '$image' (${imgsize}M)."

