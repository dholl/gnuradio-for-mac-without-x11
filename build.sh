#!/bin/sh
set -e
set -u

# Figure out where this script is located:
# If $0 starts with / then it is an absolute path.
# If not, then we'll prepend $PWD:
test -z "${0##/*}" && argv0_path="$0" || argv0_path="$PWD/$0"
#case "$0" in
#	/*)
#		# $0 is absolute path since it starts with /
#		argv0_path="$0"
#		;;
#	*)
#		# Assume $0 is relative path:
#		argv0_path="$PWD/$0"
#		;;
#esac
# Get directory where this script lives:
main_src_dir="${argv0_path%/*}"

app_dir="${1-"${PWD}/GNURadio.app"}"
case "${app_dir}" in
	/*)
		# ${app_dir} is already an absolute path since it starts with /
		#app_dir="${app_dir}"
		: # no-op
		;;
	*)
		# Assume ${app_dir} is relative path:
		app_dir="$PWD/${app_dir}"
		;;
esac

printf 'app_dir=%s\n' "${app_dir}"

tmp_dir="${app_dir}/tmp" # TODO: Delete "${app_dir}/tmp" before building .dmg

mkdir -p "${app_dir}" "${tmp_dir}"

if ! test -e "${tmp_dir}/.macports-base.installed" ; then
	if test -e "${tmp_dir}/macports-base.git" ; then
		git -C "${tmp_dir}/macports-base.git" fetch --all --progress -v
	else
		git clone https://github.com/macports/macports-base.git "${tmp_dir}/macports-base.git"
	fi

	# macports-base doesn't appear to support building out-of-tree
	# so we'll build in-tree instead:
	test -e "${tmp_dir}/macports-base" && rm -rf "${tmp_dir}/macports-base" || true
	git clone --depth=1 "${tmp_dir}/macports-base.git" "${tmp_dir}/macports-base"

	# make sure we're not going to blow away existing work!
	if test -e "${app_dir}/Contents" ; then
		printf 'Directory already exists: %s\n' "${app_dir}/Contents" 1>&2
		exit 1
	fi

	(
	cd "${tmp_dir}/macports-base"
	# I'm setting a few other paths according to https://lists.macports.org/pipermail/macports-users/2011-April/024234.html
	# Yeah, GNURadio.app/Contents/Applications is a pretty stupid location.  Will macports actually put anything in there?
	"${tmp_dir}/macports-base/configure" --enable-shared --with-unsupported-prefix --with-no-root-privileges \
		--prefix="${app_dir}/Contents/Resources" \
		--with-applications-dir="${app_dir}/Contents/Resources/Applications"
	# Must use --with-applications-dir=... or it'll put stuff in ${HOME}/Applications/MacPorts
	# Fix for volk: Don't use --with-frameworks-dir=...
	#	--with-frameworks-dir="${app_dir}/Contents/Frameworks"
	make -j"$(sysctl -n hw.ncpu)"
	make install
	)

	touch "${tmp_dir}/.macports-base.installed"

	# Save some space:
	rm -rf "${tmp_dir}/macports-base" "${tmp_dir}/macports-base.git"
fi

# Congratulations, you have successfully installed the MacPorts system. To get
# the Portfiles and update the system, add
# /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/tmp-install/bin
# to your PATH and run:
# sudo port -v selfupdate

# My idea: Naw, I won't mess up PATH for this, just to see if anything breaks.
#export PATH="${app_dir}/Contents/Resources/bin:$PATH"
# Instead, we'll define our own port function to only tweak PATH as needed:
port () {
	PATH="${app_dir}/Contents/Resources/bin:$PATH" "${app_dir}/Contents/Resources/bin/port" "$@"
}

port_clean() {
	if test "0" -eq "$(port echo requested | wc -l)" ; then
		cat << 'EOF' 1>&2
About to clean ports, but ...

Since there are no requested ports installed, this action will uninstall everything.
Are you really sure you want to do this?
I will sleep for 15 seconds to let you ponder about aborting this script.
EOF
		sleep 15
	fi
	printf 'Cleaning ports...\n'
	# Do some cleaning:
	need_more_cleaning=1
	until test "0" -eq "${need_more_cleaning}" ; do
		need_more_cleaning=0
		until test "0" -eq "$(port echo inactive | wc -l)" ; do
			need_more_cleaning=1
			printf 'Uninstalling inactive ports:\n'
			port echo inactive
			port uninstall inactive
		done
		until test "0" -eq "$(port echo leaves | wc -l)" ; do
			need_more_cleaning=1
			printf 'Uninstalling leaf ports:\n'
			port echo leaves
			port uninstall leaves
		done
	done
	unset -v need_more_cleaning
	# This takes a long time:  TODO: run clean --all all when we detect the script had been aborted.  (touch a .dirty file in tmp which we remove upon clean exit?)
	#port clean --all all
	port -q clean --all installed
	if test -d "${app_dir}/Contents/Resources/var/macports/build/" ; then
		rm -rf "${app_dir}/Contents/Resources/var/macports/build/"
		mkdir "${app_dir}/Contents/Resources/var/macports/build/"
	fi
	if test -d "${app_dir}/Contents/Resources/var/macports/distfiles/" ; then
		rm -rf "${app_dir}/Contents/Resources/var/macports/distfiles/"
		mkdir "${app_dir}/Contents/Resources/var/macports/distfiles/"
	fi
	if test -d "${app_dir}/Contents/Resources/var/macports/sources/rsync.macports.org/" ; then
		rm -rf "${app_dir}/Contents/Resources/var/macports/sources/rsync.macports.org/"
	fi
}

if ! test -e "${tmp_dir}/.macports.conf.installed" ; then
	(
	cd "${app_dir}/Contents/Resources"
	patch -p0 << 'EOF'
--- etc/macports/macports.conf.orig	2017-06-06 18:39:05.000000000 -0700
+++ etc/macports/macports.conf	2017-06-06 18:45:03.000000000 -0700
@@ -128,12 +128,14 @@
 # - none: Disable creation of StartupItems.
 # This setting only applies when building ports from source.
 #startupitem_type    	default
+startupitem_type none
 
 # Create system-level symlinks to generated StartupItems. If set to
 # "no", symlinks will not be created; otherwise, symlinks will be placed
 # in /Library/LaunchDaemons or /Library/LaunchAgents as appropriate.
 # This setting only applies when building ports from source.
 #startupitem_install	yes
+startupitem_install no
 
 # Extra environment variables to keep. MacPorts sanitizes its
 # environment while processing ports, keeping:
EOF
	)

	touch "${tmp_dir}/.macports.conf.installed"
fi

if ! test -e "${tmp_dir}/.macports.variants.installed" ; then
	# Use dbus's +no_startupitem variant -- according to https://lists.macports.org/pipermail/macports-users/2011-April/024235.html
	# plus a few others from http://gimp-app.sourceforge.net/BUILD.txt
	printf '\n%s\n' '-x11 +no_x11 +quartz +no_startupitem +no_root' >> "${app_dir}/Contents/Resources/etc/macports/variants.conf"
	# Not using +universal because:
	#	zero(ttys005):...ith-macports> "${app_dir}/Contents/Resources/bin/port" install gnuradio +universal
	#	--->  Computing dependencies for gnuradio
	#	Error: Cannot install gnuradio for the archs 'i386 x86_64' because
	#	Error: its dependency py27-scipy does not build for the required archs by default
	#	Error: and does not have a universal variant.
	#	Error: Follow https://guide.macports.org/#project.tickets to report a bug.
	#	Error: Processing of port gnuradio failed
	#	zsh: exit 1     "${app_dir}/Contents/Resources/bin/port" install gnuradio +universal
	# Using +no_root for dbus because: https://trac.macports.org/ticket/30071
	#	dbus failed during install, but re-running port install gnuradio seemed to move past dbus...?
	#	--->  Installing dbus @1.10.18_0
	#	Warning: addgroup only works when running as root.
	#	Warning: The requested group 'messagebus' was not created.
	#	Warning: adduser only works when running as root.
	#	Warning: The requested user 'messagebus' was not created.
	#	--->  Activating dbus @1.10.18_0
	#	Error: Failed to activate dbus: could not set group for file "/Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.app/Contents/Resources/var/run/dbus": group "messagebus" does not exist
	#	Error: See /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.app/Contents/Resources/var/macports/logs/_Users_dholl_Desktop_Installers_gnuradio-for-mac-with-macports_GNURadio.app_Contents_Resources_var_macports_sources_rsync.macports.org_macports_release_tarballs_ports_devel_dbus/dbus/main.log for details.
	#	Error: Follow https://guide.macports.org/#project.tickets to report a bug.
	#	Error: Processing of port gnuradio failed
	#	zsh: exit 1     ./notes.sh
	#	I'm retrying dbus with +no_root


	touch "${tmp_dir}/.macports.variants.installed"
fi

# GNURadio.app/Contents/Resources/var/macports/sources should already
# exist, but we want to create .../github.com-ports too:
if ! test -e "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" ; then
	printf 'Fetching ports tree over git...\n'
	test -e "${app_dir}/Contents/Resources/var/macports/sources" || mkdir -v "${app_dir}/Contents/Resources/var/macports/sources"
	if ! git clone https://github.com/dholl/macports-ports.git "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" ; then
		st=$?
		rm -rf "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports"
		printf 'git clone failed with status %s\n' "${st}" 1>&2
		exit 1
	fi
	# Delete .ports_rev_last to force portindex to run:
	test ! -e "${tmp_dir}/.ports_rev_last" || rm "${tmp_dir}/.ports_rev_last"
fi
if grep -q '^rsync' "${app_dir}/Contents/Resources/etc/macports/sources.conf" ; then
	printf 'Configuring sources.conf...\n'
	sed -i orig -e 's/^rsync/#&/' "${app_dir}/Contents/Resources/etc/macports/sources.conf"
	printf 'file://%s/ [default]\n' "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" >> "${app_dir}/Contents/Resources/etc/macports/sources.conf"
fi

# py27-gobject failes to compile due to https://trac.macports.org/ticket/53911
#
# Rather than wait for patches to py27-gobject, we'll just use a copy of
# the ports tree from just before the glib update, borrowing some tactics
# from https://trac.macports.org/wiki/howto/SyncingWithGit
#
# Make sure we're locked at a known-working ports tree:
#ports_rev_req="c745ea5ed18c735bf267c93f8cdcaaf9f247a121"
# Or leave ports_rev_req unset to update to the latest.
ports_branch="last-working-glib2-with-openjade-fix"
# TODO:
# detect if we're currently on ${ports_branch}.  (can I just always blindly check it out?)
# Then detect if ports_rev_req is within the history.  If not, then ask the user to put in the correct branch?

if test -n "${ports_rev_req-""}" ; then
	if test "$( git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" rev-parse HEAD )" != "${ports_rev_req-""}" ; then
		# Make sure that we're on ${ports_branch}:
		printf 'ports tree: git checkout %s ...\n' "${ports_branch}"
		git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" checkout "${ports_branch}"
		# And undo any local change to our local ${ports_branch} such as by a previous reset --hard...
		printf 'ports tree: git reset --hard origin/%s ...\n' "${ports_branch}"
		git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" reset --hard "origin/${ports_branch}"
		# Now check for upstream updates:
		printf 'ports tree: git pull ...\n'
		git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" pull
		# And lock to a specified revision: (This may shift ${ports_branch} into a branch if that's where ports_rev_req leads)
		printf 'ports tree: git reset --hard %s ...\n' "${ports_rev_req-""}"
		git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" reset --hard "${ports_rev_req-""}"
		# Clean cruft if possible:
		printf 'ports tree: git gc ...\n'
		git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" gc
		# Delete .ports_rev_last to force portindex to run:
		test ! -e "${tmp_dir}/.ports_rev_last" || rm "${tmp_dir}/.ports_rev_last"
		if test "$( git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" rev-parse HEAD )" != "${ports_rev_req-""}" ; then
			printf 'Failed to confirm ports tree at revision %s\n' "${ports_rev_req-""}" 1>&2
			exit 1
		fi
	fi
else
	# Undo any accidental mutilations from having previously run with fixed ports_rev_req
	# Make sure that we're on ${ports_branch}:
	printf 'ports tree: git checkout %s ...\n' "${ports_branch}"
	git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" checkout "${ports_branch}"
	# And undo any local change to our local ${ports_branch} such as by a previous reset --hard...
	printf 'ports tree: git reset --hard origin/%s ...\n' "${ports_branch}"
	git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" reset --hard "origin/${ports_branch}"
fi

# Run "port selfupdate" if we haven't done it in 20 hours, or if the current
# git revision of the ports tree has changed:
touch "${tmp_dir}/.current_time"
current_time="$(eval "$(stat -s "${tmp_dir}/.current_time")" ; printf '%s\n' "${st_mtime}")"
rm "${tmp_dir}/.current_time"
if test -e "${tmp_dir}/.ports_rev_last" ; then
	update_time="$(eval "$(stat -s "${tmp_dir}/.ports_rev_last")" ; printf '%s\n' "${st_mtime}")"
	ports_rev_last="$( cat "${tmp_dir}/.ports_rev_last" )"
else
	update_time=0
	ports_rev_last=''
fi
ports_rev_cur="$( git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" rev-parse HEAD )"
if test "$(( current_time-update_time > 20*60*60))" -eq "1" -o "x${ports_rev_cur}" != "x${ports_rev_last}"; then
	if test -n "${ports_rev_req-""}" ; then
		port selfupdate --nosync # Don't try to sync ports tree, since we're locking the git revision.
		# Don't run "port -v sync", because that would attempt to run "git pull --rebase --autostash".
		# Here, just update the local index:
		PATH="${app_dir}/Contents/Resources/bin:$PATH" "${app_dir}/Contents/Resources/bin/portindex" "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports"
	else
		port selfupdate
	fi
fi

ports_rev_cur="$( git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" rev-parse HEAD )"
# Check this _after_ "port selfupdate" stuff, to verify that the ports tree wasn't accidentally changed.
if test -n "${ports_rev_req-""}" -a "x${ports_rev_req-""}" != "x${ports_rev_cur}" ; then
	printf 'Failed sanity check.  Ports git revision "%s" does not match requested "%s".\n' "${ports_rev_cur}" "${ports_rev_req-""}" 1>&2
	exit 1
fi
if test "x${ports_rev_cur}" != "x${ports_rev_last}" ; then
	port -s -u upgrade outdated || true
	printf '%s\n' "${ports_rev_cur}" > "${tmp_dir}/.ports_rev_last"
fi
unset -v ports_rev_cur


# What ports do we want to install?
# libmirisdr ?
port_names="gnuradio hackrf bladeRF airspy rtl-sdr gr-osmosdr"

# What extra ports do we need for our packaging needs?
#	pkgconfig to assist with locating and fixing .pc files
#	py27-macholib for fixing library references
extra_port_names="pkgconfig py27-macholib"

# Now test which ports have not been installed yet:
printf 'Examining which ports need to be installed...\n'
port_names_to_install=""
for port_name in ${port_names} ${extra_port_names} ; do
	if test "$(port -q contents "${port_name}" | wc -l)" -eq "0" ; then
		port_names_to_install="${port_names_to_install-""}${port_names_to_install:+" "}${port_name}"
	fi
done
unset -v port_name
if test -n "${port_names_to_install}" ; then
	printf 'Installing ports: %s\n' "${port_names_to_install}"
	port -N -s install ${port_names_to_install}
else
	printf 'No new ports to install.\n'
fi
unset -v port_names_to_install
#py27-cairo has the following notes:
#	Make sure cairo is installed with the +x11 variant when installing the binary version of py27-cairo or install py27-cairo from source like so:
#		sudo port install -s py27-cairo

if ! test -f "${app_dir}/Contents/Resources/GNURadio.icns" ; then
	printf 'Looking for Inkscape.app in /Applications or %s/Applications, or for "inkscape" in $PATH...\n' "${HOME}"
	if test -x "${HOME}/Applications/Inkscape.app/Contents/Resources/script" ; then
		inkscape_bin="${HOME}/Applications/Inkscape.app/Contents/Resources/script"
	elif test -x "/Applications/Inkscape.app/Contents/Resources/script" ; then
		inkscape_bin="/Applications/Inkscape.app/Contents/Resources/script"
	elif command -v inkscape >/dev/null 2>&1 ; then
		# We found inkscape in the path.
		inkscape_bin="inkscape"
	else
		printf '\tUnable to find "inkscape" or "Inkscape.app/Contents/Resources/script"\n' 1>&2
		printf '\tWill skip icon generation\n'
		inkscape_bin=""
	fi
	if test -n "${inkscape_bin}" ; then
		printf '\tTesting Inkscape at %s...\n' "${inkscape_bin}"
		"${inkscape_bin}" --without-gui --verb-list >/dev/null 2>&1 && st="$?" || st="$?"
		if test 0 -ne "${st}" ; then
			printf '\tFailed test: Found nonzero exit status of %s from running %s --without-gui --verb-list\n' "${st}" "${inkscape_bin}" 1>&2
			printf '\tWill skip icon generation\n'
			inkscape_bin=""
		fi
	fi

	if test -n "${inkscape_bin}" ; then
		printf 'Generating GNURadio.icns...\n'
		if ! test -f "${tmp_dir}/gnuradio_logo_icon-square.svg" ; then
			printf '\tDownloading SVG artwork...\n'
			#git clone https://github.com/gnuradio/gr-logo.git "${tmp_dir}/gr-logo.git"
			#cp -a "${tmp_dir}/gr-logo.git/gnuradio_logo_icon-square.svg" "${tmp_dir}/gnuradio_logo_icon-square.svg"
			#rm -rf "${tmp_dir}/gr-logo.git"
			# Or should I just download https://github.com/gnuradio/gr-logo/raw/master/gnuradio_logo_icon-square.svg ?
			curl --location -o "${tmp_dir}/gnuradio_logo_icon-square.svg" "https://github.com/gnuradio/gr-logo/raw/master/gnuradio_logo_icon-square.svg"
		fi
		#ln -s /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns
		#iconutil --convert iconset GenericDocumentIcon.icns
		#rm GenericDocumentIcon.icns
		#file GenericDocumentIcon.iconset/*
		#	GenericDocumentIcon.iconset/icon_16x16.png:      PNG image data, 16 x 16, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_16x16@2x.png:   PNG image data, 32 x 32, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_32x32.png:      PNG image data, 32 x 32, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_32x32@2x.png:   PNG image data, 64 x 64, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_128x128.png:    PNG image data, 128 x 128, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_128x128@2x.png: PNG image data, 256 x 256, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_256x256.png:    PNG image data, 256 x 256, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_256x256@2x.png: PNG image data, 512 x 512, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_512x512.png:    PNG image data, 512 x 512, 8-bit/color RGBA, non-interlaced
		#	GenericDocumentIcon.iconset/icon_512x512@2x.png: PNG image data, 1024 x 1024, 8-bit/color RGBA, non-interlaced
		#I opened each png in Preview and found they all had the same resolution of 72 DPI.

		if test -e "${tmp_dir}/GNURadio.iconset" ; then
			rm -rf "${tmp_dir}/GNURadio.iconset"
		fi
		mkdir "${tmp_dir}/GNURadio.iconset"
		# From https://developer.apple.com/library/content/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html#//apple_ref/doc/uid/TP40012302-CH7-SW2
		for px in 16 32 128 256 512 ; do
			printf '\tGenerating icon %sx%s...\n' "${px}" "${px}"
			"${inkscape_bin}" --without-gui --file="${tmp_dir}/gnuradio_logo_icon-square.svg" --export-area-page --export-width="${px}" --export-height="${px}" --export-png="${tmp_dir}/GNURadio.iconset/icon_${px}x${px}.png" >/dev/null
			px2x=$((2*px))
			printf '\tGenerating icon %sx%s@2x...\n' "${px}" "${px}"
			"${inkscape_bin}" --without-gui --file="${tmp_dir}/gnuradio_logo_icon-square.svg" --export-area-page --export-width="${px2x}" --export-height="${px2x}" --export-png="${tmp_dir}/GNURadio.iconset/icon_${px}x${px}@2x.png" >/dev/null
		done
		unset -v px px2x
		printf '\tMerging icons...\n'
		iconutil --convert icns -o "${app_dir}/Contents/Resources/GNURadio.icns" "${tmp_dir}/GNURadio.iconset"
		rm -r "${tmp_dir}/GNURadio.iconset"
	fi
	unset -v inkscape_bin
fi

mkdir -p "${app_dir}/bin/._gnuradio"
cat << 'EOF' > "${app_dir}/bin/._gnuradio/ln_helper"
#!/bin/sh
set -e
set -u

# Figure out where this script is located: (relative to ${app_dir}/bin and NOT ${app_dir}/bin/._gnuradio )
test -z "${0##/*}" && argv0_path="$0" || argv0_path="$PWD/$0"
script_dir="${argv0_path%/*}"

bundle="${script_dir}/.."

exec "${script_dir}/._gnuradio/run_env" "${bundle}" "${bundle}/Contents/Resources/bin/${0##*/}" "$@"
EOF
chmod 755 "${app_dir}/bin/._gnuradio/ln_helper"
cat << 'EOFQ' > "${app_dir}/bin/._gnuradio/run_env"
#!/bin/sh
set -e
set -u

