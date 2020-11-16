#!/bin/sh -efu
### This file is covered by the GNU General Public License
### version 3 or later.
###
### Copyright (C) 2020, ALT Linux Team
### Author: Leonid Krivoshein <klark@altlinux.org>

### grub2dirs {VERSION}
### User-mode grub-install to the few directories

# Defaults
progname="${0##*/}"
platform="$(uname -m)"
libdir="/usr/lib64/grub"
[ -d "$libdir" ] ||
	libdir="/usr/lib/grub"
alt_cert="/etc/pki/uefi/altlinux.cer"
alt_shimx64="/usr/lib/shim/shimx64.efi.signed"
alt_shimia32="/usr/lib/shim/shimia32.efi.signed"
modules="ext2"
rootuuid=
dualboot=0
biosboot=0
uefiboot=0
swappart=0
secureboot=0
gptlabel=0
partsdir=
v="-v"

case "$platform" in
x86_64)	biosboot=1
	uefiboot=1
	;;
i[3-6]86)
	biosboot=1
	platform="i586"
	;;
esac


show_help() {
	cat <<-EOF
	Usage: $progname [<options>...] [--] [<partsdir>]

	Options:
	  -b, --bios-only        Make BIOS-only boottable system on x86.
	  -d, --dual-boot        Add both 32-bit and 64-bit UEFI firmware
	                         boot loaders for 64-bit target system,
	                         such as x86_64 or aarch64.
	  -g, --guid-gpt         Use GUID/GPT disk label instead BIOS/MBR.
	  -l, --libdir=<PATH>    Use images and modules under specified
	                         grub directory <path> (default is
	                         "$libdir").
	  -m, --module=<NAME>    Pre-load specified grub module.
	                         This option can set many times.
	  -q, --quiet            Suppress additional diagnostic.
	  -r, --root=<UUID>      UUID of the ROOT filesystem.
	  -S, --swap-part        Add SWAP partition before ROOT.
	  -s, --secure-boot      Use ALT shim's for UEFI Secure Boot.
	  -t, --target=<ARCH>    Use specified target architecture: i586,
	                         x86_64, aarch64, armh, ppc64le or e2k/v4.
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
	cat
	dd
	getopt
	grep
	mkdir
	realpath
	sed
	uname
}

verbose() {
	local fmt="$1"; shift

	[ -z "$v" ] || printf "$fmt\n" "$@" >&2
}

