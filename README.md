# swt-terminal releases

Automated builds of [swt-terminal](https://github.com/qmwd2006/swt-terminal)
(the source repository is private; this repository only builds and publishes
artifacts).

Every push to the source repository triggers a build here via
`repository_dispatch`. Builds can also be started manually from the Actions tab.

## Version scheme

Tags look like `v0.1.0-20261029-003-143caee`:

- `0.1.0` is the Maven base version;
- `20261029` is the source commit date (`YYYYMMDD`);
- `003` is the day's release sequence, zero-padded to three digits, so several
  releases in one day stay ordered and unique;
- `143caee` is the source commit (`git rev-parse --short`).

The sequence counts the releases already published for that commit date and
starts at `001`. Re-running the workflow for a commit that was already released
reuses its sequence, so a retry never creates a second version. Artifact names,
the release title, `--version` and the Eclipse `Bundle-Version`
(`0.1.0.20261029-003-143caee`) all carry the same string.

## Downloads

Each release contains these files:

| File | What it is |
| --- | --- |
| `swt-terminal-<ver>-x86_64.AppImage` | Standalone terminal. Bundles a Java 17 runtime (~35 MB; GTK 3 and FUSE still required). |
| `swt-terminal-<ver>-x86_64.tar.gz` | The same AppDir, extracted. Use this when AppImage/FUSE cannot run. |
| `swt-terminal-<ver>-x86_64.AppImage.zsync` | Update metadata for AppImageUpdate. |
| `swt-terminal-<ver>-x86_64-small.AppImage` | Standalone terminal without a bundled runtime (~2.5 MB). **Needs Java 17+** (GTK 3 and FUSE still required). |
| `swt-terminal-<ver>-x86_64-small.tar.gz` | The small AppDir, extracted. Use this when AppImage/FUSE cannot run. |
| `swt-terminal-<ver>-x86_64-small.AppImage.zsync` | Update metadata for the small build. |
| `com.cleanssh.swtterm.eclipse-0.1.0.<date>-<seq>-<sha>.jar` | Eclipse plugin, named after its `Bundle-Version`. **Eclipse 4.29 (2023-09) or newer.** |
| `swt-terminal-<ver>-all.jar` | Standalone jar. **Needs Java 17+.** |
| `SHA256SUMS` | SHA-256 checksums for the eight other files. |

## Standalone AppImage

Each release ships two builds of the same application:

- `swt-terminal-*-x86_64.AppImage` bundles a jlink Java 17 runtime (~35 MB), so
  no system Java installation is needed.
- `swt-terminal-*-x86_64-small.AppImage` leaves the runtime out (~2.5 MB) and
  uses the `java` found on `PATH`; **Java 17+ is required**.

Both still need GTK 3 and an X11/Wayland desktop. The jar inside carries SWT and
the pty native library, and extracts them at startup, so no further setup is
needed.

```bash
sha256sum -c SHA256SUMS
chmod +x swt-terminal-*-x86_64.AppImage        # bundled runtime
./swt-terminal-*-x86_64.AppImage
```

Or, on a machine with Java 17+:

```bash
chmod +x swt-terminal-*-x86_64-small.AppImage
./swt-terminal-*-x86_64-small.AppImage
```

Both builds include AppStream metadata and a 256 px icon, so desktop
environments can integrate them. Each carries its own zsync update information
(the small build updates from the `-small` asset), so AppImageUpdate keeps
working after the application version changes.

### No FUSE?

If the AppImage cannot mount because FUSE is unavailable, extract the matching
tarball instead:

```bash
tar -xzf swt-terminal-*-x86_64.tar.gz        # bundled runtime
# or
tar -xzf swt-terminal-*-x86_64-small.tar.gz  # needs Java 17+
./AppRun
```

`AppRun` and the `swt-terminal` symlink are both executable. The full tarball
uses the bundled runtime; the small one uses the system Java.

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
scripts/build-appimage.sh src                  # full build, bundles a jlink runtime
APPIMAGE_VARIANT=small BUNDLE_RUNTIME=0 \
  scripts/build-appimage.sh src                # small build, uses system Java
```

The AppImage build pins both `appimagetool` and the type-2 runtime by SHA-256.
It builds both variants from the same AppDir logic, validates the desktop file
and AppStream metadata, generates a 256 px icon, publishes a tar.gz fallback for
each variant, and embeds per-variant GitHub Releases zsync update information.

The Eclipse plugin's target platform resolves against the official online p2
repository for 2024-03 (Eclipse 4.31), so no local Eclipse is required.