bundle="${1}"
shift
exe_file="${1}"
shift

export PATH="${bundle}/Contents/Resources/bin:${PATH}"

# D.Holl - I following GIMP.app as a guide, but deviated often at my discretion as I read through the docs of each underlying library:
# Specify installed prefix AND exec_prefix
export PYTHONHOME="${bundle}/Contents/Resources/Library/Frameworks/Python.framework/Versions/2.7:${bundle}/Contents/Resources/Library/Frameworks/Python.framework/Versions/2.7"
# TODO: Confirm if I really need PYTHONHOME
# Doesn't work: export DYLD_LIBRARY_PATH="${bundle}/Contents/Resources/lib"
export XDG_CONFIG_DIRS="${bundle}/Contents/Resources/etc/xdg"
# export XDG_CONFIG_HOME="${bundle}/Contents/Resources/share" # D.Holl TODO is this right?  Needed according to https://www.freedesktop.org/software/fontconfig/fontconfig-user.html
export XDG_DATA_DIRS="${bundle}/Contents/Resources/share" # D.Holl TODO: If I have this, then I don't need XDG_CONFIG_HOME, right?
# TODO: Compare XDG_* with guidelines from https://developer.apple.com/library/content/documentation/General/Conceptual/MOSXAppProgrammingGuide/AppRuntime/AppRuntime.html
# Specifically:
#	File-System Usage Requirements for the Mac App Store
#		...
#		Your application must adhere to the following requirements:
#			...
#			* Your application may write to the following directories:
#				~/Library/Application Support/<app-identifier>
#				~/Library/<app-identifier>
#				~/Library/Caches/<app-identifier>
#			  where <app-identifier> is your application's bundle identifier, its name, or your company’s name. This must exactly match what is in iTunes Connect for the application.
#			  Always use Apple programming interfaces such as the URLsForDirectory:inDomains: function to locate these paths rather than hardcoding them. For more information, see File System Programming Guide.
#			...