warning() {
	local fmt="$1"; shift

	printf "%s warning: $fmt\n" "$progname" "$@" >&2
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

parse_args() {
	local s_opts="+bdgl:m:qr:Sst:U:uvh"
	local l_opts="bios-only,dual-boot,guid-gpt,libdir:,module:,quiet,root:"
	      l_opts="$l_opts,swap-part,secure-boot,target:,uefi-only,uuid:,version,help"
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
		-d|--dual-boot)
			uefiboot=1
			dualboot=1
			;;
		-g|--guid-gpt)
			gptlabel=1
			;;
		-l|--libdir)
			[ -n "${2-}" ] ||
				fatal "$msg"
			[ -d "$2" ] ||
				fatal "Directory not found: '%s'." "$2"
			libdir="$(realpath -- "$2")"
			shift
			;;
		-m|--module)
			[ -n "${2-}" ] ||
				fatal "$msg"
			modules="$modules $2"
			shift
			;;
		-q|--quiet)
			v=
			;;
		-r|--root)
			[ -n "${2-}" ] ||
				fatal "$msg"
			warning "Deprecated option found: '%s'." "$1"
			warning "This option was renamed to '%s'." "--uuid"
			rootuuid="$2"
			shift
			;;
		-S|--swap-part)
			swappart=1
			;;
		-s|--secure-boot)
			uefiboot=1
			secureboot=1
			;;
		-t|--target)
			[ -n "${2-}" ] ||
				fatal "$msg"
			case "$2" in
			x86_64)	biosboot=1
				uefiboot=1
				platform="$2"
				;;
			i[3-6]86)
				biosboot=1
				uefiboot=0
				dualboot=0
				secureboot=0
				platform="i586"
				;;
			*)	biosboot=0
				uefiboot=0
				dualboot=0
				secureboot=0
				platform="$2"
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

	if [ $uefiboot -eq 0 ]; then
		dualboot=0; secureboot=0
	elif [ -z "$rootuuid" ]; then
		read rootuuid < /proc/sys/kernel/random/uuid
	fi
	if [ $# -eq 1 ]; then
		[ -n "$1" -a -d "$1" ] ||
			fatal "$msg"
		partsdir="$(realpath -- "$1")"
	else
		[ $# -eq 0 ] ||
			fatal "$msg"
		partsdir="$(realpath .)"
	fi
}

prepare_boot_dirs() {
	if [ $uefiboot -ne 0 ]; then
		mkdir $v -p -m755 -- "$efidir/EFI/BOOT"
		mkdir $v -p -m755 -- "$sysdir/boot/efi"
		cat >"$efidir/EFI/BOOT/grub.cfg" <<-EOF
		search.fs_uuid $rootuuid root
		set prefix=(\$root)/boot/grub
		configfile \$prefix/grub.cfg
		EOF
	fi
	mkdir $v -p -m755 -- "$sysdir/boot/grub/fonts"
	mkdir $v -p -m755 -- "$sysdir/boot/grub/locale"
	[ ! -s /usr/share/grub/unicode.pf2 ] ||
		cp -Lf $v -- \
			/usr/share/grub/unicode.pf2 \
			"$sysdir/boot/grub/fonts/"
	{ echo "# GRUB Environment Block"
	  dd if=/dev/zero bs=999 count=1 |sed 's,.,#,g'
	} > "$sysdir/boot/grub/grubenv" 2>/dev/null
}

copy_target_files() {
	local tgtdir="$sysdir/boot/grub/$target" fname=

	cd "$libdir/$target"/
	mkdir $v -p -m755 -- "$tgtdir"
	set +f

	for fname in *; do
		[ "$fname" != '*' -a -f "$fname" ] ||
			continue
		if [ "${fname##*.}" = "mod" ]; then
			cp -Lf $v -- "$fname" "$tgtdir"/
		elif [ "${fname##*.}" = "lst" ]; then
			cp -Lf $v -- "$fname" "$tgtdir"/
		elif [ "$fname" = "modinfo.sh" ]; then
			cp -Lf $v -- "$fname" "$tgtdir"/
		fi
	done

	set -f
	cd "$OLDPWD"
}

make_early_conf() {
	sb="$sysdir/boot/grub/$target/load.cfg"
	cat >"$sb" <<-EOF
	search.fs_uuid $rootuuid root
	set prefix=(\$root)/boot/grub
	EOF
	sb="--config '$sb'"
}

prepare_bios() {
	local mbr=

	target="i386-pc"; copy_target_files
	[ ! -s "$libdir/$target/efiemu32.o" ] ||
		cp -Lf $v -- \
			"$libdir/$target/efiemu32.o" \
			"$sysdir/boot/grub/$target/"
	[ ! -s "$libdir/$target/efiemu64.o" ] ||
		cp -Lf $v -- \
			"$libdir/$target/efiemu64.o" \
			"$sysdir/boot/grub/$target/"
	mbr="$partsdir/$target-boot.img"
	cp -Lf $v -- "$libdir/$target/boot.img" "$mbr"

	{ # The offset of KERNEL_SECTOR at 0x05C, 4 bytes
	  printf "\x01\x00\x00\x00" |dd bs=1 seek=92 count=4 conv=notrunc of="$mbr"
	  # The offset of BOOT_DRIVE_CHECK at 0x066, 2 bytes
	  printf "\x90\x90" |dd bs=1 seek=102 count=2 conv=notrunc of="$mbr"
	  # The Disk Identifier used by Windows NT at 0x1B8, 4 bytes
	  dd if=/dev/urandom bs=1 seek=440 count=4 conv=notrunc of="$mbr"
	  # The Copy-Protected flag at 0x1BC, 2 bytes
	  printf "\x00\x00" |dd bs=1 seek=444 count=2 conv=notrunc of="$mbr"
	} >/dev/null 2>&1

	cmd="$mki --directory '$libdir/$target' --prefix '$prefix'"
	cmd="$cmd --output '$partsdir/$target-core.img'"
	cmd="$cmd --format '$target' --compression auto"
	cmd="$cmd $v  $modules part_$pttype biosdisk"
	spawn
	verbose "All $target files installed."
}

setup_x86() {
	if [ $gptlabel -eq 0 ]; then
		[ $uefiboot -eq 0 ] &&
			sys_part=1 || sys_part=2
		pttype="msdos"
	else
		[ $uefiboot -ne 0 -a $biosboot -ne 0 ] &&
			sys_part=3 || sys_part=2
		pttype="gpt"
	fi
	[ $swappart -eq 0 ] || sys_part="$((1 + $sys_part))"
	prefix="(,${pttype}${sys_part})/boot/grub"
	[ $biosboot -eq 0 ] || prepare_bios
}

prepare_prefix() {
	sys_part=2
	[ $gptlabel -eq 0 ] && pttype="msdos" || pttype="gpt"
	[ $swappart -eq 0 ] || sys_part="$((1 + $sys_part))"
	prefix="(,${pttype}${sys_part})/boot/grub"
}

setup_arm32() {
	target="arm-efi"; copy_target_files
	cmd="$mki --directory '$libdir/$target' --prefix '$prefix'"
	cmd="$cmd --output '$efidir/EFI/BOOT/BOOTARM.EFI'"
	cmd="$cmd --format '$target' --compression auto"
	cmd="$cmd $v  $modules part_$pttype"
	spawn
	cmd="$mki --directory '$libdir/$target' --prefix ''"
	cmd="$cmd --output '$sysdir/boot/grub/$target/grub.efi'"
	cmd="$cmd --format '$target' --compression auto"
	cmd="$cmd $v  $modules part_$pttype"
	spawn
	verbose "All $target files installed."
}

copy_signed_binary() {
	local src= dest="$1"; shift
	local pesign="$(command -v pesign)"

	for src in "$@"; do
		[ -s "$src" ] ||
			continue
		$pesign -S -i "$src" 2>&1 |grep -qs 'certificate address is ' ||
			continue
		break
	done

	cp -Lf $v -- "$src" "$dest"
}


# Entry point
export LC_ALL="C"
export PATH="/sbin:/usr/sbin:/bin:/usr/bin"

parse_args "$@"

umask 0022
efidir="$partsdir/efi-part"
sysdir="$partsdir/sys-part"
mki="$(command -v grub-mkimage ||:)"
err_type1="must be installed before run this program."
err_type2="not supported by target platform."
no_grub="GRUB $err_type1"
no_shim="shim-signed $err_type1"
no_cert="alt-uefi-certs $err_type1"
no_sign="pesign utility $err_type1"
no_uefi_sb="UEFI & Secure Boot $err_type2"
no_bios="BIOS-boot mode $err_type2"
no_uefi="UEFI-boot mode $err_type2"
no_secboot="Secure Boot $err_type2"
unset err_type1 err_type2

case "$platform" in
x86_64)	# Require separate EFI partition and GRUB installed
	[ $biosboot -eq 0 -o -s "$libdir/i386-pc/boot.img" ] &&
	[ $dualboot -eq 0 -o -s "$libdir/i386-efi/moddep.lst" ] &&
	[ $uefiboot -eq 0 -o -s "$libdir/x86_64-efi/moddep.lst" ] &&
	[ -x "$mki" ] ||
		fatal "$no_grub"
	if [ $secureboot -ne 0 ]; then
		[ -s "$alt_shimx64" ] ||
			fatal "$no_shim"
		[ -s "$alt_cert" ] ||
			fatal "$no_cert"
		command -v pesign >/dev/null ||
			fatal "$no_sign"
	fi

	prepare_boot_dirs
	setup_x86

	if [ $dualboot -ne 0 ]; then
		target="i386-efi"; copy_target_files
		[ $secureboot -eq 0 -o ! -s "$alt_shimia32" ] &&
			sb= || make_early_conf
		cmd="$mki --directory '$libdir/$target' --prefix '$prefix'"
		cmd="$cmd --output '$partsdir/$target-core.efi'"
		cmd="$cmd --format '$target' --compression auto"
		cmd="$cmd $v $sb  $modules part_$pttype"
		[ -z "$sb" ] || cmd="$cmd search_fs_uuid"
		spawn
		cmd="$mki --directory '$libdir/$target' --prefix ''"
		cmd="$cmd --output '$sysdir/boot/grub/$target/grub.efi'"
		cmd="$cmd --format '$target' --compression auto"
		cmd="$cmd $v $sb  $modules part_$pttype"
		[ -z "$sb" ] || cmd="$cmd search_fs_uuid"
		spawn

		if [ -z "$sb" ]; then
			cp -Lf $v -- \
				"$partsdir/$target-core.efi" \
				"$efidir/EFI/BOOT/BOOTIA32.EFI"
		else
			copy_signed_binary \
				"$efidir/EFI/BOOT/grubia32.efi" \
				"/usr/lib64/efi/grubia32sb.efi" \
				"/usr/lib64/efi/grubia32.efi" \
				"$partsdir/$target-core.efi"
			cp -Lf $v -- \
				"$alt_shimia32" \
				"$efidir/EFI/BOOT/BOOTIA32.EFI"
		fi

		unset sb
		verbose "All $target files installed."
	fi

	if [ $uefiboot -ne 0 ]; then
		target="x86_64-efi"; copy_target_files
		[ $secureboot -eq 0 ] && sb= || make_early_conf
		cmd="$mki --directory '$libdir/$target' --prefix '$prefix'"
		cmd="$cmd --output '$partsdir/$target-core.efi'"
		cmd="$cmd --format '$target' --compression auto"
		cmd="$cmd $v $sb  $modules part_$pttype"
		[ -z "$sb" ] || cmd="$cmd search_fs_uuid"
		spawn
		cmd="$mki --directory '$libdir/$target' --prefix ''"
		cmd="$cmd --output '$sysdir/boot/grub/$target/grub.efi'"
		cmd="$cmd --format '$target' --compression auto"
		cmd="$cmd $v $sb  $modules part_$pttype"
		[ -z "$sb" ] || cmd="$cmd search_fs_uuid"
		spawn

		if [ $secureboot -eq 0 ]; then
			cp -Lf $v -- \
				"$partsdir/$target-core.efi" \
				"$efidir/EFI/BOOT/BOOTX64.EFI"
		else
			copy_signed_binary \
				"$efidir/EFI/BOOT/grubx64.efi" \
				"/usr/lib64/efi/grubx64sb.efi" \
				"/usr/lib64/efi/grubx64.efi" \
				"$partsdir/$target-core.efi"
			cp -Lf $v -- \
				"$alt_shimx64" \
				"$efidir/EFI/BOOT/BOOTX64.EFI"
			mkdir $v -p -m755 -- "$efidir/EFI/enroll"
			cp -Lf $v -- "$alt_cert" "$efidir/EFI/enroll/"
		fi

		unset sb
		verbose "All $target files installed."
	fi
	;;

