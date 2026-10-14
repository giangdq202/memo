# MeMo (Menu Monitor)

> [!WARNING]
> **This is a custom personal fork.** 
> This repository is highly customized for my own specific needs and aesthetic preferences. For the original general-purpose version, please visit the upstream repository: [openhoangnc/mac-stats](https://github.com/openhoangnc/mac-stats).

> A lightweight, zero-Xcode macOS menu bar system monitor written purely in Swift. Keeps track of your CPU usage, Memory consumption, Network speeds, and CPU temperature in real-time.

![macOS 11.0+](https://img.shields.io/badge/macOS-11.0%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Quick Start

### One-Line Download & Install
Just copy and paste this command into your Terminal. It will automatically download, extract, and install **MeMo** directly into your `/Applications` folder:

```bash
curl -fsSL https://raw.githubusercontent.com/giangdq202/memo/main/install.sh | bash
```

---

### Complete Uninstallation
Want to remove it completely? This command safely stops the app, removes it from your startup items, clears your user preferences, and deletes the app bundle:

```bash
curl -fsSL https://raw.githubusercontent.com/giangdq202/memo/main/uninstall.sh | bash
```

---

## Key Features

- **Ultra-Lightweight & Blazing Fast**: Written entirely in native Swift, guaranteeing a minimal memory and CPU footprint. No bloated Xcode projects or heavy third-party dependencies.
- **Triple-Column Menu Bar Display**:
  - **Left (Network)**: Real-time Upload (top) and Download (bottom) speeds. Units scale automatically (B, K, M, G), and colors adapt dynamically to bandwidth usage.
  - **Center (CPU/Memory)**: Live CPU load (%, top) and RAM usage (G, bottom). Smart color thresholds (Green -> Yellow -> Red) instantly warn you under heavy load.
  - **Right (Temperature)**: Average CPU temperature (top) and unit (C or F, bottom). Text colors shift dynamically based on heat levels.
- **Top Resource Hogs at a Glance**: Opening the menu instantly reveals the apps consuming the most **CPU** and **memory**, ranked in real time. Helper processes (like a browser's many renderers) are rolled up into their parent app, and background system daemons are filtered out so you only see the apps that actually matter.
- **Quick Settings Menu**: Left or right-click the menu bar icon to access:
  - **Open Activity Monitor**: Jump straight to macOS Activity Monitor for the full, detailed breakdown.
  - **Show Network Speeds**: Toggle the visibility of the network speeds column.
  - **Show CPU Temperature**: Toggle the visibility of the CPU temperature column.
  - **Launch at Login**: Easily toggle automatic startup. (Seamlessly uses macOS 13+ `SMAppService`, with automatic fallbacks to LaunchAgents plist for older systems).
  - **Update Interval**: Customize how often data refreshes (250ms, 500ms, 1s, 2s, or 5s).
  - **Network Display Units**: Choose between Auto, Bytes/s (B/s, KB/s, MB/s), Bits/s (bps, Kbps, Mbps), or Mixed mode.
  - **Temperature Unit**: Switch effortlessly between Celsius and Fahrenheit.
  - **GitHub Repository**: Direct link to the source code.
  - **Quit MeMo**: Safely close the app.
- **Dynamic SMC Temperature Scanning**: On startup, it automatically discovers active SMC temperature sensors for Apple Silicon (M1/M2/M3/M4/M5) chips including efficiency cores, performance cores, and general sensors to calculate a highly accurate real-time average.
- **Deep Performance & Memory Optimizations**:
  - Runs entirely as a background accessory (`LSUIElement`). It stays out of your Dock and won't clutter your Command-Tab app switcher.
  - Monitors system memory pressure via `kern.memorystatus_vm_pressure_level` sysctl to reflect genuine macOS memory load.
  - Implements a smart 25% timer tolerance, allowing macOS to coalesce background tasks and drastically save battery life.
- **Automated CI/CD Workflows**: A built-in GitHub Actions pipeline automatically compiles the `.app`, increments semantic version numbers, and publishes new GitHub Releases.

---

## CLI Flags & Manual Build
The compiled binary natively supports the following command-line flags for silent management:
- `--cleanup-login-item` / `--uninstall-login-item` / `--uninstall`: Silently unregisters `SMAppService` launch items, removes user LaunchAgent plists, flushes user defaults, and immediately exits.

If you prefer to compile it yourself from source:

1. Clone the repository:
   ```bash
   git clone https://github.com/giangdq202/memo.git
   cd memo
   ```

2. **Build & install in one step (recommended).** When run from a local
   checkout, `install.sh` detects the source and builds from it instead of
   downloading a release, compiling an optimized `arm64` (Apple Silicon) binary
   via `build.sh`, installing it to `/Applications`, and launching it:
   ```bash
   ./install.sh
   ```

   Or just build the `.app` bundle in place without installing:
   ```bash
   ./build.sh
   open MeMo.app
   ```

> **Note:** The one-line command in [Quick Start](#-one-line-download--install) downloads the latest prebuilt release, whereas `./install.sh` run from a cloned repo always builds and installs your local source.

---

## Continuous Integration & Versioning

The project is fully automated via `.github/workflows/release.yml`.

- **Automatic Version Bumping**: Pushing to the main branch (or triggering manually) automatically bumps the version number (e.g., `v1.0.0` -> `v1.0.1`).
- **Automated Releases**: The workflow compiles the native macOS app bundle, compresses it into `MeMo.zip`, and automatically attaches it to a new GitHub Release.

---

## For Developers: Unique Techniques to Learn

This project employs several uncommon and highly optimized techniques for macOS development that you might find interesting:

1. **Zero-Xcode App Bundling**: This app is built entirely without an Xcode project file. Instead, it uses a custom bash script (`build.sh`) that invokes the `swiftc` compiler directly with aggressive size optimizations (`-Osize`, `-wmo`, `-dead_strip`). It then manually constructs the `.app` bundle structure, proving that you can build native macOS UI apps with just a terminal and text editor.
2. **Direct Low-Level C APIs**: To achieve near-zero CPU overhead, the app bypasses high-level `Foundation` wrappers. It directly calls Mach kernel APIs (`host_processor_info`, `host_statistics64`) and BSD socket APIs (`getifaddrs`) from Swift using raw memory pointers.
3. **Primary Interface Routing via SCDynamicStore**: Rather than blindly summing all network interfaces, the engine queries `SCDynamicStore` for the primary active IPv4 interface (e.g. `en0`) and applies a bandwidth spike filter to prevent artificial spikes on interface reconnection.
4. **Dynamic SMC Discovery via IOKit**: Instead of hardcoding temperature sensor keys, the app dynamically discovers sensors via SMC key count (`#KEY`) and index queries, sorting them into P-Cores, E-Cores, GPU, and CPU clusters.
5. **System Memory Pressure Tracking**: Uses `kern.memorystatus_vm_pressure_level` sysctl and computes active application memory (`active + speculative - purgeable`) to closely align with macOS Activity Monitor metrics.

---

## License

This project is licensed under the MIT License.