# GTK_* vars described at: https://developer.gnome.org/gtk2/stable/gtk-running.html
export GTK_DATA_PREFIX="${bundle}/Contents/Resources" # D.Holl vetted from https://developer.gnome.org/gtk2/stable/gtk-running.html
export GTK_EXE_PREFIX="${bundle}/Contents/Resources" # D.Holl vetted from https://developer.gnome.org/gtk2/stable/gtk-running.html
unset -v GTK_PATH # D.Holl best guess since GTK_EXE_PREFIX controls system default search path.  GIMP uses "${bundle}/Contents/Resources"
unset -v GTK2_MODULES # D.Holl best guess.
unset -v GTK_MODULES # D.Holl best guess.
unset -v GTK_IM_MODULE # D.Holl best guess.

# Set up generic configuration
export GTK2_RC_FILES="${bundle}/Contents/Resources/share/themes/Mac/gtk-2.0-key/gtkrc" # D.Holl - I took a guess at this.  But GIMP uses: ".../Contents/Resources/etc/gtk-2.0/gtkrc"
export GTK_IM_MODULE_FILE="${bundle}/Contents/Resources/etc/gtk-2.0/gtk.immodules"
export GDK_PIXBUF_MODULE_FILE="${bundle}/Contents/Resources/etc/gtk-2.0/gdk-pixbuf.loaders"
export GDK_PIXBUF_MODULEDIR="${bundle}/Contents/Resources/lib/gdk-pixbuf-2.0/2.10.0/loaders"

