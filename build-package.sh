#!/bin/bash

# Required setup for ubuntu (only tested on 15.04):
# $ apt install asciidoc automake bison cmake flex gettext libglib2.0-dev help2man libc6-dev-i386 libcurl4-openssl-dev libgdk-pixbuf2.0-dev libncurses5-dev libtool lzip m4 mercurial pkg-config scons texinfo xmlto xutils-dev
#   where libc6-dev-i386 is needed by luajit host part of the build for <sys/cdefs.h>
#         xutils-dev provides 'makedepend' which openssl build uses
#         gettext provides 'msgfmt' which apt build uses
#         libcurl4-openssl-dev is needed by apt build
#         libglib2.0-dev provides 'glib-genmarshal' which glib build uses
#         libgdk-pixbuf2.0-dev provides 'gdk-pixbuf-query-loaders' which librsvg build uses
# Required setup for mac (not regularly used, and may not build all packages):
# $ port install asciidoc bison cmake flex gnutar help2man lzip mercurial p5-libwww-perl pkgconfig scons xmlto
#   where Busybox requires that sed is gsed: ln -s /opt/local/bin/gsed /opt/local/bin/sed

set -e -o pipefail -u

if [ "$#" -ne 1 ]; then echo "ERROR: Specify one argument!"; exit 1; fi
export TERMUX_PKG_NAME=$1
export TERMUX_SCRIPTDIR=`cd $(dirname $0); pwd`
export TERMUX_PKG_BUILDER_DIR=$TERMUX_SCRIPTDIR/packages/$TERMUX_PKG_NAME
export TERMUX_PKG_BUILDER_SCRIPT=$TERMUX_PKG_BUILDER_DIR/build.sh
if test ! -f $TERMUX_PKG_BUILDER_SCRIPT; then echo "ERROR: No such package builder: ${TERMUX_PKG_BUILDER_SCRIPT}!"; exit 1; fi

echo "termux - building $1..."
test -t 1 && printf "\033]0;$1...\007"

# Read settings from .termuxrc if existing
test -f $HOME/.termuxrc && . $HOME/.termuxrc

# Configurable settings
: ${NDK:="${HOME}/lib/android-ndk"}
: ${ANDROID_HOME:="${HOME}/lib/android-sdk"}
if [ ! -d "$NDK" ]; then echo 'ERROR: $NDK not defined as pointing at a directory - define it pointing at a android NDK installation!'; exit 1; fi
: ${TERMUX_MAKE_PROCESSES:='4'}
: ${TERMUX_TOPDIR:="$HOME/termux"}
: ${TERMUX_ARCH:="arm"}
: ${TERMUX_HOST_PLATFORM:="${TERMUX_ARCH}-linux-android"}
if [ $TERMUX_ARCH = "arm" ]; then TERMUX_HOST_PLATFORM="${TERMUX_HOST_PLATFORM}eabi"; fi
: ${TERMUX_PREFIX:='/data/data/com.termux/files/usr'}
: ${TERMUX_ANDROID_HOME:='/data/data/com.termux/files/home'}
: ${TERMUX_DEBUG:=""}
: ${TERMUX_PROCESS_DEB:=""}
: ${TERMUX_GCC_VERSION:="4.9"}
: ${TERMUX_API_LEVEL:="21"}
: ${TERMUX_STANDALONE_TOOLCHAIN:="$HOME/lib/android-standalone-toolchain-${TERMUX_ARCH}-api${TERMUX_API_LEVEL}-gcc${TERMUX_GCC_VERSION}"}
: ${TERMUX_ANDROID_BUILD_TOOLS_VERSION:="22.0.1"}
# We do not put all of build-tools/$TERMUX_ANDROID_BUILD_TOOLS_VERSION/ into PATH
# to avoid stuff like arm-linux-androideabi-ld there to conflict with ones from
# the standalone toolchain.
TERMUX_DX=$ANDROID_HOME/build-tools/$TERMUX_ANDROID_BUILD_TOOLS_VERSION/dx

# We put this after system PATH to avoid picking up toolchain stripped python
export PATH=$PATH:$TERMUX_STANDALONE_TOOLCHAIN/bin

# Make $TERMUX_TAR and $TERMUX_TOUCH point at gnu versions:
export TERMUX_TAR="tar"
test `uname` = "Darwin" && TERMUX_TAR=gnutar
export TERMUX_TOUCH="touch"
test `uname` = "Darwin" && TERMUX_TOUCH=gtouch

# Compute NDK version. We remove the first character (the r in e.g. r9d) to get a version number which can be used in packages):
export TERMUX_NDK_VERSION=`cut -d ' ' -f 1 $NDK/RELEASE.TXT | cut -c 2-`

