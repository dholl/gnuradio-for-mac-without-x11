#!/bin/sh
set -e
set -u

# Start with clean environment:
pkgbase_clean_only=1
pkgbase=/pkg
. ~/Desktop/ad5ey/profile.d/_pkg.sh
pkgbase=~/.pkg
. ~/Desktop/ad5ey/profile.d/_pkg.sh
unset pkgbase
unset pkgbase_clean_only

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

mkdir -p "${app_dir}" "${app_dir}/tmp"

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
		--with-applications-dir="${app_dir}/Contents/Applications" \
		--with-frameworks-dir="${app_dir}/Contents/Frameworks"
	make -j"$(sysctl -n hw.ncpu)"
	make install
	)

	touch "${tmp_dir}/.macports-base.installed"

	# Save some space:
	rm -rf "${tmp_dir}/macports-base"
fi

# Congratulations, you have successfully installed the MacPorts system. To get
# the Portfiles and update the system, add
# /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/tmp-install/bin
# to your PATH and run:
# sudo port -v selfupdate

# My idea: Naw, I won't mess up PATH for this, just to see if anything breaks.
#export PATH="${app_dir}/Contents/Resources/bin:$PATH"


# WORK AROUND this bug:
#--->  Building openjade
#Error: Failed to build openjade: command execution failed
#Error: See /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.app/Contents/Resources/var/macports/logs/_Users_dholl_Desktop_Installers_gnuradio-for-mac-with-macports_GNURadio.app_Contents_Resources_var_macports_sources_rsync.macports.org_macports_release_tarballs_ports_textproc_openjade/openjade/main.log for details.
#Error: Follow https://guide.macports.org/#project.tickets to report a bug.
#Error: Processing of port gnuradio failed
#:info:build make[2]: *** No rule to make target `/Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.lapp/Contents/Resources/lib/libosp.dylib', needed by `openjade'.  Stop.
lapp_dir="$(printf '%s' "${app_dir}" | sed -e 's/.app/.lapp/g' && printf 'x\n')"
lapp_dir="${lapp_dir%??}"
if test -L "${lapp_dir}" ; then
	rm "${lapp_dir}"
fi
if ! test -e "${lapp_dir}" ; then
	ln -s "${app_dir}" "${lapp_dir}"
fi
if ! test -L "${lapp_dir}" ; then
	printf 'Failed to create symbolic link at %s\n' "${lapp_dir}"
fi
# END OF WORK AROUND

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

# TODO: Only run this if we haven't done it in 20 hours:
# One way to get file mod time: echo $(eval "$(stat -s GIMPskel.url)" ; echo $st_mtime)
touch "${tmp_dir}/.current_time"
current_time="$(eval "$(stat -s "${tmp_dir}/.current_time")" ; echo $st_mtime)"
rm -f "${tmp_dir}/.current_time"
if test -e "${tmp_dir}/.update_time" ; then
	update_time="$(eval "$(stat -s "${tmp_dir}/.update_time")" ; echo $st_mtime)"
else
	update_time=0
fi

need_upgrade_outdated=''
if test "$(( current_time-update_time > 20*60*60))" -eq "1" ; then
	PATH="${app_dir}/Contents/Resources/bin:$PATH" "${app_dir}/Contents/Resources/bin/port" selfupdate
	need_upgrade_outdated='yep'
fi

# -----------------------------------------------------------
# Fix for volk port needing to run /bin/ps which is setuid and thus blocked by
# the sandbox:  We'll open the sandbox a little.
# https://github.com/Homebrew/brew/blob/master/Library/Homebrew/sandbox.rb
#
#	--->  Configuring volk
#	Error: Failed to configure volk: configure failure: command execution failed
#	Error: See /Users/dholl/Desktop/Installers/gnuradio-for-mac-with-macports/GNURadio.app/Contents/Resources/var/macports/logs/_Users_dholl_Desktop_Installers_gnuradio-for-mac-with-macports_GNURadio.app_Contents_Resources_var_macports_sources_rsync.macports.org_macports_release_tarballs_ports_science_volk/volk/main.log for details.
#	Error: Follow https://guide.macports.org/#project.tickets to report a bug.
#	Error: Processing of port gnuradio failed
cd "${app_dir}/Contents/Resources"
if fgrep -q '\"/bin/ps\"' "${app_dir}/Contents/Resources/libexec/macports/lib/port1.0/portsandbox.tcl" ; then
	printf '/bin/ps is already in %s\n' "${app_dir}/Contents/Resources/libexec/macports/lib/port1.0/portsandbox.tcl"
else
	printf 'Adding /bin/ps to %s ...\n' "${app_dir}/Contents/Resources/libexec/macports/lib/port1.0/portsandbox.tcl"
	patch --forward -p3 "${app_dir}/Contents/Resources/libexec/macports/lib/port1.0/portsandbox.tcl" << 'EOF'
