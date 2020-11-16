#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### iso2stick {VERSION}
### Repack ALT ISO-9660 to the USB-stick disk image

# Defaults
progname="${0##*/}"
initlang="ru_RU"
rootuuid=
dualboot=0
biosboot=0
uefiboot=0
secureboot=0
gptlabel=0
timeout=60
includes=
excludes=
swapsize=
capacity=
reserved=
no_clean=0
pad_space=0
repack=
media=
image=
target=
workdir=
datadir=
quiet=0

# Repack modes
MODES="	  R rescue
	  D deploy
	  I install
	  L live
	 IR install+rescue
	 IL install+live
	ILR install+live+rescue
"

# Default languages
langlist='"ru_RU=Russian" "en_US=English" "pt_BR=Portuguese" "kk_KZ=Kazakh" "uk_UA=Ukrainian"'


show_help() {
	cat <<-EOF
	Usage: $progname [<options>...] [--] <iso9660> <image> [<size>]

	Options:
	  -b, --bios-only        Make BIOS-only boottable system on x86.
	  -D, --datadir=<PATH>   Add specified files to the boot disk.
	  -d, --dual-boot        Add both 32-bit and 64-bit UEFI firmware
	                         boot loaders for 64-bit target system,
	                         such as x86_64 or aarch64.
	  -e, --excludes=<FILE>  Set list for exclude files from ISO-9660.
	  -f, --files=<FILE>     Set list for include files from ISO-9660.
	  -g, --guid-gpt         Use GUID/GPT disk label instead BIOS/MBR.
	  -m, --mode=<MODE>      One of the followed repack modes: rescue,
	                         deploy, install, live, install+rescue,
	                         install+live or install+live+rescue.
	  -L, --lang=<LIST>      List of the languages, for example:
	                         '"ru_RU=Russian" "en_US=English"'.
	  -l, --initlang=<CODE>  Initial/default language code
	                         ('$initlang' used by default).
	  -n, --no-clean         Keep temporary files on exit.
	  -P, --pad-space        Fill free space on EFI-part by zero's.
	  -q, --quiet            Suppress additional diagnostic.
	  -r, --reserved=<SIZE>  Reserved space on the boot disk, in MiB.
	  -S, --swap=<SIZE>      Specify SWAP partition size, in MiB.
	  -s, --secure-boot      Use ALT shim's for UEFI Secure Boot.
	  -T, --timeout=<SECS>   Specify boot menu timeout, in seconds.
	  -t, --target=<ARCH>    Use specified target architecture: i586,
	                         x86_64, aarch64, armh, ppc64le or e2k/v4.
	  -U, --uuid=<UUID>      Specify UUID of the ROOT filesystem.
	  -u, --uefi-only        Make UEFI-only boottable system on x86.
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
	7z
	awk
	cat
	chmod
	cp
	cut
	cpio
	du
	getopt
	head
	ln
	ls
	md5sum
	mkdir
	mktemp
	realpath
	rm
	rpm2cpio
	rsync
	run-parts
	sed
	sha256sum
	tee
	uname
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

spawn() {
	verbose "Executing: \"$cmd\"..."
	eval $cmd
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
	local s_opts="+bD:de:f:gm:L:l:nPqr:S:sT:t:U:uvh"
	local l_opts="bios-only,datadir:,dual-boot,excludes:,files:,guid-gpt"
	      l_opts="$l_opts,initlang:,mode:,lang:,no-clean,pad-space,quiet"
	      l_opts="$l_opts,reserved:,swap:,secure-boot,timeout:,target:"
	      l_opts="$l_opts,uuid:,uefi-only,version,help"
	local msg="Invalid command-line usage, try '-h' for help."

	l_opts=$(getopt -n "$progname" -o "$s_opts" -l "$l_opts" -- "$@") ||
		fatal "$msg"
	eval set -- "$l_opts"
	while [ $# -gt 0 ]; do
		case "$1" in
		-b|--bios-only)
			biosboot=1
			uefiboot=0
			dualboot=0
			secureboot=0
			;;
		-D|--datadir)
			[ -n "${2-}" -a -d "${2-}" ] ||
				fatal "$msg"
			datadir="$(realpath -- "$2")"
			shift
			;;
		-d|--dual-boot)
			dualboot=1
			;;
		-e|--excludes)
			[ -n "${2-}" -a -f "${2-}" -a -z "$includes" ] ||
				fatal "$msg"
			excludes="$(realpath -- "$2")"
			shift
			;;
		-f|--files)
			[ -n "${2-}" -a -f "${2-}" -a -z "$excludes" ] ||
				fatal "$msg"
			includes="$(realpath -- "$2")"
			shift
			;;
		-g|--guid-gpt)
			gptlabel=1
			;;
		-m|--mode)
			[ -n "${2-}" ] ||
				fatal "$msg"
			repack="$2"
			shift
			;;
		-L|--lang)
			langlist="$2"
			shift
			;;
		-l|--initlang)
			[ -n "${2-}" ] ||
				fatal "$msg"
			initlang="$2"
			shift
			;;
		-n|--no-clean)
			no_clean=1
			;;
		-P|--pad-space)
			pad_space=1
			;;
		-q|--quiet)
			quiet=1
			;;
		-r|--reserved)
			[ -n "${2-}" ] ||
				fatal "$msg"
			reserved="$(human2size "$2")"
			shift
			;;
		-S|--swap)
			[ -n "${2-}" ] ||
				fatal "$msg"
			swapsize="$(human2size "$2")"
			shift
			;;
		-s|--secure-boot)
			secureboot=1
			target="x86_64"
			;;
		-T|--timeout)
			[ -n "${2-}" ] ||
				fatal "$msg"
			timeout="$2"
			shift
			;;
		-t|--target)
			[ -n "${2-}" ] ||
				fatal "$msg"
			case "$2" in
			x86_64)	biosboot=1
				uefiboot=1
				target="$2"
				;;
			i[3-6]86)
				biosboot=1
				uefiboot=0
				dualboot=0
				secureboot=0
				target="i586"
				;;
			aarch64)
				biosboot=0
				uefiboot=1
				secureboot=0
				target="$2"
				;;
			armh)	biosboot=0
				uefiboot=1
				dualboot=0
				secureboot=0
				target="$2"
				;;
			e2k|e2kv4|ppc64le)
				biosboot=0
				uefiboot=0
				dualboot=0
				secureboot=0
				target="$2"
				;;
			*)	fatal "Unsupported target platform: '%s'." "$2"
				;;
			esac
			shift
			;;
		-U|--uuid)
			[ -n "${2-}" ] ||
				fatal "$msg"
			rootuuid="$2"
			shift
			;;
		-u|--uefi-only)
			biosboot=0
			uefiboot=1
			target="x86_64"
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

	[ $# -ge 2 -a $# -le 3 ] ||
		fatal "$msg"
	[ -s "$1" -o -d "$1" ] ||
		fatal "Source ISO-9660 media not found: '%s'." "$1"
	media="$(realpath -- "$1")"
	[ $# -eq 2 ] ||
		capacity="$(human2size "$3")"
	if [ -d "$2" ]; then
		image="$(realpath -- "$2")/usbstick.img"
	else
		image="${2%/*}"
		[ "$image" != "$2" ] ||
			image="."
		[ -d "$image" ] ||
			fatal "Directory not exists: '%s'." "$image"
		image="$(realpath -- "$image")/${2##*/}"
	fi

	if [ -n "$datadir" -a -d "$datadir/sys-part" ]; then
		if [ -f "$datadir/EXCLUDES.lst" ]; then
			[ -z "$includes" -a -z "$excludes" ] ||
				fatal "Files list can be specified only once."
			excludes="$datadir/EXCLUDES.lst"
		fi
		if [ -f "$datadir/FILES.lst" ]; then
			[ -z "$includes" -a -z "$excludes" ] ||
				fatal "Files list can be specified only once."
			includes="$datadir/FILES.lst"
		fi
	fi

	if [ -n "$repack" ]; then
		for s_opts in $MODES; do
			[ "$s_opts" != "$repack" ] ||
				return 0
		done
		fatal "Unsupported repack mode: '%s'." "$repack"
	fi
}

cleanup() {
	trap - EXIT; cd /
	if [ -n "$workdir" -a $no_clean -eq 0 ]; then
		verbose "Cleaning work directory..."
		rm -rf --one-file-system -- "$workdir"
	fi
}

interrupt() {
	trap - INT HUP TERM QUIT USR1 USR2
	fatal "Programs execution was interrupted."
}

iso_arch_by_rpm() {
	local fname=

	ls -1 media/ALTLinux/RPMS.main/ |
	while read fname; do
		[ -f "media/ALTLinux/RPMS.main/$fname" ] ||
			continue
		[ "${fname##*.}" = "rpm" ] ||
			continue
		fname="${fname%.*}"
		fname="${fname##*.}"
		if [ "$fname" != "noarch" ]; then
			printf "%s" "$fname"
			break
		fi
	done
}

set_stages() {
	local stage=

	for stage in "$@"; do
		case "$stage" in
		altinst)
			[ $have_mrepo -ne 0 ] ||
				fatal "Install mode require '%s' repository." "ALT Main"
			[ $have_altinst -ne 0 ] ||
				fatal "Install mode require '%s' stage2 file." "altinst"
			;;
		live)	[ $have_live -ne 0 ] ||
				fatal "Live mode require '%s' stage2 file." "live"
			;;
		*)	[ $have_rescue -ne 0 ] ||
				fatal "Selected mode require '%s' stage2 file." "rescue"
			;;
		esac
	done

	stage_files="$*"
}

