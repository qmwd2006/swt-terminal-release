# swt-terminal releases

Automated builds of [swt-terminal](https://github.com/qmwd2006/swt-terminal)
(the source repository is private; this repository only builds and publishes
artifacts).

Every push to the source repository triggers a build here via
`repository_dispatch`. Builds can also be started manually from the Actions tab.

## Downloads

Each release contains these files:

| File | What it is |
| --- | --- |
| `swt-terminal-<ver>-x86_64.AppImage` | Standalone terminal. Bundles a Java runtime (GTK 3 and FUSE still required). |
| `swt-terminal-<ver>-x86_64.tar.gz` | The same AppDir, extracted. Use this when AppImage/FUSE cannot run. |
| `swt-terminal-<ver>-x86_64.AppImage.zsync` | Update metadata for AppImageUpdate. |
| `com.cleanssh.swtterm.eclipse-<ver>.jar` | Eclipse plugin. **Eclipse 4.29 (2023-09) or newer.** |
| `swt-terminal-<ver>-all.jar` | Standalone jar. **Needs Java 17+.** |
| `SHA256SUMS` | SHA-256 checksums for the five other files. |

## Standalone AppImage

```bash
sha256sum -c SHA256SUMS
chmod +x swt-terminal-*-x86_64.AppImage
./swt-terminal-*-x86_64.AppImage
```

The AppImage bundles a jlink runtime, so no system Java installation is needed.
SWT still requires GTK 3 and an X11/Wayland desktop. The jar inside carries SWT
and the pty native library, and extracts them at startup, so no further setup is
needed.

The AppImage includes AppStream metadata and a 256 px icon, so desktop
environments can integrate it. It also carries zsync update information that
matches any versioned AppImage in the latest release, so AppImageUpdate keeps
working after the application version changes.

### No FUSE?

If the AppImage cannot mount because FUSE is unavailable, extract the tarball
instead:

```bash
tar -xzf swt-terminal-*-x86_64.tar.gz
./AppRun
```

`AppRun` and the `swt-terminal` symlink are both executable and use the bundled
runtime.

## Eclipse plugin

Copy the plugin jar into Eclipse's `dropins/` directory and restart Eclipse
(start with `-clean` the first time, or when replacing an older copy):

```bash
cp com.cleanssh.swtterm.eclipse-*.jar "$ECLIPSE_HOME/dropins/"
"$ECLIPSE_HOME/eclipse" -clean
```

Requirements: **Eclipse 4.29 or newer** (these run on Java 17). The plugin uses
only long-stable view/command/preference APIs, so newer releases work too.

To install it into the `plugins/` directory instead, copy the jar there and
start with `-clean`. Replacing a jar that is already loaded requires `-clean`;
otherwise the cached bundle is used.

### Using the terminal

- Open `Window > Show View > Other... > SWT Terminal > Terminal`.
- `Ctrl+Shift+Alt+J` opens a terminal for the current project, or switches to
  the project's existing terminal and cycles through them on repeat.
  (`Ctrl+Shift+T` and `Ctrl+Shift+J` are already taken by CDT and the text
  editor; `Ctrl+Shift+U` is swallowed by GTK's Unicode input.)
- Right-click a terminal for copy/paste, clear, font size and theme.
- `Window > Preferences > SWT Terminal` sets shell, fonts, size, scrollback,
  theme, ambiguous width and cursor style.

## How it is built

`.github/workflows/release.yml` checks out the private source repository with a
read-only deploy key, then runs:

```bash
./build-native.sh
mvn verify -Pintegration     # unit + real-PTY tests
mvn package -DskipTests      # standalone jar
cd eclipse-plugin && mvn verify
scripts/build-appimage.sh src
```

The AppImage build pins both `appimagetool` and the type-2 runtime by SHA-256.
It validates the desktop file and AppStream metadata, generates a 256 px icon,
publishes a tar.gz fallback, and embeds GitHub Releases zsync update information.

The Eclipse plugin's target platform resolves against the official online p2
repository for 2024-03 (Eclipse 4.31), so no local Eclipse is required.
