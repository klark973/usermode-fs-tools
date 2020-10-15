#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### img2parts {VERSION}
### Split disk image to the separate partition images

# Defaults
progname="${0##*/}"
only_parts=
outdir=
image=

# Action code: 0=check, 1=list, 2=info, 3=extract (default)
action=3


show_help() {
	cat <<-EOF
	Usage: $progname [<options>] [--] <image> [<part-no>...]

	Options:
	  -c, --check            Check only for valid disk image.
	  -i, --info             Show partition(s) information.
	  -l, --list             List all partitions and exit.
	  -o, --output=<path>    Specify directory for save files.
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
	dd
	fdisk
	grep
	realpath
	sfdisk
	wc
}

fatal() {
	local fmt="$1"; shift

	printf "%s fatal: $fmt\n" "$progname" "$@" >&2
	exit 1
}

parse_args() {
	local s_opts="+cilo:vh"
	local l_opts="check,info,list,output:,version,help"
	local msg="Invalid command-line usage, try '-h' for help."

	l_opts=$(getopt -n "$progname" -o "$s_opts" -l "$l_opts" -- "$@") ||
		fatal "$msg"
	eval set -- "$l_opts"
	while [ $# -gt 0 ]; do
		case "$1" in
		-c|--check)
			action=0
			;;
		-i|--info)
			action=2
			;;
		-l|--list)
			action=1
			;;
		-o|--output)
			[ -n "${2-}" -a -d "${2-}" ] ||
				fatal "$msg"
			outdir="$(realpath -- "$2")"
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

	[ $# -ne 0 ] ||
		fatal "$msg"
	[ -f "$1" ] ||
		fatal "$msg"
	[ -n "$outdir" ] ||
		outdir="$(realpath .)"
	image="$(realpath -- "$1")"
	shift; only_parts="$@"
}

partition_type() {
	case "$1" in
	ef|"EFI System")
		printf "EFI"
		;;
	1|4|6|b|c|e|f|11|14|16|1b|1c|1e)
		printf "VFAT"
		;;
	"FAT12"|"FAT16 <32M"|"FAT16")
		printf "VFAT"
		;;
	"W95 FAT32"|"W95 FAT32 (LBA)"|"W95 FAT16 (LBA)"|"W95 Ext'd (LBA)")
		printf "VFAT"
		;;
	"Hidden FAT12"|"Hidden FAT16 <32M"|"Hidden FAT16"|"Hidden W95 FAT"*)
		printf "VFAT"
		;;
	82|"Linux swap"*)
		printf "SWAP"
		;;
	83|"Linux filesystem"|"Linux home")
		printf "EXTFS"
		;;
	*)	printf "SKIP"
		;;
	esac
}

is_in_list() {
	local i= number="$1"

	[ -n "$only_parts" ] ||
		return 0
	for i in $only_parts; do
		[ "$i" != "$number" ] ||
			return 0
	done

	return 1
}

check_image() {
	local type=
	local header="^Device\s+Boot\s+Start\s+End\s+Sectors"

	[ -s "$image" ] ||
		return 1
	type="$(sfdisk -l -- "$image" |grep -s 'Disklabel type:' |cut -f3 -d ' ')"
	if [ "$type" = "gpt" ]; then
		header="^Device\s+Start\s+End\s+Sectors"
		gptlabel=1
	elif [ "$type" != "dos" ]; then
		return 2
	fi
	sfdisk -l -- "$image" |grep -qsE "$header" ||
		return 3
	n_parts="$(sfdisk -l -- "$image" |sed -E "1,/$header/d" |wc -l)"
	[ "$n_parts" -gt 0 ] 2>/dev/null ||
		return 4

	return 0
}

list_all_parts() {
	local ptsize= pttype=
	local p=0 fmt="SIZE,ID"

	[ $gptlabel -eq 0 ] ||
		fmt="SIZE,TYPE"
	sfdisk -l -o "$fmt" -- "$image" |
		sed -e '1,/^$/d' |
		sed -e 1d |
	while read ptsize pttype; do
		p="$((1 + $p))"
		pttype="$(partition_type "$pttype")"
		printf "part%s\t%s\t%s\n" "$p" "$ptsize" "$pttype"
	done
}

parts_details() {
	local pttype= ext=
	local p=0 fmt="ID"

	[ $gptlabel -eq 0 ] ||
		fmt="TYPE"
	sfdisk -l -- "$image" |sed '/^$/,$d'
	printf "\n"
	sfdisk -l -o "$fmt" -- "$image" |
		sed -e '1,/^$/d' |
		sed -e 1d |
	while read pttype; do
		p="$((1 + $p))"
		is_in_list "$p" ||
			continue
		pttype="$(partition_type "$pttype")"
		if [ "$pttype" = "VFAT" -o "$pttype" = "EFI" ]; then
			ext="fat"
		elif [ "$pttype" = "EXTFS" ]; then
			ext="ext"
		else
			continue
		fi
		printf "Name: part%s-%s.img\n" "$p" "$ext"
		(echo "i"; echo "$p"; echo "q") |fdisk -- "$image" |
			sed -E 's/^\s+//g' |sed '1,/^Device:/d' |sed '/^$/,$d'
		printf "\n"
	done
}

extract_parts() {
	local ptstart= ptsize= pttype= ext=
	local p=0 fmt="START,SECTORS,ID"

	[ $gptlabel -eq 0 ] ||
		fmt="START,SECTORS,TYPE"
	sfdisk -l -o "$fmt" -- "$image" |
		sed -e '1,/^$/d' |
		sed -e 1d |
	while read ptstart ptsize pttype; do
		p="$((1 + $p))"
		is_in_list "$p" ||
			continue
		pttype="$(partition_type "$pttype")"
		if [ "$pttype" = "VFAT" -o "$pttype" = "EFI" ]; then
			ext="fat"
		elif [ "$pttype" = "EXTFS" ]; then
			ext="ext"
		else
			continue
		fi
		[ "$outdir/part$p-$ext.img" != "$image" ] ||
			fatal "Partition has same file name as source disk image."
		rm -f -- "part$p-$ext.img"
		printf "Extracting '%s'..." "part$p-$ext.img"
		dd if="$image" of="part$p-$ext.img" bs=512 \
			skip=$ptstart count=$ptsize status=none
		printf "\n"
	done
}


# Entry point
export LC_ALL="C"
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

n_parts=0
gptlabel=0
check_image ||
	fatal "Invalid disk image: '%s'." "$image"
umask 0022
cd "$outdir/"
case "$action" in
1) list_all_parts;;
2) parts_details;;
3) extract_parts;;
esac

