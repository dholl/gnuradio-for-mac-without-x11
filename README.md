# gnuradio-for-mac-without-x11
This repo is based upon the work of cfriedt/gnuradio-for-mac-without-macports, with the notable difference that MacPorts *is* used.  However, the resulting /Applications/GNURadio.app bundle is independent of any existing MacPorts installation.  The upside is that we leverage all the patches and pre-packaging from MacPorts, and this bundle should not require XQuartz during execution.

## Example usage:
```sh
mkdir -p ~/Applications
./build.sh ~/Applications/GNURadio.app
# wait about 4.5 hours on a late-2016 MacBook Pro...
# then start GNURadio Companion like this:
~/Applications/NewGNURadio.app/Contents/Resources/bin/gnuradio-companion
```

## Prerequisites:
You must install Apple Xcode's "command line tools", via ```xcode-select --install``` in a terminal, and you likely need to install XQuartz from https://www.xquartz.org.

## Known todo:
* Finish bundling such as:
  * Create GNURadio.app/Contents/Info.plist to specify an icon and supported file extensions
  * Create some sort of launch helper in GNURadio.app/Contents/MacOS/GNURadio to spawn gnuradio-companion.
  * Make the whole thing relocatable.  At the moment, all paths are baked in during compile time.  So the .app won't work if you move it or sneeze on it.  ;)
* Test if the whole thing can be built without XQuartz.