i[3-6]86)
	# Require only grub-pc installed
	[ -x "$mki" -a -d "$libdir/i386-pc" ] ||
		fatal "$no_grub"
	if [ $secureboot -ne 0 ]; then
		warning "$no_uefi_sb"
		secureboot=0
		uefiboot=0
	elif [ $uefiboot -ne 0 ]; then
		warning "$no_uefi"
		uefiboot=0
	fi

	dualboot=0
	biosboot=1
	prepare_boot_dirs
	setup_x86
	;;

aarch64)
	# Require separate EFI partition and grub-efi installed
	[ $dualboot -eq 0 -o -s "$libdir/arm-efi/moddep.lst" ] &&
	[ -x "$mki" -a -s "$libdir/arm64-efi/moddep.lst" ] ||
		fatal "$no_grub"
	if [ $secureboot -ne 0 ]; then
		warning "$no_secboot"
		secureboot=0
	fi
	if [ $biosboot -ne 0 ]; then
		warning "$no_bios"
		biosboot=0
	fi

	uefiboot=1
	prepare_boot_dirs
	prepare_prefix

	[ $dualboot -eq 0 ] ||
		setup_arm32

	if [ $uefiboot -ne 0 ]; then
		target="arm64-efi"; copy_target_files
		cmd="$mki --directory '$libdir/$target' --prefix '$prefix'"
		cmd="$cmd --output '$efidir/EFI/BOOT/BOOTAA64.EFI'"
		cmd="$cmd --format '$target' --compression auto"
		cmd="$cmd $v  $modules part_$pttype"
		spawn
		cmd="$mki --directory '$libdir/$target' --prefix ''"
		cmd="$cmd --output '$sysdir/boot/grub/$target/grub.efi'"
		cmd="$cmd --format '$target' --compression auto"
		cmd="$cmd $v  $modules part_$pttype"
		spawn
		verbose "All $target files installed."
	fi
	;;

