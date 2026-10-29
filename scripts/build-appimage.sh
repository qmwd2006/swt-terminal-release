#!/bin/bash
# Package the standalone terminal as an AppImage and a FUSE-free tarball.
#
# Usage: scripts/build-appimage.sh <path-to-swt-terminal-checkout>
#
# The AppImage bundles a jlink runtime, so the target machine does not need a
# system JRE. Set BUNDLE_RUNTIME=0 to build the "small" variant instead, which
# omits the runtime and falls back to a system Java 17+ at startup. The jar is
# also self-contained (SWT and the pty native library are extracted from it at
# startup), but GTK 3 and an X11/Wayland desktop are still required by SWT.
#
# APPIMAGE_VARIANT adds a suffix to the artifact names. Keep the suffix after
# the architecture ("-x86_64-small") so the two AppImageUpdate globs stay
# disjoint: swt-terminal-*-x86_64.AppImage.zsync vs
# swt-terminal-*-x86_64-small.AppImage.zsync.
set -euo pipefail

SRC="${1:-src}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP="swt-terminal.AppDir"
DIST="dist"
ARCH_NAME=x86_64
BUNDLE_RUNTIME="${BUNDLE_RUNTIME:-1}"
APPIMAGE_VARIANT="${APPIMAGE_VARIANT:-}"
APPIMAGETOOL_VERSION=1.9.1
APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_VERSION=20251108
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d

JAR=$(ls "$SRC"/target/swt-terminal-*-all.jar | head -n1)
if [ -z "$JAR" ]; then
  echo "error: standalone jar not found under $SRC/target" >&2
  exit 1
fi
VERSION=$(basename "$JAR" | sed 's/^swt-terminal-//; s/-all\.jar$//')
VERSION_STRING="${APP_VERSION:-$VERSION}"
APP_DATE="${APP_DATE:-$(date -u +%Y-%m-%d)}"

rm -rf "$APP"
mkdir -p "$APP/usr/lib/swt-terminal" "$DIST"
cp "$JAR" "$APP/usr/lib/swt-terminal/swt-terminal.jar"

# Bundle a minimal runtime. Keep this list aligned with what the terminal uses:
# SWT (java.desktop + GTK JNI), AWT Desktop for links, ImageIO for images,
# Preferences for window/font state, and Unsafe via jdk.unsupported.
if [ "$BUNDLE_RUNTIME" = 1 ]; then
  JAVA_BIN=$(command -v java)
  JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$JAVA_BIN")")")
  JLINK="$JAVA_HOME/bin/jlink"
  if [ ! -x "$JLINK" ]; then
    echo "error: jlink not found under $JAVA_HOME (a JDK, not a JRE, is required)" >&2
    exit 1
  fi
  "$JLINK" --add-modules java.base,java.desktop,java.logging,java.prefs,java.xml,jdk.unsupported \
    --strip-debug --no-man-pages --no-header-files --compress=2 \
    --output "$APP/usr/lib/runtime"
fi

# Use the committed 256px asset: the source-tree icons are only 16px/32px and
# upscaling them at build time would either blur them or depend on ImageMagick.
install -Dm644 "$SCRIPT_DIR/swt-terminal-256.png" "$APP/swt-terminal.png"
install -Dm644 "$SCRIPT_DIR/swt-terminal-256.png" \
  "$APP/usr/share/icons/hicolor/256x256/apps/swt-terminal.png"

cat > "$APP/AppRun" <<'EOF'
#!/bin/sh
# Prefer the bundled jlink runtime; fall back to a system JRE in the small
# variant and in hand-built AppDirs made before bundling was added.
HERE=$(dirname "$(readlink -f "$0")")
JAVA="$HERE/usr/lib/runtime/bin/java"
if [ ! -x "$JAVA" ]; then
  if ! command -v java >/dev/null 2>&1; then
    echo "swt-terminal needs Java 17 or newer but no runtime was found." >&2
    exit 1
  fi
  JAVA=java
fi
exec "$JAVA" -jar "$HERE/usr/lib/swt-terminal/swt-terminal.jar" "$@"
EOF
chmod +x "$APP/AppRun"

# Keep a command named in the desktop file so extracted/hand-integrated AppDirs
# work as well as AppImage-aware launchers.
ln -s AppRun "$APP/swt-terminal"

