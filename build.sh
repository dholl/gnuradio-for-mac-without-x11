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

# openjade WORK AROUND this bug:
#--->  Building openjade
#Error: Failed to build openjade: command execution failed
#Error: See /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.app/Contents/Resources/var/macports/logs/_Users_dholl_Desktop_Installers_gnuradio-for-mac-with-macports_GNURadio.app_Contents_Resources_var_macports_sources_rsync.macports.org_macports_release_tarballs_ports_textproc_openjade/openjade/main.log for details.
#Error: Follow https://guide.macports.org/#project.tickets to report a bug.
#Error: Processing of port gnuradio failed
#:info:build make[2]: *** No rule to make target `/Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.lapp/Contents/Resources/lib/libosp.dylib', needed by `openjade'.  Stop.
# Note how the :info: message above mentions .../GNURadio.lapp/...  I speculate
# that something during openjade's build is trying to replace .a with .la such
# as for static library stuff.  The downside is this turns our GNURadio.app
# into GNURadio.lapp.  So here, we'll patch it with a symlink:
lapp_dir="$(printf '%s\n' "${app_dir}" | sed -e 's/\.a/\.la/g' && printf 'x\n')"
lapp_dir="${lapp_dir%??}"
if test -L "${lapp_dir}" ; then
	if test "${app_dir}" -ef "${lapp_dir}" ; then
		printf 'openjade WORK AROUND: Using existing symbolic link %s\n' "${lapp_dir}"
		# Clearing lapp_dir will prevent us from trying to delete it later, in
		# case the target directory such as /Applications is not normally
		# writable by the user, and they only temporarilly used sudo or "su -
		# admin" to manually create the link for us.
		lapp_dir=''
	else
		printf 'openjade WORK AROUND: Removing old symbolic link %s\n' "${lapp_dir}"
		rm "${lapp_dir}"
		printf 'openjade WORK AROUND: Creating symbolic link %s\n' "${lapp_dir}"
		if ! ln -s "${app_dir}" "${lapp_dir}" ; then
			printf 'openjade WORK AROUND: Failed to create symbolic link %s\nPlease use an account with sufficient privileges to execute:\n\tln -s "%s" "%s"\n' "${app_dir}" "${lapp_dir}" 1>&2
			exit 1
		fi
	fi
else
	printf 'openjade WORK AROUND: Creating symbolic link %s\n' "${lapp_dir}"
	ln -s "${app_dir}" "${lapp_dir}"
fi
# END OF openjade WORK AROUND

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
	if ! git clone https://github.com/macports/macports-ports.git "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" ; then
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
ports_rev_req="ff6ce7fa929ede0751f8dfc08e1c7da937c7956e"
# Or leave ports_rev_req unset to update to the latest.

if test -n "${ports_rev_req-""}" ; then
	if test "$( git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" rev-parse HEAD )" != "${ports_rev_req-""}" ; then
		printf 'ports tree: git pull ...\n'
		git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" pull
		printf 'ports tree: git reset --hard %s ...\n' "${ports_rev_req-""}"
		git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" reset --hard "${ports_rev_req-""}"
		printf 'ports tree: git gc ...\n'
		git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" gc
		# Delete .ports_rev_last to force portindex to run:
		test ! -e "${tmp_dir}/.ports_rev_last" || rm "${tmp_dir}/.ports_rev_last"
		if test "$( git -C "${app_dir}/Contents/Resources/var/macports/sources/github.com-ports" rev-parse HEAD )" != "${ports_rev_req-""}" ; then
			printf 'Failed to confirm ports tree at revision %s\n' "${ports_rev_req-""}" 1>&2
			exit 1
		fi
	fi
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
extra_port_names="pkgconfig"

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

# openjade WORK AROUND
if test -n "${lapp_dir}" ; then
	printf 'openjade WORK AROUND: Removing symbolic link %s\n' "${lapp_dir}"
	rm "${lapp_dir}"
fi
# END OF openjade WORK AROUND

# Minimize how much junk that the fix_* scripts will sift through.
port_clean

# Now perform my own fix_* cleaning:

# For this execution of fix_pkg_config, use env to ensure we don't accidentally
# get any packages outside of the defaults included in the pkg-config we just
# built:
printf 'Making pkg-config (.pc) files relocatable...\n'
env -u PKG_CONFIG_PATH -u PKG_CONFIG_LIBDIR \
	"${main_src_dir}/fix_pkg_config" "${app_dir}/Contents" "${app_dir}/Contents/Resources/bin/pkg-config"

# TODO:
# "${main_src_dir}/fix_library_references" "${app_dir}/Contents"

if test -n "${extra_port_names}" ; then
	# We don't need this any more:
	port unsetrequested ${extra_port_names}
	port_clean
fi

printf 'Making symbolic links relocatable...\n'
"${main_src_dir}/fix_symbolic_links" "${app_dir}/Contents"

# This can make pretty dependency trees:
#   https://github.com/Synss/macports_deptree

# From http://aaronscher.com/wireless_com_SDR/MacOSX_install_gnu_radio.html
#   Check to see if gnuradio installed correctly by typing the following in the Terminal:
#     gnuradio-config-info --version
#   This should display the version of GNU Radio.


# 2017-06-07 - Where I left off:
#	--->  Some of the ports you installed have notes:
#	  coreutils has the following notes:
#	    The tools provided by GNU coreutils are prefixed with the character 'g' by default to distinguish them from the BSD commands.
#	    For example, cp becomes gcp and ls becomes gls.
#
#	    If you want to use the GNU tools by default, add this directory to the front of your PATH environment variable:
#	        /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.app/Contents/Resources/libexec/gnubin/
#	  dbus has the following notes:
#	    ############################################################################
#	    # Startup items were not installed for dbus
#	    # Some programs which depend on dbus might not function properly.
#	    # To load dbus manually, run
#	    #
#	    # launchctl load -w /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.app/Contents/Resources/Library/LaunchDaemons/org.freedesktop.dbus-system.plist
#	    # launchctl load -w /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.app/Contents/Resources/Library/LaunchAgents/org.freedesktop.dbus-session.plist
#	    ############################################################################
#	  py27-sphinx has the following notes:
#	    To make the Python 2.7 version of Sphinx the one that is run when you execute the commands without a version suffix, e.g. 'sphinx-build', run:
#
#	    port select --set sphinx py27-sphinx
#	zsh: exit 1     ./notes.sh
#	zero(ttys008):...ith-macports>