# TODO Verify XDG_DATA_HOME and XDG_DATA_DIRS as needed by https://developer.gnome.org/gtk2/stable/gtk-running.html

# D.Holl unused for GNURadio? export PANGO_RC_FILE="${bundle}/Contents/Resources/etc/pango/pangorc"
export PANGO_SYSCONFDIR="${bundle}/Contents/Resources/etc" # D.Holl best guess
export PANGO_LIBDIR="${bundle}/Contents/Resources/lib" # D.Holl best guess

# Specify Fontconfig configuration file
##export FONTCONFIG_FILE="${bundle}/Contents/Resources/etc/fonts/fonts.conf" # D.Holl vetted.  :)
FONTCONFIG_FILE="$(mktemp -t ".gnuradio-fontconfig-$(id -u)-" 2>/dev/null)" && st="$?" || st="$?"
if test 0 -ne "${st}" ; then
	printf 'mktemp exited with nonzero status %s\n' "${st}" 1>&2
	exit 1
fi
unset -v st
if ! test -f "${FONTCONFIG_FILE}" ; then
	printf 'mktemp failed to create temporary file\n' 1>&2
	exit 1
fi
cat << EOF > "${FONTCONFIG_FILE}"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- Write out the current PID so we have a way to detect stale temp files:
gnuradio_fontconfig_pid=$$
-->
<!-- /etc/fonts/fonts.conf file to configure system font access -->
<fontconfig>
<!-- Adding ~/Library/Fonts before any other <dir> specification: -->
<dir>~/Library/Fonts</dir>
<!-- Now include our bundle's fonts: -->
<dir>${bundle}/Contents/Resources/share/fonts</dir>
<!-- Now include the rest of the default config: -->
<include>${bundle}/Contents/Resources/etc/fonts/fonts.conf</include>
</fontconfig>
EOF
export FONTCONFIG_FILE
for tmpfile in "${FONTCONFIG_FILE%/*}/.gnuradio-fontconfig-$(id -u)-"* ; do
	if test -e "${tmpfile}" ; then
		tmpfile_pid="$(grep '^gnuradio_fontconfig_pid=[0-9]*$' "${tmpfile}")" && st="$?" || st="$?"
		# Strip off the leading "gnuradio_fontconfig_pid="
		tmpfile_pid="${tmpfile_pid#gnuradio_fontconfig_pid=}"
		if test 0 -ne "${st}" ; then
			printf 'Could not find pid from temporary fontconfig file: %s\n' "${tmpfile}" 1>&2
		else
			if ! kill -0 "${tmpfile_pid}" >/dev/null 2>&1 ; then
				# kill -0 tests if a pid exists.
				# If a pid doesn't exist, then we remove this tmpfile:
				#printf 'Removing stale temporary fontconfig file: %s\n' "${tmpfile}" 1>&2
				rm -f "${tmpfile}"
			fi
		fi
		unset -v tmpfile_pid
	fi