write_e2k_menu_entry() {
	local entry="$1" kargs="$2"
	local tty="console=ttyS0,115200 console=tty0"
	local src="automatic=method:disk,uuid:{SYSTEM_UUID}"

	cat >>loader.tpl <<-EOF
	label=$entry
	  partition=0
	  image=/alt0/vmlinux.0
	  cmdline=$tty hardreset fastboot live $src $kargs
	  initrd=/alt0/full.cz

	EOF
}

write_grub_menu_entry() {
	local entry="$1" hotkey="$2" id="$3" kargs="$4"
	local kernel="/boot/vmlinuz initrd=/boot/full.cz"
	local src="automatic=method:disk,uuid:{SYSTEM_UUID}"
	local classes="--class gnu-linux --class gnu --class os"

	cat >>loader.tpl <<-EOF
	menuentry '$entry' $classes --hotkey '$hotkey' --id '$id' --unrestricted {
	  search --no-floppy --fs-uuid --set=root {SYSTEM_UUID}
	  echo 'Loading Linux kernel...'
	  linux $kernel fastboot live $src $kargs 
	  echo 'Loading initial RAM-disk...'
	  initrd /boot/full.cz
	}

	EOF
}

write_e2k_boot_template() {
	local entry= kargs=

	case "$stage_files" in
	*live*)	  entry="live";;
	*rescue*) entry="rescue";;
	*)	  entry="install";;
	esac

	cat >loader.tpl <<-EOF
	# Auto-generated by $progname

	default=$entry
	timeout=$timeout

	EOF

	case "$stage_files" in
	*live*)
		kargs="stagename=live lowmem showopts quiet"
		write_e2k_menu_entry \
			"live"       "$kargs lang=$initlang"
		write_e2k_menu_entry \
			"live_rw"    "$kargs live_rw lang=$initlang"
		;;
	esac

	case "$stage_files" in
	*altinst*)
		kargs="stagename=altinst lowmem showopts quiet"
		write_e2k_menu_entry \
			"install"    "$kargs lang=$initlang"
		;;
	esac

	case "$stage_files" in
	*rescue*)
		kargs="stagename=rescue ramdisk_size={RAMDISKSIZE} showopts quiet"
		write_e2k_menu_entry \
			"rescue" "$kargs"
		[ $have_deploy -eq 0 ] ||
			write_e2k_menu_entry \
				"deploy" "$kargs autorun=method:disk,label:{SYSTEM_LABEL}"
		write_e2k_menu_entry \
			"rescue_rw"  "$kargs live_rw"
		write_e2k_menu_entry \
			"forensic"   "$kargs max_loop=16 forensic hash={RESCUE_HASH}"
		write_e2k_menu_entry \
			"remote_ssh" "$kargs ip=dhcp port=22 rootpw=AUTO"
		;;
	esac
}

