# claudetv

Strip the bloat, tracking and ads out of an Amazon Fire TV stick without rooting it.

`claudetv.sh` connects to the stick over ADB and disables Amazon's telemetry, promo and
unwanted app packages. It also helps you install a clean, ad-free launcher. **Everything is
reversible:** packages are disabled for your user, never deleted, and `restore` (or a factory reset)
brings them back.

| Device | Supported? |
|---|---|
| Fire TV Stick 4K, 1st gen (2018, codename `mantis`) | Yes, this is what it's built for |
| Other Fire OS sticks (4K 2nd gen, 4K Max) | Should work, untested. Use `--dry-run` first |
| Fire TV Stick 4K Select and other **Vega OS** devices | No. Vega OS has no ADB. See [docs/vega-select.md](docs/vega-select.md) |

## Setup

1. Install [Android platform-tools](https://developer.android.com/tools/releases/platform-tools)
   on your computer, so `adb` is available.
2. On the stick: **Settings → My Fire TV → About**, click the device name 7 times to unlock
   Developer Options. Then **Settings → My Fire TV → Developer Options → ADB debugging: ON**.
3. Find the stick's IP: **Settings → My Fire TV → About → Network**.
4. Connect, and accept the "Allow debugging?" prompt on the TV:

```sh
./claudetv.sh connect 192.168.1.50
./claudetv.sh info
```

## Use

```sh
./claudetv.sh scan                         # see every Amazon package and its state
./claudetv.sh --dry-run debloat            # preview: telemetry + ads + amazon-apps
./claudetv.sh debloat                      # do it (backs up package state first)
./claudetv.sh debloat alexa                # optional extra list
./claudetv.sh restore                      # undo everything
./claudetv.sh restore com.amazon.bueller.music   # undo one package
adb reboot
```

The lists in [`lists/`](lists) are plain text, one package per line, so edit them freely. Packages
not on your firmware are skipped. Two lists are never disabled, even if a package appears elsewhere:

- `lists/keep.txt`: your choices. Currently **Prime Video** and **Wi-Fi password sync**.
- `lists/protected.txt`: things the stick needs (home screen, Settings, Appstore, remote pairing).

| List | What it disables | Default? |
|---|---|---|
| `telemetry` | Metrics, crash reports, logging | ✅ |
| `ads` | Sponsored content, promo notifications, GameCircle | ✅ |
| `amazon-apps` | Amazon Kids, Shopping, Music, Photos, Freevee, Silk browser | ✅ |
| `alexa` | Alexa (breaks voice search) | |
| `updates` | System updates. ⚠️ Also blocks security fixes | |

## Getting rid of the home screen ads

The sponsored rows and autoplaying trailers come from Amazon's own launcher, which can't be safely
disabled. Debloating alone won't remove them. To get a clean home screen:

1. **Install a custom launcher.** [Projectivy Launcher](https://play.google.com/store/apps/details?id=com.spocky.projengmenu)
   is a good choice: search for it in the Amazon Appstore, or sideload its APK with
   `./claudetv.sh launcher projectivy.apk`. Then turn on its home-button override in its settings.
2. **Block ad domains with DNS.** Use [NextDNS](https://nextdns.io), [AdGuard DNS](https://adguard-dns.io)
   or a Pi-hole, set on your router or on the stick (**Network → your Wi-Fi → Advanced**, static IP
   with custom DNS).
3. **Turn off the extras in Settings:**
   - **Preferences → Featured Content:** turn off video and audio autoplay.
   - **Preferences → Privacy Settings:** turn off Device Usage Data, Collect App Usage Data and
     Interest-based Ads.
   - **Preferences → Notification Settings:** turn off app notifications.

## If something goes wrong

- Something stopped working: run `./claudetv.sh restore` and then `adb reboot`.
- Every run of `debloat` saves a snapshot of package state in `backups/`.
- Last resort: a factory reset (**Settings → My Fire TV → Reset to Factory Defaults**) restores every
  package, because nothing is ever deleted.