done
unset -v tmpfile
export FONTCONFIG_PATH="${bundle}/Contents/Resources/etc/fonts" # D.Holl best guess.
export FC_DEBUG=1024 # D.Holl - Verify that fontconfig is looking in the right places, and then remove this.

# Include GEGL path
# D.Holl unused for GNURadio? export GEGL_PATH="${bundle}/Contents/Resources/lib/gegl-0.2"

# Include BABL path
# D.Holl unused for GNURadio? export BABL_PATH="${bundle}/Contents/Resources/lib/babl-0.1"

#unset -v PYTHONPATH # D.Holl best guess.  Do I need to set this if I set PYTHONHOME
# TODO Get rid of PYTHONPATH if relocation works without it.  We don't want to unset it if the user specifically set it...

# Set custom Poppler Data Directory
# D.Holl unused for GNURadio? export POPPLER_DATADIR="${bundle}/Contents/Resources/share/poppler"

# Specify Ghostscript directories
# export GS_RESOURCE_DIR="${bundle}/Contents/Resources/share/ghostscript/9.06/Resource"
# export GS_ICC_PROFILES="${bundle}/Contents/Resources/share/ghostscript/9.06/iccprofiles/"
# export GS_LIB="$GS_RESOURCE_DIR/Init:$GS_RESOURCE_DIR:$GS_RESOURCE_DIR/Font:${bundle}/Contents/Resources/share/ghostscript/fonts:${bundle}/Contents/Resources/share/fonts/urw-fonts:$GS_ICC_PROFILES"
# export GS_FONTPATH="${bundle}/Contents/Resources/share/ghostscript/fonts:${bundle}/Contents/Resources/share/fonts/urw-fonts:~/Library/Fonts:/Library/Fonts:/System/Library/Fonts"