write_grub_template() {
	local kargs=

	cat >loader.tpl <<-EOF
	insmod part_msdos
	insmod part_gpt
	insmod ext2
	insmod gzio

	if keystatus --shift; then
	  set timeout=-1
	else
	  set timeout=$timeout
	fi

	if [ "x\$lang" = "x" ]; then
	  set lang="$initlang"
	fi

	EOF

	# When packing altinst/live stages, if there is more one language in
	# the list, add this code snippet for select language. I don't know,
	# who is author, we can find him in the mkimage-profile sources.
	#
	if [ "$stage_files" != "rescue" ] && [ -n "${langlist//[^ ]/}" ]; then
		cat >>loader.tpl <<-EOF
		submenu "Change language [\$lang] (press F2)" --hotkey 'f2' {
		  insmod regexp
		  for langstr in $langlist; do
		    regexp -s 2:langname -s 1:langcode '(.*)=(.*)' "\$langstr"
		    menuentry "\$langname" "\$langcode" --unrestricted {
		      set lang="\$2"
		      export lang
		      configfile \$prefix/grub.cfg
		    }
		  done
		  menuentry "Return to the main menu" --unrestricted {
		    configfile \$prefix/grub.cfg
		  }
		}

		EOF
	fi

	case "$stage_files" in
	*live*)
		kargs="showopts quiet lang=\$lang"
		write_grub_menu_entry \
			"Try $os_type without installation" \
			"l" "live"    "stagename=live lowmem $kargs"
		write_grub_menu_entry \
			"$os_type LiveCD with session support" \
			"o" "live-rw" "stagename=live lowmem live_rw $kargs"
		;;
	esac

	case "$stage_files" in
	*altinst*)
		kargs="stagename=altinst lowmem showopts quiet lang=\$lang"
		case "$target" in
		x86_64|i586)
			kargs="$kargs splash"
			;;
		ppc64le)
			kargs="$kargs vga=normal nomodeset splash=0"
			;;
		*)	kargs="$kargs vga=normal splash=0"
			;;
		esac
		write_grub_menu_entry \
			"Install $os_type" \
			"i" "install" "$kargs"
		;;
	esac

	case "$stage_files" in
	*rescue*)
		kargs="stagename=rescue ramdisk_size={RAMDISKSIZE} showopts quiet splash=0"
		[ "$target" != "ppc64le" ] ||
			kargs="$kargs vga=normal nomodeset"
		write_grub_menu_entry \
			"Rescue LiveCD" \
			"r" "rescue"     "$kargs"
		[ $have_deploy -eq 0 ] ||
			write_grub_menu_entry \
				"Rescue Deploy (dangerous for you data!)" \
				"d" "deploy" "$kargs autorun=method:disk,label:{SYSTEM_LABEL}"
		write_grub_menu_entry \
			"Rescue LiveCD with session support" \
			"v" "rescue-rw"  "$kargs live_rw"
		write_grub_menu_entry \
			"Forensic mode (leave disks alone)" \
			"f" "forensic"   "$kargs max_loop=16 forensic hash={RESCUE_HASH}"
		write_grub_menu_entry \
			"Rescue with remote SSH access (DHCP)" \
			"s" "remote-ssh" "$kargs ip=dhcp port=22 rootpw=AUTO"
		;;
	esac

	if [ "$target" = "aarch64" -o $uefiboot -ne 0 ] ||
	   [ "$target" = "x86_64"  -a $biosboot -eq 0 ]
	then
		cat >>loader.tpl <<-EOF
		if [ "u\$grub_platform" = "uefi" ]; then
		   menuentry 'UEFI system setup' --hotkey 'u' --id 'uefi-firmware' --unrestricted {
		     fwsetup
		   }
		fi

		EOF
	fi
}

