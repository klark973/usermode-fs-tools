#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020-2021, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### parts2img {VERSION}
### Unite separate partitions to the single disk image

# Defaults
progname="${0##*/}"
no_clean=0
gptlabel=0
partsdir=
swapsize=
tmpimage=
imgfile=
v="-v"


show_help() {
	cat <<-EOF
	Usage: $progname [<options>...] [--] [<partsdir>] [<image>]

	Options:
	  -g, --guid-gpt         Use GPT disk label instead MBR.
	  -n, --no-clean         Keep temporary files on exit.
	  -q, --quiet            Suppress additional diagnostic.
	  -s, --swap=<size>      Specify SWAP partition size, in MiB.
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
	mkswap
	realpath
	sfdisk
	truncate
}

verbose() {
	local fmt="$1"; shift

	[ -z "$v" ] || printf "$fmt\n" "$@" >&2
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
	local s_opts="+gnqs:vh"
	local l_opts="guid-gpt,no-clean,quiet,swap:,version,help"
	local msg="Invalid command-line usage, try '-h' for help."

	l_opts=$(getopt -n "$progname" -o "$s_opts" -l "$l_opts" -- "$@") ||
		fatal "$msg"
	eval set -- "$l_opts"
	while [ $# -gt 0 ]; do
		case "$1" in
		-g|--guid-gpt)
			gptlabel=1
			;;
		-n|--no-clean)
			no_clean=1
			;;
		-q|--quiet)
			v=
			;;
		-s|--swap)
			[ -n "${2-}" ] ||
				fatal "$msg"
			swapsize="$(human2size "$2")"
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

	if [ $# -gt 0 -a -d "${1-}" ]; then
		partsdir="$(realpath -- "$1")"
		shift
	else
		partsdir="$(realpath .)"
	fi
	if [ $# -eq 1 ]; then
		imgfile="$1"
		shift
	fi
	[ $# -eq 0 ] ||
		fatal "$msg"
	[ -s "$partsdir/SYS.img" ] ||
		fatal "ROOT partition image (SYS.img) not found."
	tmpimage="$partsdir/probe.img"
}

get_part_size() {
	du -sm --apparent-size -- "$1" |cut -f1
}

align_part() {
	local pname="$1"
	local psize="${2-}"

	[ -n "$psize" -a "$psize" -gt 0 ] 2>/dev/null ||
		psize="$(get_part_size "$pname")"
	truncate -s "${psize}M" -- "$pname"
}

uint2bytes() {
	local s="$(printf "%08x" $1)"

	eval "printf '\x${s:6:2}'"
	eval "printf '\x${s:4:2}'"
	eval "printf '\x${s:2:2}'"
	eval "printf '\x${s:0:2}'"
}


# Entry point
export LC_ALL="C"
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

n_parts=0
imgsize=1
haveboot=0
plist="MBR.img"
cd "$partsdir/"
umask 0022
:> LAYOUT

# EFI partition
if [ -s EFI.img ]; then
	align_part EFI.img
	plist="$plist EFI.img"
	n_parts="$((1 + $n_parts))"
	psize="$(get_part_size EFI.img)"
	verbose "EFI size: %s %s" "$psize" "MiB"
	imgsize="$(($imgsize + $psize))"
	echo ",${psize}M,U" >> LAYOUT
fi

# BIOS grub partition
if [ $gptlabel -ne 0 -a -s i386-pc-core.img ]; then
	mv -f $v i386-pc-core.img BGP.img
	align_part BGP.img
	plist="$plist BGP.img"
	n_parts="$((1 + $n_parts))"
	psize="$(get_part_size BGP.img)"
	verbose "BGP size: %s %s" "$psize" "MiB"
	imgsize="$(($imgsize + $psize))"
	echo ",${psize}M,21686148-6449-6E6F-744E-656564454649" >> LAYOUT
fi

# E2K /boot partition
if [ -s E2K.img ]; then
	[ $n_parts -eq 0 ] ||
		fatal "E2K /boot partition must be first."
	align_part E2K.img
	plist="$plist E2K.img"
	n_parts="$((1 + $n_parts))"
	psize="$(get_part_size E2K.img)"
	verbose "E2K size: %s %s" "$psize" "MiB"
	imgsize="$(($imgsize + $psize))"
	echo ",${psize}M,L,*" >> LAYOUT
	haveboot=1
fi

# Power PReP partition
if [ -s powerpc-ieee1275-powerpc.elf ]; then
	[ $n_parts -eq 0 ] ||
		fatal "Power PReP partition must be first."
	mv -f $v powerpc-ieee1275-powerpc.elf PReP.img
	align_part PReP.img
	plist="$plist PReP.img"
	n_parts="$((1 + $n_parts))"
	psize="$(get_part_size PReP.img)"
	[ $psize -gt 0 -a $psize -lt 8 ] ||
		fatal "Power PReP partition must be between 1-7 MiB."
	verbose "PReP size: %s %s" "$psize" "MiB"
	imgsize="$(($imgsize + $psize))"
	if [ $gptlabel -eq 0 ]; then
		echo ",${psize}M,41,*" >> LAYOUT
	else
		echo ",${psize}M,7,*" >> LAYOUT
	fi
	haveboot=1
fi

# Linux SWAP partition
if [ -s SWP.img ]; then
	swapsize="$(get_part_size SWP.img)"
	align_part SWP.img $swapsize
elif [ -n "$swapsize" -a "$swapsize" -gt 0 ] 2>/dev/null; then
	align_part SWP.img $swapsize
	chmod $v 0600 SWP.img
	mkswap -f SWP.img
	chmod $v 0644 SWP.img
else
	swapsize=
fi
if [ -n "$swapsize" ]; then
	plist="$plist SWP.img"
	n_parts="$((1 + $n_parts))"
	verbose "SWAP size: %s %s" "$swapsize" "MiB"
	imgsize="$(($imgsize + $swapsize))"
	echo ",${swapsize}M,S" >> LAYOUT
fi

# ROOT partition
align_part SYS.img
plist="$plist SYS.img"
n_parts="$((1 + $n_parts))"
psize="$(get_part_size SYS.img)"
imgsize="$(($imgsize + $psize))"
verbose "ROOT size: %s %s" "$psize" "MiB"
if [ ! -s HOME.img ]; then
	if [ $haveboot -eq 0 ]; then
		echo ",,L,*" >> LAYOUT
		haveboot=$n_parts
	else
		echo ",,L" >> LAYOUT
	fi
else
	[ $gptlabel -ne 0 -o $haveboot -ne 0 -o $n_parts -lt 4 ] ||
		fatal "Only GUID/GPT supports over 4 primary partitions."
	if [ $haveboot -eq 0 ]; then
		echo ",${psize}M,L,*" >> LAYOUT
		haveboot=$n_parts
	else
		echo ",${psize}M,L" >> LAYOUT
	fi

	# HOME partition
	align_part HOME.img
	plist="$plist HOME.img"
	n_parts="$((1 + $n_parts))"
	psize="$(get_part_size HOME.img)"
	verbose "HOME size: %s %s" "$psize" "MiB"
	imgsize="$(($imgsize + $psize))"
	if [ $gptlabel -ne 0 ]; then
		echo ",,H" >> LAYOUT
	else
		echo ",,L" >> LAYOUT
	fi
fi

# Debug image layout
[ $gptlabel -eq 0 ] ||
	imgsize="$((1 + $imgsize))"
verbose "Disk image layout:"
[ -z "$v" ] || cat LAYOUT >&2
verbose "Total image size: %s %s" "$imgsize" "MiB"

# Unite all partitions
if [ $gptlabel -eq 0 ]; then
	verbose "Writing MBR and boot loader code..."
	align_part MBR.img $imgsize
	sfdisk -X dos -W always -q -- MBR.img <LAYOUT
	align_part MBR.img 1
	( # Grub stage 0 Boot Loader
	  [ ! -s i386-pc-boot.img ] ||
		dd if=i386-pc-boot.img bs=440 count=1 conv=notrunc of=MBR.img
	  # Grub stage 1.5 Boot Loader
	  [ ! -s i386-pc-core.img ] ||
		dd if=i386-pc-core.img bs=512 seek=1 conv=notrunc of=MBR.img
	) >/dev/null 2>&1
	verbose "Writing disk image..."
	cat $plist > "$tmpimage"
else
	verbose "Creating GUID/GPT..."
	align_part probe.img $imgsize
	sfdisk -X gpt -W always -q -- probe.img <LAYOUT
	[ $haveboot -eq 0 ] ||
		sfdisk -q -f --part-attrs probe.img $haveboot LegacyBIOSBootable
	verbose "Building disk image..."
	imgsize=0; kernsec=

	for pname in $plist; do
		if [ "$pname" = "MBR.img" ]; then
			# Grub stage 0 Boot Loader
			[ ! -s i386-pc-boot.img ] ||
				dd if=i386-pc-boot.img bs=440 count=1 seek=0 \
					conv=notrunc of=probe.img >/dev/null 2>&1
			imgsize=1
		else
			if [ "$pname" = "BGP.img" ]; then
				kernsec="$((2048 * $imgsize))"
				# The offset of NEXT_SECTOR at 0x1F4, 4 bytes
				uint2bytes $((1 + $kernsec)) |dd bs=1 seek=500 \
					count=4 conv=notrunc of=BGP.img >/dev/null 2>&1
			fi
			psize="$(get_part_size "$pname")"
			verbose "Writing %s (%s %s)..." "$pname" "$psize" "MiB"
			dd if="$pname" bs=1M count=$psize seek=$imgsize \
				conv=notrunc of=probe.img >/dev/null 2>&1
			imgsize="$(($imgsize + $psize))"
		fi
	done

	if [ -n "$kernsec" -a -s i386-pc-boot.img ]; then
		# The offset of KERNEL_SECTOR at 0x05C, 4 bytes
		uint2bytes $kernsec |dd bs=1 seek=92 count=4 \
			conv=notrunc of=probe.img >/dev/null 2>&1
	fi
fi

# Finalize
[ -z "$imgfile" ] ||
	mv -f $v -- "$tmpimage" "$imgfile"
[ $no_clean -ne 0 ] ||
	rm -f $v -- $plist LAYOUT
cd "$OLDPWD"