# set up character encoding aliases
if test -f "${bundle}/Contents/Resources/lib/charset.alias"; then
	export CHARSETALIASDIR="${bundle}/Contents/Resources/lib"
fi

exec "${exe_file}" "$@"
EOFQ
chmod 755 "${app_dir}/bin/._gnuradio/run_env"

(
cd "${app_dir}/bin"
printf 'Removing symlinks:'
for bin_name in * ; do
	if test -L "${bin_name}" && test "._gnuradio/ln_helper" -ef "${bin_name}" ; then
		# Clean out all symlinks:
		printf ' %s' "${bin_name}"
		rm "${bin_name}"
	fi
done
printf '\n'
)
printf 'Creating symlinks:'
for bin_name in $(port -q contents ${port_names} | sed -e 's_^[[:space:]]*__' | awk -v tgt="${app_dir}/Contents/Resources/bin/" '{if (index($0, tgt)==1) {b=substr($0, length(tgt)+1); if (match(b, "[/[[:space:]]]")==0) print b}}') ; do
	if test -x "${app_dir}/Contents/Resources/bin/${bin_name}" ; then
		if test -e "${app_dir}/bin/${bin_name}" ; then
			printf '\nWARNING: Skipping symlink for %s because a file already exists...\n' "${bin_name}" 1>&2
		else
			printf ' %s' "${bin_name}"
			ln -s ._gnuradio/ln_helper "${app_dir}/bin/${bin_name}"
		fi
	fi