armh)	# Require separate EFI partition and grub-efi installed
	[ -x "$mki" -a -s "$libdir/arm-efi/moddep.lst" ] ||
		fatal "$no_grub"
	if [ $secureboot -ne 0 ]; then
		warning "$no_secboot"
		secureboot=0
	fi
	if [ $biosboot -ne 0 ]; then
		warning "$no_bios"
		biosboot=0
	fi

	dualboot=0
	uefiboot=1
	prepare_boot_dirs
	prepare_prefix
	setup_arm32
	;;

ppc64le)
	# Require separate PReP partition and grub-ieee1275 installed
	[ -x "$mki" -a -s "$libdir/powerpc-ieee1275/bootinfo.txt" ] ||
		fatal "$no_grub"
	if [ $secureboot -ne 0 ]; then
		warning "$no_uefi_sb"
		secureboot=0
		uefiboot=0
	elif [ $uefiboot -ne 0 ]; then
		warning "$no_uefi"
		uefiboot=0
	fi
	if [ $biosboot -ne 0 ]; then
		warning "$no_bios"
		biosboot=0
	fi

	dualboot=0
	prepare_boot_dirs
	mkdir $v -p -m755 -- "$sysdir/ppc/chrp"
	prepare_prefix

	if [ $biosboot -eq 0 ]; then
		target="powerpc-ieee1275"; copy_target_files
		cmd="$mki --directory '$libdir/$target' --prefix '$prefix'"
		cmd="$cmd --output '$partsdir/$target-powerpc.elf'"
		cmd="$cmd --format '$target' --compression auto"
		cmd="$cmd $v  $modules part_$pttype"
		spawn
		cp -Lf $v -- "$libdir/$target/bootinfo.txt" "$sysdir/ppc/"
		verbose "All $target files installed."
	fi
	;;

*)
	fatal "Unsupported target platform: '%s'." "$platform"
	;;
esac

