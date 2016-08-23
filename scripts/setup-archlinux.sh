#!/bin/sh

PACKAGES=""
PACKAGES="$PACKAGES asciidoc"
PACKAGES="$PACKAGES automake"
PACKAGES="$PACKAGES bison"
PACKAGES="$PACKAGES cmake"
PACKAGES="$PACKAGES curl"			    # Used for fetching sources.
PACKAGES="$PACKAGES flex"
PACKAGES="$PACKAGES gettext"			# Provides 'msgfmt' which the apt build uses.
PACKAGES="$PACKAGES git"			    # Used by the neovim build.
PACKAGES="$PACKAGES help2man"
PACKAGES="$PACKAGES lib32-glibc"	# Needed by luajit host part of the build for <sys/cdefs.h>.
PACKAGES="$PACKAGES curl"	    # XXX: Needed by apt build.
PACKAGES="$PACKAGES gdk-pixbuf2"	# Provides 'gkd-pixbuf-query-loaders' which the librsvg build uses.
PACKAGES="$PACKAGES glib2"		# Provides 'glib-genmarshal' which the glib build uses.
PACKAGES="$PACKAGES ncurses"
PACKAGES="$PACKAGES libtool"
PACKAGES="$PACKAGES lzip"
PACKAGES="$PACKAGES subversion"			# Used by the netpbm build.
PACKAGES="$PACKAGES tar"
PACKAGES="$PACKAGES unzip"
PACKAGES="$PACKAGES m4"
PACKAGES="$PACKAGES jdk8-openjdk"	# Used for android-sdk.
PACKAGES="$PACKAGES pkgconfig"
PACKAGES="$PACKAGES scons"
PACKAGES="$PACKAGES texinfo"
PACKAGES="$PACKAGES xmlto"
PACKAGES="$PACKAGES imake"	            # Provides 'makedepend' which the openssl build uses.
NEEDED=$(pacman -T $PACKAGES)       # test whether dependency is satisfied and return only needed packages
[[ ! -z "$NEEDED" ]] && sudo pacman -S $NEEDED

sudo mkdir -p /data/data/com.termux/files/usr
sudo chown -R `whoami` /data