done
printf '\n'
unset -v bin_name

# Minimize how much junk that the fix_* scripts will sift through.
port_clean

# Now perform my own fix_* cleaning:

# Edit fonts.conf to replace hard-coded path to bundle.  See https://www.freedesktop.org/software/fontconfig/fontconfig-user.html
#	Fix this so it is no longer hard-coded:  Can I make it relative to FONTCONFIG_PATH which is ${app_dir}/Contents/Resources/etc/fonts ?  https://www.freedesktop.org/software/fontconfig/fontconfig-devel/fcconfigfilename.html
#	Remove this from Contents/Resources/etc/fonts/fonts.conf:
# Create temp file with same perms as orig file:
printf 'Removing hard-coded bundle paths from %s\n' "${app_dir}/Contents/Resources/etc/fonts/fonts.conf"
cp -a "${app_dir}/Contents/Resources/etc/fonts/fonts.conf" "${app_dir}/Contents/Resources/etc/fonts/fonts.conf.tmp"
# Now we can put fixed-up paths into this new fonts.conf before including the main fonts.conf:
# TODO: quote ${app_dir} in case it has any special regex chars?
sed \
	-e "s|[[:space:]]*<dir>${app_dir}/Contents/Resources/share/fonts</dir>||g" \
	-e "s|[[:space:]]*<cachedir>/Applications/GNURadio.app/Contents/Resources/var/cache/fontconfig</cachedir>||g" \
	-e "s|[[:space:]]*<dir>/Network/Library/Fonts</dir>||g" \
	< "${app_dir}/Contents/Resources/etc/fonts/fonts.conf" \
	> "${app_dir}/Contents/Resources/etc/fonts/fonts.conf.tmp"
mv "${app_dir}/Contents/Resources/etc/fonts/fonts.conf.tmp" "${app_dir}/Contents/Resources/etc/fonts/fonts.conf"
if test -e "${app_dir}/Contents/Resources/var/cache/fontconfig" ; then
	# We're not keeping a writable cache directory within the bundle:
	rm -r "${app_dir}/Contents/Resources/var/cache/fontconfig"
fi

# Replace "${app_dir}/Contents/Resources/lib/gtk-2.0/2.10.0/immodules.cache" with symlink to "${app_dir}/Contents/Resources/etc/gtk-2.0/gtk.immodules"
if test -L "${app_dir}/Contents/Resources/etc/gtk-2.0/gtk.immodules" ; then
	# For paranoia, make sure we're about to point a symbolic link to a regular file to avoid pointing to a symlink that points back circularly:
	printf '%s is a symbolic link!\n' 1>&2
	exit 1
fi
if test -e "${app_dir}/Contents/Resources/lib/gtk-2.0/2.10.0/immodules.cache" ; then
	if ! test "${app_dir}/Contents/Resources/lib/gtk-2.0/2.10.0/immodules.cache" -ef "${app_dir}/Contents/Resources/etc/gtk-2.0/gtk.immodules" ; then
		rm "${app_dir}/Contents/Resources/lib/gtk-2.0/2.10.0/immodules.cache"
		ln -s "../../../etc/gtk-2.0/gtk.immodules" "${app_dir}/Contents/Resources/lib/gtk-2.0/2.10.0/immodules.cache"
	fi
else
	ln -s "../../../etc/gtk-2.0/gtk.immodules" "${app_dir}/Contents/Resources/lib/gtk-2.0/2.10.0/immodules.cache"
fi
# Replace "${app_dir}/Contents/Resources/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" with symlink to "${app_dir}/Contents/Resources/etc/gtk-2.0/gdk-pixbuf.loaders"
if test -L "${app_dir}/Contents/Resources/etc/gtk-2.0/gdk-pixbuf.loaders" ; then
	# For paranoia, make sure we're about to point a symbolic link to a regular file to avoid pointing to a symlink that points back circularly:
	printf '%s is a symbolic link!\n' 1>&2
	exit 1
fi
if test -e "${app_dir}/Contents/Resources/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" ; then
	if ! test "${app_dir}/Contents/Resources/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" -ef "${app_dir}/Contents/Resources/etc/gtk-2.0/gdk-pixbuf.loaders" ; then
		rm "${app_dir}/Contents/Resources/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
		ln -s "../../../etc/gtk-2.0/gdk-pixbuf.loaders" "${app_dir}/Contents/Resources/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
	fi
else
	ln -s "../../../etc/gtk-2.0/gdk-pixbuf.loaders" "${app_dir}/Contents/Resources/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
fi

# TODO: Make files relocatable:
#	"${app_dir}/Contents/Resources/etc/gtk-2.0/gtk.immodules"
#	"${app_dir}/Contents/Resources/etc/gtk-2.0/gdk-pixbuf.loaders"


