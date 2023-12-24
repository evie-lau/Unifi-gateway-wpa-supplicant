# UXG-Lite wpa_supplicant bypass ATT fiber modem

Use this guide to setup wpa_supplicant with your UXG-Lite to bypass the ATT modem.

Prerequisites:
- extracted and decoded certificates from an ATT modem

Instructions to [extract certs for newish BGW210](https://github.com/mozzarellathicc/attcerts)

## Install wpa_supplicant on the UXG-Lite
SSH into your UXG-Lite. It runs Debian, so we can install the `wpasupplicant` package.
```
> apt-get install wpasupplicant
```

## Copy certs and config to UXG-Lite
Prepare your files on your computer to copy into the UXG-Lite

These files come from the mfg_dat_decode tool:
- CA_XXXXXX-XXXXXXXXXXXXXX.pem
- Client_XXXXXX-XXXXXXXXXXXXXX.pem
- PrivateKey_PKCS1_XXXXXX-XXXXXXXXXXXXXX.pem
- wpa_supplicant.conf

```
> scp *.pem <uxg-lite>:/etc/wpa_supplicant/certs
> scp wpa_supplicant.conf <uxg-lite>:/etc/wpa_supplicant
```
> Note: Create the `certs` folder in `/etc/wpa_supplicant` first if you need to.

Make sure in the `wpa_supplicant.conf` to modify the `ca_cert`, `client_cert` and `private_key` to use absolute paths. In this case, prepend `/etc/wpa_supplicant/certs/` to the filename strings.

## Setup network

ATT authenticates using VLAN ID 0, so we have to tag our WAN port with that.

In your Unifi console/dashboard, under `Settings` -> `Internet` -> `Primary (WAN1)` (or your WAN name if you renamed it), Enable `VLAN ID` and set it to `0`.

![Alt text](vlan0.png)

You will not be able to access the internet after applying this change, until running `wpa_supplicant` in the next step.

Now go unplug the ethernet cable from the ONT port on your ATT Gateway, and plug it into the WAN port on your UXG-Lite.

## Test wpa_supplicant

```
> wpa_supplicant -i eth1 -D wired -c /etc/wpa_supplicant/wpa_supplicant.conf
```
Breaking down this command...
- `-i eth1` Specifies `eth1` (UXG-Lite WAN port) as the interface
- `-D wired` Specify driver type of `eth1`
- `-c <path-to>/wpa_supplicant.conf` The config file

You should see the message `Successfully initialized wpa_supplicant` if the command and config are configured correctly.

Following that will be some logs from authenticating. If it looks something like this, then it was successful! If not, try [spoofing the mac address](#spoof-mac-address) (I'm unsure if this is necessary).
```
eth1: CTRL-EVENT-EAP-PEER-CERT depth=0 subject='/C=US/ST=Michigan/L=Southfield/O=ATT Services Inc/OU=OCATS/CN=aut03lsanca.lsanca.sbcglobal.net' hash=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
eth1: CTRL-EVENT-EAP-PEER-ALT depth=0 DNS:aut03lsanca.lsanca.sbcglobal.net
eth1: CTRL-EVENT-EAP-SUCCESS EAP authentication completed successfully
eth1: CTRL-EVENT-CONNECTED - Connection to XX:XX:XX:XX:XX:XX completed [id=0 id_str=]
```

`Ctrl-c` to exit. If you would like to run it in the background for temporary internet access, add a `-B` parameter to the command. Running this command is still a manual process to authenticate, and it will only last until the next reboot.

## Setup wpa_supplicant service for startup
Now we have to make sure wpa_supplicant starts automatically when the UXG-Lite reboots, whether from firmware updates or power interruptions.

Let's use wpa_supplicant's built in interface-specific service to enable it on startup. More information [here](https://wiki.archlinux.org/title/Wpa_supplicant#At_boot_.28systemd.29).

Because we need to specify the `wired` driver and `eth1` interface, the corresponding service will be `wpa_supplicant-wired@eth1.service`. This service is tied to a specific .conf file, so we will have to rename our config file.

Back in `/etc/wpa_supplicant`, rename `wpa_supplicant.conf` to `wpa_supplicant-wired-eth1.conf`.
```
> cd /etc/wpa_supplicant
> mv wpa_supplicant.conf wpa_supplicant-wired-eth1.conf
```

Then start the service and check the status.
```
> systemctl start wpa_supplicant-wired@eth1

> systemctl status wpa_supplicant-wired@eth1
```
If the service successfully started and is active, you should see similar logs as when we tested with the `wpa_supplicant` command.

Now we can go ahead and enable the service.
```
> systemctl enable wpa_supplicant-wired@eth1
```

Try restarting your UXG-Lite if you wish, and it should automatically authenticate!

## Spoof mac address
> NOTE: I'm actually not sure if this is required. But if you are unable to authenticate, then try this.
Based on these [instructions to spoof mac address](https://www.xmodulo.com/spoof-mac-address-network-interface-linux.html).

SSH into your UXG-Lite, and create the following file.

`vi /etc/network/if-up.d/changemac`

```
#!/bin/sh

if [ "$IFACE" = eth1 ]; then
  ip link set dev "$IFACE" address XX:XX:XX:XX:XX:XX
fi
```
Replace the mac address with your gateway's address, found in the `wpa_supplicant.conf` file.

Set the permissions:
```
sudo chmod 755 /etc/network/if-up.d/changemac
```