write_loader_config() {
	local type="$1" config="$2"

	verbose "Writing %s:" "$config"
	[ -s loader.tpl ] ||
		eval "write_${type}_template"
	cat loader.tpl |sed -E \
		-e 's,\{SYSTEM_UUID\},'"$rootuuid,g"    \
		-e 's,\{SYSTEM_LABEL\},'"${syslabel-},g"   \
		-e 's,\{RESCUE_HASH\},'"${rescue_hash-},g" \
		-e 's,\{RAMDISKSIZE\},'"${ramdisksize-},g" > "$config"
	[ $quiet -ne 0 ] ||
		cat "$config" >&2
	chmod $v -- 644 "$config"
}

unpack_rpm() {
	local package="$1"

	verbose "Unpacking RPM: '%s'..." "$package"
	rpm2cpio "$package" |cpio -imd $v -D rpm-root
}


# Entry point
export LC_ALL="C"
export TMPDIR="${TMPDIR:-/tmp}"
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

verbose "Option '-q' turn off verbose diagnostic."

verbose "progname='$progname'"
verbose "version='{VERSION}'"
verbose "no_clean=$no_clean"
verbose "media='$media'"
verbose "image='$image'"
verbose "quiet=$quiet"
verbose "repack='$repack'"
verbose "target='$target'"
verbose "capacity=$capacity"
verbose "reserved=$reserved"
verbose "dualboot=$dualboot"
verbose "biosboot=$biosboot"
verbose "uefiboot=$uefiboot"
verbose "secureboot=$secureboot"
verbose "gptlabel=$gptlabel"
verbose "timeout=$timeout"
verbose "includes='$includes'"
verbose "excludes='$excludes'"
verbose "rootuuid='$rootuuid'"
verbose "swapsize=$swapsize"
verbose "datadir='$datadir'"
verbose "initlang='$initlang'"
verbose "langlist='$langlist'"

# Prepare work directory
[ $quiet -eq 0 ] && v="-v" || v=
trap cleanup EXIT; umask 0022
trap interrupt INT HUP TERM QUIT USR1 USR2
workdir="$(mktemp -dt "$progname-XXXXXXXX.tmp")"
verbose "workdir='$workdir'"
rm -rf $v -- "$image"
cd "$workdir/"
mkdir -m755 $v sys-part

kernel=
initrd=
iso_arch=
os_type=
have_mrepo=0
have_rescue=0
have_deploy=0
have_altinst=0
have_live=0
foreign=0

# Unpack source media
if [ -d "$media" ]; then
	ln -snf $v -- "$media" media
	readonly_media=1
else
	case "${media##*/}" in
	*x86_64.iso)		iso_arch="x86_64";;
	*i586.iso)		iso_arch="i586";;
	*aarch64.iso)		iso_arch="aarch64";;
	*armh.iso)		iso_arch="armh";;
	*e2k.iso)		iso_arch="e2k";;
	*e2kv4.iso)		iso_arch="e2kv4";;
	*ppc64le.iso)		iso_arch="ppc64le";;
	esac

	case "${media##*/}" in
	alt-p7-*)		os_type="ALT p7 StarterKit";;
	alt-p8-*)		os_type="ALT p8 StarterKit";;
	alt-p9-*)		os_type="ALT p9 StarterKit";;
	regular-*)		os_type="ALT Regular Build";;
	alt-kworkstation-*)	os_type="ALT Workstation K";;
	alt-workstation-*)	os_type="ALT Workstation";;
	alt-education-*)	os_type="ALT Education";;
	*server-v-*)		os_type="ALT Server V";;
	*server-*)		os_type="ALT Server";;
	slinux-*|*simply-*)	os_type="Simply Linux";;
	esac

	mkdir -m755 $v media && cd media/
	verbose "Unpacking source media..."
	7z x "$media" >../unpack.log 2>&1
	media="$workdir/media"
	readonly_media=0
	cd "$workdir/"
