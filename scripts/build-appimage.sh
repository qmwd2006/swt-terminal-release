#!/bin/bash
# Package the standalone terminal as an AppImage.
#
# Usage: scripts/build-appimage.sh <path-to-swt-terminal-checkout>
#
# The AppImage does not bundle a JRE: AppRun looks up `java` on PATH, so the
# target machine needs Java 17 or newer. The jar is fully self-contained
# otherwise (SWT and the pty native library are extracted from it at startup).
set -euo pipefail

SRC="${1:-src}"
APP="swt-terminal.AppDir"
DIST="dist"

JAR=$(ls "$SRC"/target/swt-terminal-*-all.jar | head -n1)
if [ -z "$JAR" ]; then
  echo "error: standalone jar not found under $SRC/target" >&2
  exit 1
fi
VERSION=$(basename "$JAR" | sed 's/^swt-terminal-//; s/-all\.jar$//')

rm -rf "$APP"
mkdir -p "$APP/usr/lib/swt-terminal" "$DIST"
cp "$JAR" "$APP/usr/lib/swt-terminal/swt-terminal.jar"

# Icon: prefer the @2x variant, scaled up to the 256px AppImage convention.
ICON="$SRC/eclipse-plugin/icons/terminal@2x.png"
if [ -f "$ICON" ]; then
  cp "$ICON" "$APP/swt-terminal.png"
else
  cp "$SRC/eclipse-plugin/icons/terminal.png" "$APP/swt-terminal.png"
fi

cat > "$APP/AppRun" <<'EOF'
#!/bin/sh
# Resolve the AppImage mount point and run the bundled jar with the system JRE.
HERE=$(dirname "$(readlink -f "$0")")
if ! command -v java >/dev/null 2>&1; then
  echo "swt-terminal needs Java 17 or newer on PATH but 'java' was not found." >&2
  echo "Install a JRE (e.g. 'sudo apt install openjdk-17-jre') and try again." >&2
  exit 1
fi
exec java -jar "$HERE/usr/lib/swt-terminal/swt-terminal.jar" "$@"
EOF
chmod +x "$APP/AppRun"

# APP_VERSION is supplied by the workflow (e.g. v0.1.0-20261025-de49453);
# fall back to the jar version so a manual run still produces valid metadata.
VERSION_STRING="${APP_VERSION:-$VERSION}"

cat > "$APP/swt-terminal.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SWT Terminal
Comment=Terminal emulator (SWT) $VERSION_STRING
Exec=swt-terminal
Icon=swt-terminal
Terminal=false
Categories=System;TerminalEmulator;
X-AppImage-Version=$VERSION_STRING
EOF

# Convenience copy of the version next to the jar, visible after
# --appimage-extract and in the AppImage's usr/lib tree.
printf '%s\n' "$VERSION_STRING" > "$APP/usr/lib/swt-terminal/version.txt"

TOOL=appimagetool-x86_64.AppImage
if [ ! -x "$TOOL" ]; then
  wget -q -O "$TOOL" \
    https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi

# ARCH is normally derived from the build host; make it explicit for CI.
ARCH=x86_64 ./"$TOOL" --appimage-extract-and-run "$APP" "$DIST/swt-terminal-$VERSION-x86_64.AppImage"
echo "created $DIST/swt-terminal-$VERSION-x86_64.AppImage"
