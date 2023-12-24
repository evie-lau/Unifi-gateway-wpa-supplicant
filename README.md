# UXG-Lite wpa_supplicant bypass ATT fiber modem

Use this guide to setup wpa_supplicant with your UXG-Lite to bypass the ATT modem.

Prerequisites:
- extracted and decoded certificates from an ATT modem

Instructions to extract certs for newish [BGW210](https://github.com/mozzarellathicc/attcerts)

## Install wpa_supplicant
SSH into your UXG-Lite. It runs Debian, so we can install the `wpasupplicant` package.
```
apt-get install wpasupplicant
```

## Copy certs and config to UXG-Lite
Prepare your files on your computer to copy into the UXG-Lite

These files come from the mfg_dat_decode tool:
- CA_XXXXXX-XXXXXXXXXXXXXX.pem
- Client_XXXXXX-XXXXXXXXXXXXXX.pem
- PrivateKey_PKCS1_XXXXXX-XXXXXXXXXXXXXX.pem
- wpa_supplicant.conf

```
scp *.pem <uxg-lite>:/etc/wpa_supplicant/certs
scp wpa_supplicant.conf <uxg-lite>:/etc/wpa_supplicant
```
> Note: Create the `certs` folder first if you need to.

Make sure in the `wpa_supplicant.conf` to modify the `ca_cert`, `client_cert` and `private_key` to absolute paths. In this case, prepend `/etc/wpa_supplicant/certs/` to the filename strings.

## Start wpa_supplicant

```
wpa_supplicant -B -i eth1 -D wired -c /etc/wpa_supplicant/wpa_supplicant.conf -f /var/log/wpa_supplicant.log
```
Breaking down this command...
- `-B` Runs it in the background
- `-i eth1` Specifies `eth1` (UXG-Lite WAN port) as the interface
- `-D wired` Specify driver type of `eth1`
- `-c <path-to>/wpa_supplicant.conf` The config file
- `-f <log file>` Specifies log file we can easily check logs

You should see the message `Successfully initialized wpa_supplicant` if everything is configured correctly.

## Setup network

In your Unifi console/dashboard, under `Settings` -> `Internet` -> `Primary (WAN1)` (or your WAN name if you renamed it), Enable `VLAN ID` and set it to `0`.
![Alt text](vlan0.png)

Now go unplug the ethernet cable from the ONT port on your ATT Gateway, and plug it into the WAN port on your UXG-Lite.

Maybe restart your UXG-Lite too, I don't really know if this was necessary.

Back to SSH in the UXG-Lite, check the wpa_supplicant logs to see what happens.
```
tail -n 100 -f /var/log/wpa_supplicant.log
```

If you see something like this, then it was successful!
```
eth1: CTRL-EVENT-EAP-PEER-CERT depth=0 subject='/C=US/ST=Michigan/L=Southfield/O=ATT Services Inc/OU=OCATS/CN=aut03lsanca.lsanca.sbcglobal.net' hash=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
eth1: CTRL-EVENT-EAP-PEER-ALT depth=0 DNS:aut03lsanca.lsanca.sbcglobal.net
eth1: CTRL-EVENT-EAP-SUCCESS EAP authentication completed successfully
eth1: CTRL-EVENT-CONNECTED - Connection to XX:XX:XX:XX:XX:XX completed [id=0 id_str=]
```


## Spoof mac address
I'm actually not sure if this is required. But if you are unable to authenticate, then try this.
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