# For this execution of fix_pkg_config, use env to ensure we don't accidentally
# get any packages outside of the defaults included in the pkg-config we just
# built:
printf 'Making pkg-config (.pc) files relocatable...\n'
env -u PKG_CONFIG_PATH -u PKG_CONFIG_LIBDIR \
	"${main_src_dir}/fix_pkg_config" "${app_dir}/Contents" "${app_dir}/Contents/Resources/bin/pkg-config"

# TODO:
# "${main_src_dir}/fix_library_references" "${app_dir}/Contents"

# TODO:
# "${main_src_dir}/fix_script_references" "${app_dir}/Contents"
#zero(ttys000):...-without-x11> find /Applications/GNURadio.app -type f -perm +0111 -print0 | xargs -0 grep '^#!/Appl' | cut -d: -f2- | sort | uniq -c
#  42 #!/Applications/GNURadio.app/Contents/Resources/Library/Frameworks/Python.framework/Versions/2.7/Resources/Python.app/Contents/MacOS/Python
# 174 #!/Applications/GNURadio.app/Contents/Resources/Library/Frameworks/Python.framework/Versions/2.7/bin/python2.7
#  31 #!/Applications/GNURadio.app/Contents/Resources/bin/perl5.24
#   3 #!/Applications/GNURadio.app/Contents/Resources/bin/python2.7
#   3 #!/Applications/GNURadio.app/Contents/Resources/libexec/macports/bin/tclsh8.5

#if test -n "${extra_port_names}" ; then
#	# We don't need this any more:
#	port unsetrequested ${extra_port_names}
#	port_clean
#fi

printf 'Making symbolic links relocatable...\n'
"${main_src_dir}/fix_symbolic_links" "${app_dir}/Contents"

# This can make pretty dependency trees:
#   https://github.com/Synss/macports_deptree

printf 'Testing installation...\n'
test_failed=0

# Test GDK_ environment variables:
"${app_dir}/bin/._gnuradio/run_env" "${app_dir}/bin/.." "${app_dir}/bin/../Contents/Resources/bin/gdk-pixbuf-query-loaders" > /dev/null 2>&1 && st="$?" || st="$?"
# superfluous bin/.. added to emulate ln_helper
if test 0 -ne "${st}" ; then
	printf 'Test command failed: gdk-pixbuf-query-loaders\n\tExit status: %s\n\tOutput:\n' "${st}" 1>&2
	"${app_dir}/bin/._gnuradio/run_env" "${app_dir}/bin/.." "${app_dir}/bin/../Contents/Resources/bin/gdk-pixbuf-query-loaders" 1>&2 || true
	test_failed=1
fi

# Test GTK_ environment variables:
"${app_dir}/bin/._gnuradio/run_env" "${app_dir}/bin/.." "${app_dir}/bin/../Contents/Resources/bin/gtk-query-immodules-2.0" > /dev/null 2>&1 && st="$?" || st="$?"
# superfluous bin/.. added to emulate ln_helper
if test 0 -ne "${st}" ; then
	printf 'Test command failed: gtk-query-immodules-2.0\n\tExit status: %s\n\tOutput:\n' "${st}" 1>&2
	"${app_dir}/bin/._gnuradio/run_env" "${app_dir}/bin/.." "${app_dir}/bin/../Contents/Resources/bin/gtk-query-immodules-2.0" 1>&2 || true
	test_failed=1
fi

# Test fontconfig:
"${app_dir}/bin/._gnuradio/run_env" "${app_dir}/bin/.." "${app_dir}/bin/../Contents/Resources/bin/fc-list" > /dev/null 2>&1 && st="$?" || st="$?"
# superfluous bin/.. added to emulate ln_helper
if test 0 -ne "${st}" ; then
	printf 'Test command failed: fc-list\n\tExit status: %s\n\tOutput:\n' "${st}" 1>&2
	"${app_dir}/bin/._gnuradio/run_env" "${app_dir}/bin/.." "${app_dir}/bin/../Contents/Resources/bin/fc-list" 1>&2 || true
	test_failed=1
fi

# Inspired by http://aaronscher.com/wireless_com_SDR/MacOSX_install_gnu_radio.html
#   Check to see if gnuradio installed correctly by typing the following in the Terminal:
#     gnuradio-config-info --version
#   This should display the version of GNU Radio.
test_cmd="${app_dir}/bin/gnuradio-config-info"
for test_arg in --prefix --sysconfdir --prefsdir --userprefsdir --prefs --builddate --enabled-components --cc --cxx --cflags --version ; do
	"${test_cmd}" ${test_arg} > /dev/null 2>&1 && st="$?" || st="$?"
	if test 0 -ne "${st}" ; then
		printf 'Test command failed: %s%s\n\tExit status: %s\n\tOutput:\n' "${test_cmd}" " ${test_arg}" "${st}" 1>&2
		"${test_cmd}" ${test_arg} 1>&2 || true
		test_failed=1
	fi
done
unset -v test_cmd test_arg

if test 0 -ne "${test_failed}" ; then
	exit 1
fi
unset -v test_failed