fi
verbose "readonly_media=$readonly_media"
verbose "iso_arch='$iso_arch'"
verbose "os_type='$os_type'"

# Check platform and stages
if [ ! -s media/.disk/info ]; then
	verbose "Analyzing source media..."
else
	diskinfo="$(head -n1 media/.disk/info)"
	verbose "Analyzing source media: '%s'..." "$diskinfo"
	if [ -z "$os_type" ]; then
		case "$diskinfo" in
		*"Workstation K"*)	os_type="ALT Workstation K";;
		*"Workstation"*)	os_type="ALT Workstation";;
		*"Education"*)		os_type="ALT Education";;
		*"Server V"*)		os_type="ALT Server V";;
		*"Server"*)		os_type="ALT Server";;
		*"Rescue"*)		os_type="ALT Rescue";;
		*"Simply"*)		os_type="Simply Linux";;
		*)			os_type="ALT";;
		esac
	fi
	unset diskinfo
fi
[ ! -d media/ALTLinux/RPMS.main ] ||
	have_mrepo=1
[ ! -s media/.disk/arch ] ||
	read iso_arch < media/.disk/arch
[ $have_mrepo -eq 0 -o -n "$iso_arch" ] ||
	iso_arch="$(iso_arch_by_rpm)"
[ -n "$iso_arch" -o -n "$target" ] ||
	fatal "Target platform not specified and can't be auto-detected."
case "$iso_arch" in
i[3-6]86) iso_arch="i586";;
esac
verbose "iso_arch='$iso_arch'"
if [ -n "$iso_arch" -a -n "$target" ]; then
	if [ "$iso_arch" != "$target" ]; then
		case "$iso_arch" in
		x86_64|i586|aarch64|armh|e2k|e2kv4|ppc64le)
			fatal "Platform of this media and specified target mismatch."
			;;
		*)	fatal "Unsupported media platform: '%s'." "$iso_arch"
			;;
		esac
	fi
fi
[ -n "$target" ] ||
	target="$iso_arch"
platform="$(uname -m)"
case "$platform" in
i[3-6]86) platform="i586";;
esac
verbose "platform='$platform'"
if [ "$platform" != "$target" ]; then
	[ "$platform" = "x86_64" -a "$target" = "i586" ] ||
	[ "$platform" = "i586" -a "$target" = "x86_64" ] ||
		foreign=1
fi
verbose "target='$target'"
verbose "foreign=$foreign"
[ $foreign -eq 0 -o $have_mrepo -ne 0 -o "$target" = "e2k" -o "$target" = "e2kv4" ] ||
	fatal "Foreign mode require %s repository on the source media." "ALT Main"
[ ! -s media/altinst ] ||
	have_altinst=1
[ ! -s media/live ] ||
	have_live=1
[ ! -s media/rescue ] ||
	have_rescue=1
[ $have_altinst -ne 0 -o $have_live -ne 0 -o $have_rescue -ne 0 ] ||
	fatal "ALT stage2 files not found on the source media."
if [ -z "$datadir" ]; then
	case "$repack" in
	D|deploy)
		fatal "Deploy mode require to be datadir specified."
		;;
	esac
elif [ -s "$datadir/autorun" -o -s "$datadir/sys-part/autorun" ] ||
     [ -L "$datadir/autorun" -o -L "$datadir/sys-part/autorun" ]
then
	case "$repack" in
	""|D|deploy|R|rescue)
		repack="deploy"
		have_deploy=1
		;;
	esac
fi
#
case "$repack" in
"D"|"deploy")
	[ $have_deploy -ne 0 ] ||
		fatal "Deploy mode require autorun in the datadir."
	set_stages rescue
	;;
"R"|"rescue")
	set_stages rescue
	;;
"I"|"install")
	set_stages altinst
	;;
"L"|"live")
	set_stages live
	;;
"IR"|"install+rescue")
	set_stages altinst rescue
	;;
"IL"|"install+live")
	set_stages altinst live
	;;
"ILR"|"install+live+rescue")
	set_stages altinst live rescue
	;;
"")	if [ $have_altinst -ne 0 ]; then
		stage_files="altinst"
		[ $have_live -eq 0 ] ||
			stage_files="$stage_files live"
		[ $have_rescue -eq 0 ] ||
			stage_files="$stage_files rescue"
	elif [ $have_live -ne 0 ]; then
		stage_files="live"
		[ $have_rescue -eq 0 ] ||
			stage_files="$stage_files rescue"
	else
		stage_files="rescue"
	fi
	;;
esac
#
verbose "repack='$repack'"
verbose "have_mrepo=$have_mrepo"
verbose "have_altinst=$have_altinst"
verbose "have_live=$have_live"
verbose "have_rescue=$have_rescue"
verbose "have_deploy=$have_deploy"
unset have_altinst have_live have_rescue
unset iso_arch platform