export prefix=${TERMUX_PREFIX} # prefix is used by some makefiles
#export ACLOCAL="aclocal -I $TERMUX_PREFIX/share/aclocal"
export AR=$TERMUX_HOST_PLATFORM-ar
export AS=${TERMUX_HOST_PLATFORM}-gcc
export CC=$TERMUX_HOST_PLATFORM-gcc
export CPP=${TERMUX_HOST_PLATFORM}-cpp
export CXX=$TERMUX_HOST_PLATFORM-g++
export CC_FOR_BUILD=gcc
export LD=$TERMUX_HOST_PLATFORM-ld
export OBJDUMP=$TERMUX_HOST_PLATFORM-objdump
# Setup pkg-config for cross-compiling:
export PKG_CONFIG=$TERMUX_STANDALONE_TOOLCHAIN/bin/${TERMUX_HOST_PLATFORM}-pkg-config
export PKG_CONFIG_LIBDIR=$TERMUX_PREFIX/lib/pkgconfig
export RANLIB=$TERMUX_HOST_PLATFORM-ranlib
export READELF=$TERMUX_HOST_PLATFORM-readelf
export STRIP=$TERMUX_HOST_PLATFORM-strip

_SPECSFLAG="-specs=$TERMUX_SCRIPTDIR/termux.spec"
export CFLAGS="$_SPECSFLAG"
export LDFLAGS="$_SPECSFLAG -L${TERMUX_PREFIX}/lib"

if [ "$TERMUX_ARCH" = "arm" ]; then
        # For hard support: http://blog.alexrp.com/2014/02/18/android-hard-float-support/
        # "First, to utilize the hard float ABI, you must either compile every last component of your application
        # as hard float (the -mhard-float GCC/Clang switch), or mark individual functions with the appropriate
        # __attribute__ to indicate the desired ABI. For example, to mark a function so that it’s called with the
        # soft float ABI, stick __attribute__((pcs("aapcs"))) on it.
        # Note that the NDK will link to a libm which uses the aforementioned attribute on all of its functions.
        # This means that if you use libm functions a lot, you’re not likely to get much of a boost in those places.
        # The way to fix this is to add -mhard-float -D_NDK_MATH_NO_SOFTFP=1 to your GCC/Clang command line. Then
        # add -lm_hard to your linker command line (or -Wl,-lm_hard if you just invoke GCC/Clang to link). This will
        # make your application link statically to a libm compiled for the hard float ABI. The only downside of this
        # is that your application will increase somewhat in size."
	CFLAGS+=" -march=armv7-a -mfpu=neon -mhard-float -Wl,--no-warn-mismatch"
 	LDFLAGS+=" -march=armv7-a -Wl,--no-warn-mismatch"
elif [ $TERMUX_ARCH = "i686" ]; then
	# From $NDK/docs/CPU-ARCH-ABIS.html:
	CFLAGS+=" -march=i686 -msse3 -mstackrealign -mfpmath=sse"
fi

if [ -n "$TERMUX_DEBUG" ]; then
        CFLAGS+=" -g3 -Og -fstack-protector --param ssp-buffer-size=4 -D_FORTIFY_SOURCE=2"
else
        CFLAGS+=" -Os"
fi

export CXXFLAGS="$CFLAGS"
export CPPFLAGS="-I${TERMUX_PREFIX}/include"

export ac_cv_func_getpwent=no
export ac_cv_func_getpwnam=no
export ac_cv_func_getpwuid=no

