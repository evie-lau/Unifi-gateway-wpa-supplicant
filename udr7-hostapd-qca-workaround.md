# Wired wpa_supplicant workaround for UDR7 and similar gateways

Gateways with built-in Wi-Fi may ship a UniFi `wpa_supplicant` without the `wired` driver and have a package conflict when installing Debian's version. This has been reported on a UniFi Dream Router 7 (UDR7) running UniFi OS 6.0.17, but has not been confirmed on every model or firmware version.

On the reported UDR7, `hostapd-qca` provides the built-in supplicant and conflicts with Debian's `wpasupplicant` over `/usr/lib/systemd/system/wpa_supplicant@.service`. This guide runs an extracted Debian copy from `/etc`, leaving UniFi's files in place so Wi-Fi is unaffected.

## Before you begin

- SSH into the gateway as `root` and confirm it reports Debian 13 (trixie) and `arm64`:

  ```bash
  grep PRETTY_NAME /etc/os-release
  dpkg --print-architecture
  ```

  Stop if either is different. The package paths and versions below are for Debian 13 on `arm64`.
- Use the interface identified while following the main guide. One UDR7 used `eth3.0`, a VLAN interface on `eth3`. The examples below use `eth3.0`; replace it throughout with your authentication interface, including in the config filename and service name.
- Prepare the certificates, config, MAC address, and WAN settings from the [main guide](./README.md#copy-certs-and-config-to-unifi-gateway). For Debian 13, make sure `openssl_ciphers=DEFAULT@SECLEVEL=0` is in the global section of the config, before `network={`.

> [!IMPORTANT]
> Use this guide **instead of** the main guide's package installation, wired service setup, and reinstall service steps. Do not run `dpkg -i` or `dpkg -Ri` on these packages as part of this workaround.

## Check whether this applies

Check the installed supplicant's drivers and the owner of the conflicting service file:

```bash
/usr/sbin/wpa_supplicant -h
dpkg -S /usr/lib/systemd/system/wpa_supplicant@.service
```

On the reported UDR7, the help lists `nl80211` but not `wired`, and `dpkg -S` reports `hostapd-qca`. If `wired` is listed, the installed binary supports the wired driver. If either command fails or the file belongs to another package, investigate before assuming this is the same issue: a missing driver alone does not establish a package conflict.

## 1. Download and extract the packages

Keep the matching Debian 13 packages in `/etc/wpa_supplicant/packages`. If these exact files are already cached, skip their downloads:

```bash
mkdir -p /etc/wpa_supplicant/packages
cd /etc/wpa_supplicant/packages
wget https://deb.debian.org/debian/pool/main/w/wpa/wpasupplicant_2.10-24_arm64.deb
wget https://deb.debian.org/debian/pool/main/p/pcsc-lite/libpcsclite1_2.3.3-1_arm64.deb
```

If the gateway is offline, download the packages on another computer and copy them into this folder. If a link is unavailable, find matching `arm64` packages on the [trixie wpasupplicant](https://packages.debian.org/trixie/arm64/wpasupplicant/download) and [libpcsclite1](https://packages.debian.org/trixie/arm64/libpcsclite1/download) pages. Adjust the filenames in both the extraction commands and the reinstall service below.

Extract the packages without installing them:

```bash
cd /etc/wpa_supplicant/packages
mkdir -p /etc/wpa_supplicant/trixie
dpkg-deb -x wpasupplicant_2.10-24_arm64.deb /etc/wpa_supplicant/trixie
dpkg-deb -x libpcsclite1_2.3.3-1_arm64.deb /etc/wpa_supplicant/trixie
```

Check that the extracted binary runs and lists `wired` under `drivers`. It uses the extracted `libpcsclite1` through `LD_LIBRARY_PATH`; other required libraries must be available on the gateway.

```bash
LD_LIBRARY_PATH=/etc/wpa_supplicant/trixie/usr/lib/aarch64-linux-gnu \
  /etc/wpa_supplicant/trixie/usr/sbin/wpa_supplicant -h
```

If it fails to run or does not list `wired`, resolve that before continuing.

## 2. Prepare the interface config

The service expects `/etc/wpa_supplicant/wpa_supplicant-wired-<interface>.conf`. If your config is still named `wpa_supplicant.conf`, copy it to the expected name, substituting your interface:

```bash
cp -i /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-wired-eth3.0.conf
```

If you already have an interface-specific config, use it or copy it to the appropriate name instead. Verify its certificate paths and global OpenSSL setting before starting the service.

## 3. Create the wired service

Create `/etc/systemd/system/wpa_supplicant-wired@.service`. If a custom file already exists at that path, review and back it up before replacing it.

```ini
[Unit]
Description=WPA supplicant daemon (interface- and wired driver-specific version)
Requires=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device
Before=network.target
Wants=network.target

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=/etc/wpa_supplicant/trixie/usr/lib/aarch64-linux-gnu
ExecStart=/etc/wpa_supplicant/trixie/usr/sbin/wpa_supplicant -c/etc/wpa_supplicant/wpa_supplicant-wired-%I.conf -Dwired -i%I
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
```

## 4. Configure the reinstall service

If you previously enabled `reinstall-wpa.service` from the main guide, stop and disable the old version before replacing it:

```bash
systemctl disable --now reinstall-wpa.service
```

Skip that command if the service was never created.

Save a copy of the custom wired template. If prompted to replace an older saved copy, confirm so it matches the template you just created. The reinstall service can restore this copy if the template is missing:

```bash
cp -i /etc/systemd/system/wpa_supplicant-wired@.service /etc/wpa_supplicant/wpa_supplicant-wired@.service
```

Create or replace `/etc/systemd/system/reinstall-wpa.service` with the following. Replace `eth3.0` with your authentication interface in **all three places**:

```ini
[Unit]
Description=Restore and start the separate wired wpa_supplicant
Before=wpa_supplicant-wired@eth3.0.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=oneshot
ExecStartPre=/bin/sh -c "test -e /etc/systemd/system/wpa_supplicant-wired@.service || { /usr/bin/cp -n /etc/wpa_supplicant/wpa_supplicant-wired@.service /etc/systemd/system/wpa_supplicant-wired@.service && /usr/bin/systemctl daemon-reload; }"
ExecStart=/bin/sh -c "test -x /etc/wpa_supplicant/trixie/usr/sbin/wpa_supplicant || /usr/bin/dpkg-deb -x /etc/wpa_supplicant/packages/wpasupplicant_2.10-24_arm64.deb /etc/wpa_supplicant/trixie"
ExecStart=/bin/sh -c "test -r /etc/wpa_supplicant/trixie/usr/lib/aarch64-linux-gnu/libpcsclite.so.1 && test -r /etc/wpa_supplicant/trixie/usr/lib/aarch64-linux-gnu/libpcsclite_real.so.1 || /usr/bin/dpkg-deb -x /etc/wpa_supplicant/packages/libpcsclite1_2.3.3-1_arm64.deb /etc/wpa_supplicant/trixie"
ExecStartPost=/usr/bin/systemctl reenable wpa_supplicant-wired@eth3.0.service
ExecStartPost=/usr/bin/systemctl --no-block start wpa_supplicant-wired@eth3.0.service
Restart=on-failure
RestartSec=20

[Install]
WantedBy=multi-user.target
```

The service runs before the wired service without waiting for internet access. It restores the template if missing and extracts each cached package only if its binary or libraries are missing, then reenables and starts the wired service. It does not overwrite UniFi's package files. If you change the wired template later, update its saved copy as well.

## 5. Enable and test

Reload systemd and enable both services. Start the reinstall service, then check it and the wired service. Substitute your interface:

```bash
systemctl daemon-reload
systemctl enable reinstall-wpa.service
systemctl reenable wpa_supplicant-wired@eth3.0.service
systemctl start reinstall-wpa.service
systemctl status reinstall-wpa.service --no-pager
systemctl show reinstall-wpa.service -p Result
systemctl status wpa_supplicant-wired@eth3.0.service --no-pager
```

The reinstall service should report `Result=success`; `inactive (dead)` is normal after a successful oneshot service finishes. The wired start is queued asynchronously, so allow it time to start before checking its status. Check the logs for `CTRL-EVENT-EAP-SUCCESS` and confirm that the WAN receives an IP address. An active service alone does not confirm authentication or DHCP.

To confirm the vendor binary was left in place:

```bash
ls -l /usr/sbin/wpa_supplicant
```

On the reported UDR7 it remained a symlink to `qca-hapd-supp`. Reboot and check the wired service and WAN connection again.

## Firmware updates

The reinstall service checks the files at boot but does not extract the packages unless they are missing. It relies on the reinstall service, its enabled link, cached packages, saved wired template, config, and certificates surviving under `/etc`; persistence can vary by device and firmware. After an update, verify the files, enabled services, authentication, and WAN connection.

If the reinstall service, cached packages, or saved template were removed, restore them manually. The service does not check the Debian release: if it changes, obtain matching packages, update the service, and revalidate the setup. Do not assume the trixie binaries or libraries will remain compatible. The file checks do not detect corruption or missing dependencies.