# Search Linux kernel and Initial RAM-disk
case "$target" in
aarch64|armh)
	[ ! -s media/EFI/BOOT/vmlinuz ] ||
		kernel="EFI/BOOT/vmlinuz"
	[ ! -s media/EFI/BOOT/full.cz ] ||
		initrd="EFI/BOOT/full.cz"
	mkdir -p -m755 $v efi-part/EFI/BOOT
	mkdir -p -m755 $v sys-part/boot/efi
	;;
e2k|e2kv4)
	[ ! -s media/alt0/vmlinux.0 ] ||
		kernel="alt0/vmlinux.0"
	[ ! -s media/alt0/full.cz ] ||
		initrd="alt0/full.cz"
	mkdir -p -m755 $v e2k-part/alt0
	mkdir -p -m755 $v sys-part/boot
	;;
i586)	[ ! -s media/syslinux/alt0/vmlinuz ] ||
		kernel="syslinux/alt0/vmlinuz"
	[ ! -s media/syslinux/alt0/full.cz ] ||
		initrd="syslinux/alt0/full.cz"
	;;
ppc64le)
	[ ! -s media/boot/vmlinuz ] ||
		kernel="boot/vmlinuz"
	[ ! -s media/boot/full.cz ] ||
		initrd="boot/full.cz"
	;;
x86_64)	[ ! -s media/syslinux/alt0/vmlinuz ] ||
		kernel="syslinux/alt0/vmlinuz"
	[ ! -s media/syslinux/alt0/full.cz ] ||
		initrd="syslinux/alt0/full.cz"
	[ -n "$kernel" -o ! -s media/EFI/BOOT/vmlinuz ] ||
		kernel="EFI/BOOT/vmlinuz"
	[ -n "$initrd" -o ! -s media/EFI/BOOT/full.cz ] ||
		initrd="EFI/BOOT/full.cz"
	if [ $uefiboot -ne 0 ]; then
		mkdir -p -m755 $v efi-part/EFI/BOOT
		mkdir -p -m755 $v sys-part/boot/efi
	fi
	;;
esac
#
[ -n "$kernel" ] ||
	fatal "Linux kernel not found on the source media."
[ -n "$initrd" ] ||
	fatal "Initial RAM-disk not found on the source media."
verbose "Detected OS Type: '%s'." "$os_type"
verbose "Linux kernel image: '%s'." "$kernel"
verbose "Initial RAM-disk image: '%s'." "$initrd"
verbose "ALT stage2 files: '%s'." "$stage_files"
verbose "Target platform: '%s'." "$target"

# Check the foreign platform requires
if [ $foreign -ne 0 ]; then
	case "$target" in
	aarch64|armh)
		requires='grub-common-*.rpm grub-efi-*.rpm'
		;;
	i586)	requires='grub-common-*.rpm grub-pc-*.rpm'
		;;
	ppc64le)
		requires='grub-common-*.rpm grub-ieee1275-*.rpm'
		;;
	x86_64)	if [ $uefiboot -eq 0 -a $biosboot -ne 0 ]; then
			requires='grub-common-*.rpm grub-pc-*.rpm'
		else
			requires='grub-common-*.rpm grub-pc-*.rpm grub-efi-*.rpm'
		fi
		;;
	*)	requires=
		;;
	esac
	verbose "Requires: '$requires'"
	mkdir -m755 $v -- rpm-root
	if [ -n "$requires" ]; then
		rpmfiles=
		for rpm in $requires; do
			list="$(set +f; eval "ls -1 -- \
				media/ALTLinux/RPMS.main/$rpm" ||:)"
			[ -n "$list" ] ||
				fatal "Foreign mode require '%s' in %s repository." \
					"$pattern" "ALT Main"
			rpmfiles="$rpmfiles $list"
			unset list
		done
		if [ -n "$rpmfiles" ]; then
			verbose "rpmfiles: '$rpmfiles'"
			for rpm in $rpmfiles; do
				unpack_rpm "$rpm"
			done
		fi
		unset rpmfiles rpm
	fi
	unset requires
fi

# Copy files from source media
[ $readonly_media -eq 0 ] && cmd="mv -f" ||
	cmd="cp -Lf"
if [ -n "$excludes" ]; then
	verbose "Using 'EXCLUDES' policy:"
	{ echo "[BOOT]"
	  cat  "$excludes"
	  echo "mediacheck"
	  case "$target" in
	  aarch64|armh)
		echo "EFI"
		;;
	  e2k|e2kv4)
		echo "alt0"
		echo "boot.conf"
		;;
	  i586)	echo "syslinux"
		;;
	  ppc64le)
		echo "boot"
		echo "ppc"
		;;
	  x86_64)
		echo "EFI"
		echo "syslinux"
		;;
	  esac
	} > excludes.lst
	[ $quiet -ne 0 ] ||
		cat excludes.lst >&2
	verbose "Copying files from source media..."
	rsync -arH $v --exclude-from=excludes.lst -- media/ sys-part/