if [ ! -d $TERMUX_STANDALONE_TOOLCHAIN ]; then
	_TERMUX_NDK_TOOLCHAIN_NAME=""
	if [ "arm" = $TERMUX_ARCH ]; then
		_TERMUX_NDK_TOOLCHAIN_NAME="$TERMUX_HOST_PLATFORM"
	elif [ "i686" = $TERMUX_ARCH ]; then
		_TERMUX_NDK_TOOLCHAIN_NAME="x86"
	fi
	bash $NDK/build/tools/make-standalone-toolchain.sh --platform=android-$TERMUX_API_LEVEL --toolchain=${_TERMUX_NDK_TOOLCHAIN_NAME}-${TERMUX_GCC_VERSION} \
		--install-dir=$TERMUX_STANDALONE_TOOLCHAIN --system=`uname | tr '[:upper:]' '[:lower:]'`-x86_64
        if [ "arm" = $TERMUX_ARCH ]; then
                # Fix to allow e.g. <bits/c++config.h> to be included:
                cp $TERMUX_STANDALONE_TOOLCHAIN/include/c++/$TERMUX_GCC_VERSION/arm-linux-androideabi/armv7-a/bits/* $TERMUX_STANDALONE_TOOLCHAIN/include/c++/$TERMUX_GCC_VERSION/bits
        fi
	cd $TERMUX_STANDALONE_TOOLCHAIN/sysroot
	for f in $TERMUX_SCRIPTDIR/ndk_patches/*.patch; do
		sed "s%\@TERMUX_PREFIX\@%${TERMUX_PREFIX}%g" $f | \
			sed "s%\@TERMUX_HOME\@%${TERMUX_ANDROID_HOME}%g" | \
			patch -p1;
		echo "PATCHING FILE $f done!"
	done
	# sha1.h was removed from android ndk for platforms above 19, but needed by the aapt package
	# JNIHelp.h is also used by aapt
	# sysexits.h is header-only and used by some unix code
        cp $TERMUX_SCRIPTDIR/ndk_patches/{sha1.h,sysexits.h,JNIHelp.h} $TERMUX_STANDALONE_TOOLCHAIN/sysroot/usr/include
fi

export TERMUX_COMMON_CACHEDIR="$TERMUX_TOPDIR/_cache"
export TERMUX_COMMON_DEBDIR="$TERMUX_TOPDIR/_deb"
mkdir -p $TERMUX_COMMON_CACHEDIR $TERMUX_COMMON_DEBDIR

# Get fresh versions of config.sub and config.guess
for f in config.sub config.guess; do test ! -f $TERMUX_COMMON_CACHEDIR/$f && curl "http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=${f};hb=HEAD" > $TERMUX_COMMON_CACHEDIR/$f; done
# Have a debian-binary file ready for deb packaging:
test ! -f $TERMUX_COMMON_CACHEDIR/debian-binary && echo "2.0" > $TERMUX_COMMON_CACHEDIR/debian-binary
# The host tuple that may be given to --host configure flag, but normally autodetected so not needed explicitly
TERMUX_HOST_TUPLE=`sh $TERMUX_COMMON_CACHEDIR/config.guess`

TERMUX_PKG_BUILDDIR=$TERMUX_TOPDIR/$TERMUX_PKG_NAME/build
TERMUX_PKG_CACHEDIR=$TERMUX_TOPDIR/$TERMUX_PKG_NAME/cache
TERMUX_PKG_MASSAGEDIR=$TERMUX_TOPDIR/$TERMUX_PKG_NAME/massage
TERMUX_PKG_PACKAGEDIR=$TERMUX_TOPDIR/$TERMUX_PKG_NAME/package
TERMUX_PKG_SRCDIR=$TERMUX_TOPDIR/$TERMUX_PKG_NAME/src
TERMUX_PKG_TMPDIR=$TERMUX_TOPDIR/$TERMUX_PKG_NAME/tmp
TERMUX_PKG_HOSTBUILD_DIR=$TERMUX_TOPDIR/$TERMUX_PKG_NAME/host-build
TERMUX_PKG_PLATFORM_INDEPENDENT=""
TERMUX_PKG_NO_DEVELSPLIT=""
TERMUX_PKG_BUILD_REVISION="0" # http://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-Version
TERMUX_PKG_EXTRA_CONFIGURE_ARGS=""
TERMUX_PKG_EXTRA_HOSTBUILD_CONFIGURE_ARGS=""
TERMUX_PKG_EXTRA_MAKE_ARGS=""
TERMUX_PKG_BUILD_IN_SRC=""
TERMUX_PKG_RM_AFTER_INSTALL=""
TERMUX_PKG_DEPENDS=""
TERMUX_PKG_HOMEPAGE=""
TERMUX_PKG_DESCRIPTION="FIXME:Add description"
TERMUX_PKG_FOLDERNAME=""
TERMUX_PKG_KEEP_STATIC_LIBRARIES="false"
TERMUX_PKG_KEEP_HEADER_FILES="false"
TERMUX_PKG_ESSENTIAL=""
TERMUX_PKG_CONFFILES=""
# Set if a host build should be done in TERMUX_PKG_HOSTBUILD_DIR:
TERMUX_PKG_HOSTBUILD=""
TERMUX_PKG_MAINTAINER="Fredrik Fornwall <fredrik@fornwall.net>"

# Cleanup old state
rm -Rf   $TERMUX_PKG_BUILDDIR $TERMUX_PKG_PACKAGEDIR $TERMUX_PKG_SRCDIR $TERMUX_PKG_TMPDIR $TERMUX_PKG_MASSAGEDIR
# Ensure folders present (but not $TERMUX_PKG_SRCDIR, it will be created in build)
mkdir -p $TERMUX_PKG_BUILDDIR $TERMUX_PKG_PACKAGEDIR $TERMUX_PKG_TMPDIR $TERMUX_PKG_CACHEDIR $TERMUX_PKG_MASSAGEDIR $PKG_CONFIG_LIBDIR $TERMUX_PREFIX/{bin,lib,share,tmp}

# If $TERMUX_PREFIX already exists, it may have been built for a different arch
TERMUX_ARCH_FILE=/data/TERMUX_ARCH
if [ -f "${TERMUX_ARCH_FILE}" ]; then
        TERMUX_PREVIOUS_ARCH=`cat $TERMUX_ARCH_FILE`
        if [ $TERMUX_PREVIOUS_ARCH != $TERMUX_ARCH ]; then
                TERMUX_DATA_BACKUPDIRS=$TERMUX_TOPDIR/_databackups
                mkdir -p $TERMUX_DATA_BACKUPDIRS
                TERMUX_DATA_PREVIOUS_BACKUPDIR=$TERMUX_DATA_BACKUPDIRS/$TERMUX_PREVIOUS_ARCH
                TERMUX_DATA_CURRENT_BACKUPDIR=$TERMUX_DATA_BACKUPDIRS/$TERMUX_ARCH
                echo "NOTE: Different archs - building for $TERMUX_ARCH, but current $TERMUX_PREVIOUS_ARCH"
                echo "      Saving current /data/data to $TERMUX_DATA_PREVIOUS_BACKUPDIR"
                # Save current /data (removing old backup if any)
		if test -e $TERMUX_DATA_PREVIOUS_BACKUPDIR; then
			echo "ERROR: Directory already exists"
			exit 1
		fi
                mv /data/data $TERMUX_DATA_PREVIOUS_BACKUPDIR
                # Restore new one (if any)
                if [ -d $TERMUX_DATA_CURRENT_BACKUPDIR ]; then
                        echo "      Restoring old backupdir from $TERMUX_DATA_CURRENT_BACKUPDIR"
                        mv $TERMUX_DATA_CURRENT_BACKUPDIR /data/data
                fi
        fi
fi
echo $TERMUX_ARCH > $TERMUX_ARCH_FILE

if [ ! -f $PKG_CONFIG ]; then
	echo "Creating pkg-config wrapper..."
	# We use path to host pkg-config to avoid picking up a cross-compiled pkg-config later on
	_HOST_PKGCONFIG=`which pkg-config`
	mkdir -p $TERMUX_STANDALONE_TOOLCHAIN/bin $PKG_CONFIG_LIBDIR
	cat > $PKG_CONFIG <<HERE
#!/bin/sh
export PKG_CONFIG_DIR=
export PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR
# export PKG_CONFIG_SYSROOT_DIR=${TERMUX_PREFIX}
exec $_HOST_PKGCONFIG "\$@"
HERE
	chmod +x $PKG_CONFIG

	# Add a pkg-config file for the system zlib
	cat > $PKG_CONFIG_LIBDIR/zlib.pc <<HERE
Name: zlib
Description: zlib compression library
Version: 1.2.3

Requires:
Libs: -L$TERMUX_STANDALONE_TOOLCHAIN/sysroot/usr/lib -lz
Cflags: -I$TERMUX_STANDALONE_TOOLCHAIN/sysroot/usr/include
HERE
        sleep 1 # Sleep so that zlib.c get older timestamp then TERMUX_BUILD_TS_FILE.
fi

TERMUX_ELF_CLEANER=$TERMUX_COMMON_CACHEDIR/termux-elf-cleaner
if [ ! -f $TERMUX_ELF_CLEANER ]; then
	g++ -std=c++11 -Wall -Wextra -pedantic -Os $TERMUX_SCRIPTDIR/packages/termux-tools/termux-elf-cleaner.cpp -o $TERMUX_ELF_CLEANER
fi

# Keep track of when build started so we can see what files have been created
export TERMUX_BUILD_TS_FILE=$TERMUX_PKG_TMPDIR/timestamp_$TERMUX_PKG_NAME
rm -f $TERMUX_BUILD_TS_FILE && touch $TERMUX_BUILD_TS_FILE

# Run just after sourcing $TERMUX_PKG_BUILDER_SCRIPT
termux_step_extract_package () {
        if [ -z "${TERMUX_PKG_SRCURL:=""}" ]; then
                mkdir -p $TERMUX_PKG_SRCDIR
                return
        fi
	cd $TERMUX_PKG_TMPDIR
	filename=`basename $TERMUX_PKG_SRCURL`
	file=$TERMUX_PKG_CACHEDIR/$filename
	# Set "TERMUX_PKG_NO_SRC_CACHE=yes" in package to never cache packages, such as in git builds:
	test -n ${TERMUX_PKG_NO_SRC_CACHE-""} -o ! -f $file && curl --retry 3 -o $file -L $TERMUX_PKG_SRCURL
	if [ "x$TERMUX_PKG_FOLDERNAME" = "x" ]; then
		folder=`basename $filename .tar.bz2` && folder=`basename $folder .tar.gz` && folder=`basename $folder .tar.xz` && folder=`basename $folder .tar.lz` && folder=`basename $folder .tgz` && folder=`basename $folder .zip`
		folder=`echo $folder | sed 's/_/-/'` # dpkg uses _ in tar filename, but - in folder
	else
		folder=$TERMUX_PKG_FOLDERNAME
	fi
	rm -Rf $folder
	if [ ${file##*.} = zip ]; then
		unzip $file
	else
		$TERMUX_TAR xf $file
	fi
	mv $folder $TERMUX_PKG_SRCDIR
}

termux_step_post_extract_package () {
        return
}

# Perform a host build. Will be called in $TERMUX_PKG_HOSTBUILD_DIR.
# After termux_step_post_extract_package() and before termux_step_patch_package()
termux_step_host_build () {
	$TERMUX_PKG_SRCDIR/configure ${TERMUX_PKG_EXTRA_HOSTBUILD_CONFIGURE_ARGS}
	make
}

# This should not be overridden
termux_step_patch_package () {
	cd $TERMUX_PKG_SRCDIR
	for patch in $TERMUX_PKG_BUILDER_DIR/*.patch; do
		test -f $patch && sed "s%\@TERMUX_PREFIX\@%${TERMUX_PREFIX}%g" $patch | patch -p1
	done

	find . -name config.sub -exec chmod u+w '{}' \; -exec cp $TERMUX_COMMON_CACHEDIR/config.sub '{}' \;
	find . -name config.guess -exec chmod u+w '{}' \; -exec cp $TERMUX_COMMON_CACHEDIR/config.guess '{}' \;
}

termux_step_pre_configure () {
        return
}

termux_step_configure () {
        if [ ! -e $TERMUX_PKG_SRCDIR/configure ]; then
                return
        fi

	DISABLE_STATIC="--disable-static"
	if [ "$TERMUX_PKG_EXTRA_CONFIGURE_ARGS" != "${TERMUX_PKG_EXTRA_CONFIGURE_ARGS/--enable-static/}" ]; then
		# Do not --disable-static if package explicitly enables it (e.g. gdb needs enable-static to build)
		DISABLE_STATIC=""
	fi

	DISABLE_NLS="--disable-nls"
	if [ "$TERMUX_PKG_EXTRA_CONFIGURE_ARGS" != "${TERMUX_PKG_EXTRA_CONFIGURE_ARGS/--enable-nls/}" ]; then
		# Do not --disable-nls if package explicitly enables it (for gettext itself)
		DISABLE_NLS=""
	fi

	ENABLE_SHARED="--enable-shared"
	if [ "$TERMUX_PKG_EXTRA_CONFIGURE_ARGS" != "${TERMUX_PKG_EXTRA_CONFIGURE_ARGS/--disable-shared/}" ]; then
		ENABLE_SHARED=""
	fi
	HOST_FLAG="--host=$TERMUX_HOST_PLATFORM"
	if [ "$TERMUX_PKG_EXTRA_CONFIGURE_ARGS" != "${TERMUX_PKG_EXTRA_CONFIGURE_ARGS/--host=/}" ]; then
		HOST_FLAG=""
	fi

	# Some packages provides a $PKG-config script which some configure scripts pickup instead of pkg-config:
	mkdir $TERMUX_PKG_TMPDIR/config-scripts
	for f in $TERMUX_PREFIX/bin/*config; do
		test -f $f && cp $f $TERMUX_PKG_TMPDIR/config-scripts
	done
	set +e +o pipefail
	find $TERMUX_PKG_TMPDIR/config-scripts | xargs file | grep -F " script" | cut -f 1 -d : | xargs sed -i -E "s@^#\!/system/bin/sh@#\!/bin/sh@"
	set -e -o pipefail
	export PATH=$TERMUX_PKG_TMPDIR/config-scripts:$PATH

	$TERMUX_PKG_SRCDIR/configure \
		--disable-dependency-tracking \
		--prefix=$TERMUX_PREFIX \
                --disable-rpath --disable-rpath-hack \
		$HOST_FLAG \
		$TERMUX_PKG_EXTRA_CONFIGURE_ARGS \
		$DISABLE_NLS \
		$ENABLE_SHARED \
		$DISABLE_STATIC \
		--libexecdir=$TERMUX_PREFIX/libexec
}

termux_step_post_configure () {
        return
}

termux_step_pre_make () {
        return
}

termux_step_make () {
        if ls *akefile &> /dev/null; then
                if [ -z "$TERMUX_PKG_EXTRA_MAKE_ARGS" ]; then
                        make -j $TERMUX_MAKE_PROCESSES
                else
                        make -j $TERMUX_MAKE_PROCESSES ${TERMUX_PKG_EXTRA_MAKE_ARGS}
                fi
        fi
}

termux_step_make_install () {
        if ls *akefile &> /dev/null; then
                : ${TERMUX_PKG_MAKE_INSTALL_TARGET:="install"}:
                # Some packages have problem with parallell install, and it does not buy much, so use -j 1.
                if [ -z "$TERMUX_PKG_EXTRA_MAKE_ARGS" ]; then
                        make -j 1 ${TERMUX_PKG_MAKE_INSTALL_TARGET}
                else
                        make -j 1 ${TERMUX_PKG_EXTRA_MAKE_ARGS} ${TERMUX_PKG_MAKE_INSTALL_TARGET}
                fi
        fi
}

termux_step_post_make_install () {
        return
}

termux_step_extract_into_massagedir () {
	TARBALL_ORIG=$TERMUX_PKG_PACKAGEDIR/${TERMUX_PKG_NAME}_orig.tar.gz

	# Build diff tar with what has changed during the build:
	cd $TERMUX_PREFIX
	$TERMUX_TAR -N $TERMUX_BUILD_TS_FILE -czf $TARBALL_ORIG .

	# Extract tar in order to massage it
	mkdir -p $TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX
	cd $TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX
	$TERMUX_TAR xf $TARBALL_ORIG
}

termux_step_massage () {
	cd $TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX

	# Remove lib/charset.alias which is installed by gettext-using packages:
	rm -f lib/charset.alias
	# Remove non-english man pages:
	test -d share/man && (cd share/man; for f in `ls | grep -v man`; do rm -Rf $f; done )
	# Remove info pages and other docs:
	rm -Rf share/info share/doc share/locale
	# Remove old kept libraries (readline):
	find . -name '*.old' -delete
	# .. remove static libraries:
	if [ $TERMUX_PKG_KEEP_STATIC_LIBRARIES = "false" ]; then
		find . -name '*.a' -delete
		find . -name '*.la' -delete
	fi

	# .. move over sbin to bin
	for file in sbin/*; do if test -f $file; then mv $file bin/; fi; done

	# file(1) may fail for certain unusual files, so disable pipefail
	set +e +o pipefail
        # Remove world permissions and add write permissions:
        find . -exec chmod u+w,o-rwx \{\} \;
	# .. strip binaries (setting them as writeable first)
	if [ "$TERMUX_DEBUG" = "" ]; then
                find . -type f | xargs file | grep -E "(executable|shared object)" | grep ELF | cut -f 1 -d : | xargs $STRIP --strip-unneeded --preserve-dates -R '.gnu.version*'
	fi
        # Remove DT_ entries which the android 5.1 linker warns about:
        find . -type f | xargs $TERMUX_ELF_CLEANER
        # Fix shebang paths:
        for file in `find . -type f`; do
                head -c 100 $file | grep -E "^#\!.*\\/bin\\/.*" | grep -q -E -v "^#\! ?\\/system" && sed --follow-symlinks -i -E "s@^#\!(.*)/bin/(.*)@#\!$TERMUX_PREFIX/bin/\2@" $file
        done
	set -e -o pipefail

	test ! -z "$TERMUX_PKG_RM_AFTER_INSTALL" && rm -Rf $TERMUX_PKG_RM_AFTER_INSTALL

	find . -type d -empty -delete # Remove empty directories

        # Sub packages:
        if [ -d include -a -z "${TERMUX_PKG_NO_DEVELSPLIT}" ]; then
                # Add virtual -dev sub package if there are include files:
                _DEVEL_SUBPACKAGE_FILE=$TERMUX_PKG_TMPDIR/${TERMUX_PKG_NAME}-dev.subpackage.sh
                echo TERMUX_SUBPKG_INCLUDE=\"include share/man/man3 lib/pkgconfig share/aclocal\" > $_DEVEL_SUBPACKAGE_FILE
                echo TERMUX_SUBPKG_DESCRIPTION=\"Development files for ${TERMUX_PKG_NAME}\" >> $_DEVEL_SUBPACKAGE_FILE
                echo TERMUX_SUBPKG_DEPENDS=\"$TERMUX_PKG_NAME\" >> $_DEVEL_SUBPACKAGE_FILE
        fi
        # Now build all sub packages
        rm -Rf $TERMUX_TOPDIR/$TERMUX_PKG_NAME/subpackages
	for subpackage in $TERMUX_PKG_BUILDER_DIR/*.subpackage.sh $TERMUX_PKG_TMPDIR/*subpackage.sh; do
                test ! -f $subpackage && continue
		SUB_PKG_NAME=`basename $subpackage .subpackage.sh`
                # Default value is same as main package, but sub package may override:
                TERMUX_SUBPKG_PLATFORM_INDEPENDENT=$TERMUX_PKG_PLATFORM_INDEPENDENT
		echo "$SUB_PKG_NAME => $subpackage"
                SUB_PKG_DIR=$TERMUX_TOPDIR/$TERMUX_PKG_NAME/subpackages/$SUB_PKG_NAME
                TERMUX_SUBPKG_DEPENDS=""
                SUB_PKG_MASSAGE_DIR=$SUB_PKG_DIR/massage/$TERMUX_PREFIX
		SUB_PKG_PACKAGE_DIR=$SUB_PKG_DIR/package
                mkdir -p $SUB_PKG_MASSAGE_DIR $SUB_PKG_PACKAGE_DIR

                . $subpackage

                for includeset in $TERMUX_SUBPKG_INCLUDE; do
                        _INCLUDE_DIRSET=`dirname $includeset`
                        test "$_INCLUDE_DIRSET" = "." && _INCLUDE_DIRSET=""
                        if [ -e $includeset ]; then
                                mkdir -p $SUB_PKG_MASSAGE_DIR/$_INCLUDE_DIRSET
                                mv $includeset $SUB_PKG_MASSAGE_DIR/$_INCLUDE_DIRSET
                        fi
                done

                SUB_PKG_ARCH=$TERMUX_ARCH
                test -n "$TERMUX_SUBPKG_PLATFORM_INDEPENDENT" && SUB_PKG_ARCH=all

                cd $SUB_PKG_DIR/massage
                SUB_PKG_INSTALLSIZE=`du -sk . | cut -f 1`
		$TERMUX_TAR --xz -cf $SUB_PKG_PACKAGE_DIR/data.tar.xz .

                mkdir -p DEBIAN
		cd DEBIAN
                cat > control <<HERE
Package: $SUB_PKG_NAME
Architecture: ${SUB_PKG_ARCH}
Installed-Size: ${SUB_PKG_INSTALLSIZE}
Maintainer: $TERMUX_PKG_MAINTAINER
Version: $TERMUX_PKG_FULLVERSION
Description: $TERMUX_SUBPKG_DESCRIPTION
Homepage: $TERMUX_PKG_HOMEPAGE
HERE
                test ! -z "$TERMUX_SUBPKG_DEPENDS" && echo "Depends: $TERMUX_SUBPKG_DEPENDS" >> control
		$TERMUX_TAR -czf $SUB_PKG_PACKAGE_DIR/control.tar.gz .

                # Create the actual .deb file:
                TERMUX_SUBPKG_DEBFILE=$TERMUX_COMMON_DEBDIR/${SUB_PKG_NAME}-${TERMUX_PKG_FULLVERSION}_${SUB_PKG_ARCH}.deb
		ar cr $TERMUX_SUBPKG_DEBFILE \
				   $TERMUX_COMMON_CACHEDIR/debian-binary \
				   $SUB_PKG_PACKAGE_DIR/control.tar.gz \
				   $SUB_PKG_PACKAGE_DIR/data.tar.xz
                if [ "$TERMUX_PROCESS_DEB" != "" ]; then
			$TERMUX_PROCESS_DEB $TERMUX_SUBPKG_DEBFILE
                fi

                # Go back to main package:
	        cd $TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX
	done

	# .. remove empty directories (NOTE: keep this last):
	find . -type d -empty -delete
        # Make sure user can read and write all files (problem with dpkg otherwise):
        chmod -R u+rw .
}

termux_step_post_massage () {
        return
}

termux_step_create_debscripts () {
        return
}

source $TERMUX_PKG_BUILDER_SCRIPT

# Compute full version:
TERMUX_PKG_FULLVERSION=$TERMUX_PKG_VERSION
if [ "$TERMUX_PKG_BUILD_REVISION" != "0" -o "$TERMUX_PKG_FULLVERSION" != "${TERMUX_PKG_FULLVERSION/-/}" ]; then
	# "0" is the default revision, so only include it if the upstream versions contains "-" itself
	TERMUX_PKG_FULLVERSION+="-$TERMUX_PKG_BUILD_REVISION"
fi

# Start by extracting the package src into $TERMUX_PKG_SRCURL:
termux_step_extract_package
# Optional post processing:
termux_step_post_extract_package

# Optional host build:
if [ "x$TERMUX_PKG_HOSTBUILD" != "x" ]; then
	cd $TERMUX_PKG_SRCDIR
	for patch in $TERMUX_PKG_BUILDER_DIR/*.patch.beforehostbuild; do
		test -f $patch && sed "s%\@TERMUX_PREFIX\@%${TERMUX_PREFIX}%g" $patch | patch -p1
	done

        if [ -f "$TERMUX_PKG_HOSTBUILD_DIR/TERMUX_BUILT_FOR_$TERMUX_PKG_VERSION" ]; then
                echo "Using already built host build"
        else
                mkdir -p $TERMUX_PKG_HOSTBUILD_DIR	
                cd $TERMUX_PKG_HOSTBUILD_DIR

                ORIG_AR=$AR; unset AR
                ORIG_AS=$AS; unset AS
                ORIG_CC=$CC; unset CC
                ORIG_CXX=$CXX; unset CXX
                ORIG_CPP=$CPP; unset CPP
                ORIG_CFLAGS=$CFLAGS; unset CFLAGS
                ORIG_CPPFLAGS=$CPPFLAGS; unset CPPFLAGS
                ORIG_CXXFLAGS=$CXXFLAGS; unset CXXFLAGS
                ORIG_LDFLAGS=$LDFLAGS; unset LDFLAGS
                ORIG_RANLIB=$RANLIB; unset RANLIB
                ORIG_LD=$LD; unset LD
                ORIG_PKG_CONFIG=$PKG_CONFIG; unset PKG_CONFIG
                ORIG_PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR; unset PKG_CONFIG_LIBDIR
                ORIG_STRIP=$STRIP; unset STRIP

                termux_step_host_build
                touch $TERMUX_PKG_HOSTBUILD_DIR/TERMUX_BUILT_FOR_$TERMUX_PKG_VERSION

                export AR=$ORIG_AR
                export AS=$ORIG_AS
                export CC=$ORIG_CC
                export CXX=$ORIG_CXX
                export CPP=$ORIG_CPP
                export CFLAGS=$ORIG_CFLAGS
                export CPPFLAGS=$ORIG_CPPFLAGS
                export CXXFLAGS=$ORIG_CXXFLAGS
                export LDFLAGS=$ORIG_LDFLAGS
                export RANLIB=$ORIG_RANLIB
                export LD=$ORIG_LD
                export PKG_CONFIG=$ORIG_PKG_CONFIG
                export PKG_CONFIG_LIBDIR=$ORIG_PKG_CONFIG_LIBDIR
                export STRIP=$ORIG_STRIP
        fi
fi

if [ "$TERMUX_PKG_DEPENDS" != "${TERMUX_PKG_DEPENDS/libandroid-support/}" ]; then
	# If using the android support library, link to it and include its headers as system headers:
	export CPPFLAGS="$CPPFLAGS -isystem $TERMUX_PREFIX/include/libandroid-support"
	export LDFLAGS="$LDFLAGS -landroid-support"
fi

if [ -n "$TERMUX_PKG_BUILD_IN_SRC" ]; then
	echo "Building in src due to TERMUX_PKG_BUILD_IN_SRC being set" >> $TERMUX_PKG_BUILDDIR/BUILDING_IN_SRC.txt
	TERMUX_PKG_BUILDDIR=$TERMUX_PKG_SRCDIR
fi

cd $TERMUX_PKG_BUILDDIR
termux_step_patch_package
cd $TERMUX_PKG_BUILDDIR
termux_step_pre_configure
cd $TERMUX_PKG_BUILDDIR
termux_step_configure
cd $TERMUX_PKG_BUILDDIR
termux_step_post_configure
cd $TERMUX_PKG_BUILDDIR
termux_step_pre_make
cd $TERMUX_PKG_BUILDDIR
termux_step_make
cd $TERMUX_PKG_BUILDDIR
termux_step_make_install
cd $TERMUX_PKG_BUILDDIR
termux_step_post_make_install
cd $TERMUX_PKG_MASSAGEDIR
termux_step_extract_into_massagedir
termux_step_massage
termux_step_post_massage

# Create data tarball containing files to package:
cd $TERMUX_PKG_MASSAGEDIR
if [ "`find . -type f`" = "" ]; then
        echo "ERROR: No files in package"
        exit 1
fi
$TERMUX_TAR --xz -cf $TERMUX_PKG_PACKAGEDIR/data.tar.xz .

# Get install size. This will be written as the "Installed-Size" deb field so is measured in 1024-byte blocks:
TERMUX_PKG_INSTALLSIZE=`du -sk . | cut -f 1`

# Create deb package:
# NOTE: From here on TERMUX_ARCH is set to "all" if TERMUX_PKG_PLATFORM_INDEPENDENT is set by the package
test -n "$TERMUX_PKG_PLATFORM_INDEPENDENT" && TERMUX_ARCH=all

cd $TERMUX_PKG_MASSAGEDIR

mkdir -p DEBIAN
cat > DEBIAN/control <<HERE
Package: $TERMUX_PKG_NAME
Architecture: ${TERMUX_ARCH}
Installed-Size: ${TERMUX_PKG_INSTALLSIZE}
Maintainer: $TERMUX_PKG_MAINTAINER
Version: $TERMUX_PKG_FULLVERSION
Description: $TERMUX_PKG_DESCRIPTION
Homepage: $TERMUX_PKG_HOMEPAGE
HERE
test ! -z "$TERMUX_PKG_DEPENDS" && echo "Depends: $TERMUX_PKG_DEPENDS" >> DEBIAN/control
test ! -z "$TERMUX_PKG_ESSENTIAL" && echo "Essential: yes" >> DEBIAN/control

# Create DEBIAN/conffiles (see https://www.debian.org/doc/debian-policy/ap-pkg-conffiles.html):
for f in $TERMUX_PKG_CONFFILES; do echo $TERMUX_PREFIX/$f >> DEBIAN/conffiles; done
# Allow packages to create arbitrary control files:
cd DEBIAN
termux_step_create_debscripts

# Create control.tar.gz
$TERMUX_TAR -czf $TERMUX_PKG_PACKAGEDIR/control.tar.gz .
# In the .deb ar file there should be a file "debian-binary" with "2.0" as the content:
TERMUX_PKG_DEBFILE=$TERMUX_COMMON_DEBDIR/${TERMUX_PKG_NAME}-${TERMUX_PKG_FULLVERSION}_${TERMUX_ARCH}.deb
# Create the actual .deb file:
ar cr $TERMUX_PKG_DEBFILE \
                   $TERMUX_COMMON_CACHEDIR/debian-binary \
                   $TERMUX_PKG_PACKAGEDIR/control.tar.gz \
                   $TERMUX_PKG_PACKAGEDIR/data.tar.xz

if [ "$TERMUX_PROCESS_DEB" != "" ]; then
	$TERMUX_PROCESS_DEB $TERMUX_PKG_DEBFILE
fi

echo "termux - build of '$1' done"
test -t 1 && printf "\033]0;$1 - DONE\007"
exit 0