DESKTOP_FILE="$APP/swt-terminal.desktop"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=SWT Terminal
GenericName=Terminal Emulator
Comment=Terminal emulator (SWT) $VERSION_STRING
Exec=swt-terminal
Icon=swt-terminal
Terminal=false
Categories=System;TerminalEmulator;
Keywords=terminal;shell;console;command line;pty;
StartupNotify=true
X-AppImage-Version=$VERSION_STRING
EOF
install -Dm644 "$DESKTOP_FILE" \
  "$APP/usr/share/applications/swt-terminal.desktop"

mkdir -p "$APP/usr/share/metainfo"
APPSTREAM_FILE="$APP/usr/share/metainfo/com.cleanssh.swtterm.appdata.xml"
sed -e "s|@VERSION@|$VERSION|g" -e "s|@DATE@|$APP_DATE|g" \
  "$SCRIPT_DIR/com.cleanssh.swtterm.appdata.xml.in" \
  > "$APPSTREAM_FILE"

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$DESKTOP_FILE"
else
  echo "warning: desktop-file-validate not found; skipping desktop validation" >&2
fi
if command -v appstreamcli >/dev/null 2>&1; then
  appstreamcli validate --no-net "$APPSTREAM_FILE"
else
  echo "warning: appstreamcli not found; skipping AppStream validation" >&2
fi

# Convenience copy of the version next to the jar, visible after
# --appimage-extract and in the AppImage's usr/lib tree.
printf '%s\n' "$VERSION_STRING" > "$APP/usr/lib/swt-terminal/version.txt"

TOOL="appimagetool-$APPIMAGETOOL_VERSION-x86_64.AppImage"
if [ ! -x "$TOOL" ]; then
  curl -fL --retry 3 --retry-delay 2 -o "$TOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-x86_64.AppImage"
  chmod +x "$TOOL"
fi
printf '%s  %s\n' "$APPIMAGETOOL_SHA256" "$TOOL" | sha256sum -c -

RUNTIME="runtime-$ARCH_NAME-$RUNTIME_VERSION"
if [ ! -f "$RUNTIME" ]; then
  curl -fL --retry 3 --retry-delay 2 -o "$RUNTIME" \
    "https://github.com/AppImage/type2-runtime/releases/download/$RUNTIME_VERSION/runtime-$ARCH_NAME"
fi
printf '%s  %s\n' "$RUNTIME_SHA256" "$RUNTIME" | sha256sum -c -

SUFFIX="${APPIMAGE_VARIANT:+-$APPIMAGE_VARIANT}"
APPIMAGE_NAME="swt-terminal-$VERSION_STRING-$ARCH_NAME$SUFFIX.AppImage"
UPDATE_INFO="gh-releases-zsync|qmwd2006|swt-terminal-release|latest|swt-terminal-*-$ARCH_NAME$SUFFIX.AppImage.zsync"

# appimagetool writes the .zsync next to the output when zsyncmake is present.
# Its own AppStream check calls validate-tree without --no-net, which can block
# on restricted networks, so validate above and skip the internal check.
ARCH=$ARCH_NAME ./"$TOOL" --appimage-extract-and-run -n \
  --runtime-file "$RUNTIME" -u "$UPDATE_INFO" "$APP" "$DIST/$APPIMAGE_NAME"
echo "created $DIST/$APPIMAGE_NAME"

ZSYNC="$DIST/$APPIMAGE_NAME.zsync"
if command -v zsyncmake >/dev/null 2>&1; then
  if [ ! -f "$ZSYNC" ]; then
    zsyncmake -u "$APPIMAGE_NAME" -o "$ZSYNC" "$DIST/$APPIMAGE_NAME"
  fi
  echo "created $ZSYNC"
else
  echo "warning: zsyncmake not found; skipping .zsync generation" >&2
fi

# FUSE-free fallback for systems that cannot mount AppImages. Keep the same
# AppDir layout so AppRun, the icon and the desktop file remain usable.
TARBALL="$DIST/swt-terminal-$VERSION_STRING-$ARCH_NAME$SUFFIX.tar.gz"
tar -C "$APP" --sort=name --owner=0 --group=0 --numeric-owner \
  -czf "$TARBALL" .
echo "created $TARBALL"