else
	verbose "Using 'INCLUDES' policy:"
	{ [ ! -d media/.disk ] ||
		echo ".disk"
	  case "$stage_files" in
	  *altinst*)
		[ $readonly_media -eq 0 ] ||
			echo "ALTLinux"
		;;
	  esac
	  [ -z "$includes" ] ||
		cat "$includes"
	} > includes.lst
	[ $quiet -ne 0 ] ||
		cat includes.lst >&2
	if [ -s includes.lst ]; then
		verbose "Copying files from source media..."
		rsync -arH $v --files-from=includes.lst -- media/ sys-part/
	fi
	verbose "Moving ALT Main repository and copy stage2 files..."
	for fname in $stage_files; do
		[ $readonly_media -ne 0 -o "$fname" != "altinst" ] ||
			mv -f $v -- media/ALTLinux sys-part/
		$cmd  $v -- "media/$fname" sys-part/
		chmod $v -- 444 "sys-part/$fname"
	done
	unset fname
fi
verbose "Copying Linux kernel and initial RAM-disk..."
if [ "$target" = "e2k" -o "$target" = "e2kv4" ]; then
	$cmd  $v -- "media/$kernel" e2k-part/alt0/vmlinux.0
	$cmd  $v -- "media/$initrd" e2k-part/alt0/full.cz
	chmod $v -- 555 e2k-part/alt0/vmlinux.0
	chmod $v -- 444 e2k-part/alt0/full.cz
else
	mkdir -p -m755 $v sys-part/boot/grub
	$cmd  $v -- "media/$kernel" sys-part/boot/vmlinuz
	$cmd  $v -- "media/$initrd" sys-part/boot/full.cz
	chmod $v -- 444 sys-part/boot/vmlinuz
	chmod $v -- 444 sys-part/boot/full.cz
fi
unset kernel initrd

# Information about this programm
mkdir -p -m755 $v -- sys-part/.disk
printf "%s %s %s\n" "$progname" "{VERSION}" \
	"$(date +%F)" > sys-part/.disk/repacked
chmod $v -- 0644 sys-part/.disk/repacked

# Overwrite disk contents by files from user-specified directory
if [ -n "$datadir" ]; then
	verbose "Adding user data files..."
	if [ ! -d "$datadir/sys-part" ]; then
		rsync -aH $v -- "$datadir/" sys-part/
	else
		[ ! -d "$datadir/efi-part" -o ! -d efi-part ] ||
			rsync -aH $v -- "$datadir/efi-part/" efi-part/
		[ ! -d "$datadir/e2k-part" -o ! -d e2k-part ] ||
			rsync -aH $v -- "$datadir/e2k-part/" e2k-part/
		[ ! -s "$datadir/loader.tpl" ] ||
			cp -Lf $v -- "$datadir/loader.tpl" ./
		[ ! -s "$datadir/SWP.img" ] ||
			cp -Lf $v -- "$datadir/SWP.img" ./
		rsync -aH $v -- "$datadir/sys-part/" sys-part/
	fi
	if [ $have_deploy -ne 0 -a ! -L sys-part/autorun ]; then
		chmod $v -- 0755 sys-part/autorun
	fi
fi

# Tune kernel arguments
case "$stage_files" in
*rescue*)
	verbose "Calculating rescue hash and neccessary RAM-disk size..."
	rescue_hash="$(sha256sum sys-part/rescue |awk '{print $1;}')"
	ramdisksize="$(du -lxsLB4k sys-part/rescue |cut -f1)"
	ramdisksize="$((4 * $ramdisksize + 1))"
	verbose "ALT Rescue stage2 hash: '%s'." "$rescue_hash"
	verbose "Initial RAM-disk size: %s %s" "$ramdisksize" "KiB"
	;;
esac
if [ -z "$rootuuid" ]; then
	if [ -e /proc/sys/kernel/random/uuid ]; then
		read rootuuid < /proc/sys/kernel/random/uuid
	else
		verbose "Preparing to create temporary extfs image..."
		[ $quiet -eq 0 ] && cmd="dir2extfs" ||
			cmd="dir2extfs --quiet"
		[ $no_clean -eq 0 ] ||
			cmd="$cmd --no-clean"
		cmd="$cmd -- /var/empty tmp-uuid.img"
		spawn
		cmd="extfsinfo --uuid -- tmp-uuid.img"
		verbose "Executing: '$cmd'..."
		rootuuid="$($cmd)"
		rm -f $v -- tmp-uuid.img
	fi
fi
[ $have_deploy -eq 0 ] && syslabel="altinst" ||
	syslabel="alt-autorun"
verbose "System partition UUID: '%s'." "$rootuuid"
verbose "System partition label: '%s'." "$syslabel"

# On Elbrus: only create boot loader configuration
if [ "$target" = "e2k" -o "$target" = "e2kv4" ]; then
	write_loader_config "e2k_boot" "e2k-part/boot.conf"