diff -ruN GNURadio.app.old/Contents/Resources/libexec/macports/lib/port1.0/portsandbox.tcl GNURadio.app.new/Contents/Resources/libexec/macports/lib/port1.0/portsandbox.tcl
--- GNURadio.app.old/Contents/Resources/libexec/macports/lib/port1.0/portsandbox.tcl	2017-06-07 00:26:39.000000000 -0700
+++ GNURadio.app.new/Contents/Resources/libexec/macports/lib/port1.0/portsandbox.tcl	2017-06-09 18:38:58.000000000 -0700
@@ -87,6 +87,8 @@
 (regex #\"^/dev/fd/\")) (allow file-write* \
 (regex #\"^(/private)?(/var)?/tmp/\" #\"^(/private)?/var/folders/\"))"
 
+    append portsandbox_profile " (allow process-exec (literal \"/bin/ps\") (with no-sandbox))"
+
     foreach dir $allow_dirs {
         append portsandbox_profile " (allow file-write* ("
         if {${os.major} > 9} {
EOF
fi

if test -n "${need_upgrade_outdated}" ; then
	PATH="${app_dir}/Contents/Resources/bin:$PATH" "${app_dir}/Contents/Resources/bin/port" -u upgrade outdated || true
	touch "${tmp_dir}/.update_time"
fi
unset need_upgrade_outdated

#if fgrep -q '\"/bin/ps\"' "${app_dir}/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/base/src/port1.0/portsandbox.tcl" ; then
#	printf '/bin/ps is already in %s\n' "${app_dir}/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/base/src/port1.0/portsandbox.tcl"
#else
#	printf 'Adding /bin/ps to %s\n' "${app_dir}/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/base/src/port1.0/portsandbox.tcl"
#	patch --forward -p3 << 'EOF'
#diff -ruN GNURadio.app.old/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/base/src/port1.0/portsandbox.tcl GNURadio.app.new/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/base/src/port1.0/portsandbox.tcl
#--- GNURadio.app.old/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/base/src/port1.0/portsandbox.tcl	2017-02-26 04:25:13.000000000 -0800
#+++ GNURadio.app.new/Contents/Resources/var/macports/sources/rsync.macports.org/macports/release/tarballs/base/src/port1.0/portsandbox.tcl	2017-06-09 18:39:09.000000000 -0700
#@@ -87,6 +87,8 @@
# (regex #\"^/dev/fd/\")) (allow file-write* \
# (regex #\"^(/private)?(/var)?/tmp/\" #\"^(/private)?/var/folders/\"))"
# 
#+    append portsandbox_profile " (allow process-exec (literal \"/bin/ps\") (with no-sandbox))"
#+
#     foreach dir $allow_dirs {
#         append portsandbox_profile " (allow file-write* ("
#         if {${os.major} > 9} {
#EOF
#fi
# -----------------------------------------------------------

# This takes a long time:  TODO: run clean --all all when we detect the script had been aborted.  (touch a .dirty file in tmp which we remove upon clean exit?)
#PATH="${app_dir}/Contents/Resources/bin:$PATH" "${app_dir}/Contents/Resources/bin/port" -f clean --all all
#PATH="${app_dir}/Contents/Resources/bin:$PATH" "${app_dir}/Contents/Resources/bin/port" -f uninstall inactive


# libmirisdr ?
port_names="gnuradio hackrf bladeRF airspy rtl-sdr gr-osmosdr"
port_names_to_install=""
for port_name in ${port_names} ; do
	if test "$(PATH="${app_dir}/Contents/Resources/bin:$PATH" "${app_dir}/Contents/Resources/bin/port" -q contents "${port_name}" | wc -l)" -eq "0" ; then
		port_names_to_install="${port_names_to_install-}${port_names_to_install:+" "}${port_name}"
	fi
done
unset port_name
printf 'port_names_to_install=%s\n' "${port_names_to_install}"
if [ -n "${port_names_to_install}" ]; then
	PATH="${app_dir}/Contents/Resources/bin:$PATH" "${app_dir}/Contents/Resources/bin/port" -N -s install ${port_names_to_install}
fi
unset port_names_to_install
#py27-cairo has the following notes:
#	Make sure cairo is installed with the +x11 variant when installing the binary version of py27-cairo or install py27-cairo from source like so:
#		sudo port install -s py27-cairo

# WORK AROUND
rm "${lapp_dir}"
# END OF WORK AROUND

# "${main_src_dir}/fix-library-references" "${app_dir}/Contents"
# "${main_src_dir}/fix-symbolic-links" "${app_dir}/Contents"

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

