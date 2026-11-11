# Move an existing setup from UniFi OS 5 to 6

Preferably do these steps while the gateway is still online, before upgrading its firmware. 
But if you already upgraded, you can still follow the steps.

SSH into the gateway as `root`.

1. Add the OpenSSL setting to the global section of the wired config, above `network={}`:

```bash
grep -q '^openssl_ciphers=' /etc/wpa_supplicant/wpa_supplicant-wired-eth1.conf || sed -i '/^[[:space:]]*network[[:space:]]*=/i openssl_ciphers=DEFAULT@SECLEVEL=0' /etc/wpa_supplicant/wpa_supplicant-wired-eth1.conf
```

The conf file should look like:
```ini
eapol_version=1
ap_scan=0
fast_reauth=1
openssl_ciphers=DEFAULT@SECLEVEL=0
network={
...
```

2. Replace the previously saved packages with Debian 13 (trixie) versions:

```bash
mkdir -p /etc/wpa_supplicant/packages
cd /etc/wpa_supplicant/packages
rm -f ./*.deb
wget https://deb.debian.org/debian/pool/main/w/wpa/wpasupplicant_2.10-24_arm64.deb
wget https://deb.debian.org/debian/pool/main/p/pcsc-lite/libpcsclite1_2.3.3-1_arm64.deb
```

If you currently do not have internet access on the gateway, find a way to download these onto your computer, then scp them into the gateway.

> [!NOTE]
> If a link is unavailable, choose the current `arm64` packages from the [trixie wpasupplicant](https://packages.debian.org/trixie/arm64/wpasupplicant/download) and [libpcsclite1](https://packages.debian.org/trixie/arm64/libpcsclite1/download) pages.

Now upgrade the firmware. Hopefully you are done now.

Or if you were already upgraded, run:

```bash
dpkg -i /etc/wpa_supplicant/packages/*.deb
systemctl daemon-reload
```

Restart and verify the wired service:

```bash
systemctl enable --now wpa_supplicant-wired@eth1
dpkg -l wpasupplicant
systemctl status wpa_supplicant-wired@eth1 --no-pager
```

Confirm the package state is `ii` and the logs show authentication success. If it's still failing, try a gateway reboot.