else
	# Install GRUB on other platforms
	verbose "Preparing to install boot loader files..."
	[ $quiet -eq 0 ] && cmd="grub2dirs" ||
		cmd="grub2dirs --quiet"
	cmd="$cmd --target=$target"
	[ $foreign -eq 0 ] ||
		cmd="$cmd --foreign=./rpm-root"
	if [ $biosboot -ne 0 -a $uefiboot -eq 0 ]; then
		cmd="$cmd --bios-only"
	elif [ $biosboot -eq 0 -a $uefiboot -ne 0 ]; then
		cmd="$cmd --uefi-only"
	fi
	[ $dualboot -eq 0 ] ||
		cmd="$cmd --dual-boot"
	[ $secureboot -eq 0 ] ||
		cmd="$cmd --secure-boot"
	[ $gptlabel -eq 0 ] ||
		cmd="$cmd --guid-gpt"
	[ -z "$swapsize" -a ! -s SWP.img ] ||
		cmd="$cmd --swap-part"
	cmd="$cmd --uuid=$rootuuid"
	spawn

	# Try to unpack unicode font from RPM
	if [ $foreign -eq 0 -a $have_mrepo -ne 0 ] &&
	   [ ! -s "sys-part/boot/grub/fonts/unicode.pf2" ]
	then
		rpm="$(set +f; eval 'ls -1 -- \
			media/ALTLinux/RPMS.main/grub-common-*.rpm' ||:)"
		if [ -n "$rpm" ]; then
			mkdir -p -m755 $v rpm-root
			unpack_rpm "$rpm"
			unifont="boot/grub/fonts/unicode.pf2"
			if [ -s "rpm-root/$unifont" ]; then
				verbose "Unicode font found in '%s'." "$rpm"
				cat "rpm-root/$unifont" >"sys-part/$unifont"
			fi
			unset unifont
		fi
		unset rpm
	fi

	# Create grub configuration
	write_loader_config "grub" "sys-part/boot/grub/grub.cfg"
fi

# Execute user-defined hook's...
if [ -n "$datadir" -a -d "$datadir/sys-part" -a -d "$datadir/hooks.d" ]; then
	verbose "Executing user-defined hook's..."
	cp -Lrf $v -- "$datadir/hooks.d" ./
	chmod -R $v -- 0755 hooks.d
	run-parts "$workdir/hooks.d"
	cd "$workdir/"
fi

# Remove source media clone
if [ $no_clean -eq 0 ]; then
	if [ $readonly_media -ne 0 ]; then
		rm -f $v media
	else
		verbose "Removing temporary clone of the source media..."
		rm -rf --one-file-system media
	fi
fi

# Create partitions
if [ -d efi-part ]; then
	verbose "Preparing to create ESP image..."
	[ $quiet -eq 0 ] && cmd="dir2vfat" ||
		cmd="dir2vfat --quiet"
	[ $pad_space -eq 0 ] ||
		cmd="$cmd --pad-space"
	cmd="$cmd -n STICK-ESP -- efi-part EFI.img"
	spawn
	if [ $no_clean -eq 0 ]; then
		verbose "Removing 'efi-part'..."
		rm -rf efi-part
	fi
elif [ -d e2k-part ]; then
	verbose "Preparing to create E2K /boot image..."
	[ $quiet -eq 0 ] && cmd="dir2extfs" ||
		cmd="dir2extfs --quiet"
	[ $no_clean -eq 0 ] ||
		cmd="$cmd --no-clean"
	cmd="$cmd -L STICK-E2K -- e2k-part E2K.img"
	spawn
	if [ $no_clean -eq 0 ]; then
		verbose "Removing 'e2k-part'..."
		rm -rf e2k-part
	fi
fi
verbose "Preparing to create rootfs image..."
[ $quiet -eq 0 ] && cmd="dir2extfs" ||
	cmd="dir2extfs --quiet"
[ $no_clean -eq 0 ] ||
	cmd="$cmd --no-clean"
[ -z "$reserved" ] ||
	cmd="$cmd -r $reserved"
cmd="$cmd -L $syslabel -U $rootuuid"
cmd="$cmd -- sys-part SYS.img $capacity"
spawn
if [ $no_clean -eq 0 ]; then
	verbose "Removing 'sys-part'..."
	rm -rf sys-part
fi

# Write final disk image
verbose "Preparing to write final disk image..."
[ $quiet -eq 0 ] && cmd="parts2img" ||
	cmd="parts2img --quiet"
[ $no_clean -eq 0 ] ||
	cmd="$cmd --no-clean"
[ $gptlabel -eq 0 ] ||
	cmd="$cmd --guid-gpt"
[ -z "$swapsize" ] ||
	cmd="$cmd --swap=$swapsize"
spawn
fname="${image##*/}"
mv -f $v -- probe.img "$fname"

# Calcualate checksums
verbose "Calcualating checksums..."
md5sum    "$fname" |tee checksum.MD5
sha256sum "$fname" |tee checksum.256
du -sh --apparent-size -- "$fname"
[ $readonly_media -ne 0 ] ||
	mv -f $v -- unpack.log "${image%/*}/"
mv -f $v -- checksum.MD5 checksum.256 "$fname" "${image%/*}/"

