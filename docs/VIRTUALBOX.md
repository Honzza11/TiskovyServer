# Prototype in VirtualBox (no Raspberry Pi needed)

The server runs in a virtual machine (VM) on your PC. Thanks to **bridged networking**
the VM gets its own IP address on your Wi-Fi, so to your phone and PC it looks
exactly like a Raspberry Pi plugged into the network. Later the same scripts run
unchanged on a real Pi.

Time: about 30–45 minutes (most of it is waiting for downloads).

## 1. Download

- **VirtualBox** – <https://www.virtualbox.org/wiki/Downloads> → "Windows hosts", install it.
- **Debian 13 netinst ISO** (amd64) – <https://www.debian.org/distrib/netinst> → "amd64", ~700 MB.

Raspberry Pi OS is also Debian 13 underneath, so everything behaves the same.

## 2. Create the VM

VirtualBox → **New**:

| Setting | Value |
|---|---|
| Name | `tiskarna` |
| ISO Image | the downloaded `debian-13.x.x-amd64-netinst.iso` |
| ☑ Skip Unattended Installation | **tick it** (you'll install by hand, you learn more) |
| Base Memory / Processors | 2048 MB / 2 CPUs |
| Hard Disk | 20 GB |

**Before starting it:** select the VM → **Settings → Network → Adapter 1**
→ *Attached to:* **Bridged Adapter** → *Name:* your **Wi-Fi card** (or Ethernet card, whichever your PC uses).

> Why: with the default *NAT* the VM is hidden behind your PC and your phone can't see it.
> *Bridged* puts it directly on your home network like a real device.

## 3. Install Debian

Start the VM → **Install** (the text one is fine). Answer:

- Language/location/keyboard: whatever you like.
- **Hostname:** `tiskarna`  · Domain: leave empty.
- **Root password: leave EMPTY** (press Enter twice). Your normal user then automatically gets `sudo`.
- Your name / username / password: e.g. `honza`.
- Partitioning: *Guided – use entire disk* → *All files in one partition* → *Yes*.
- **Software selection:** untick *Debian desktop environment* and *GNOME*,
  **tick *SSH server*** and *standard system utilities*.
- GRUB: *Yes*, on `/dev/sda`.

Reboot, log in. Find the VM's IP:

```bash
ip -4 addr | grep inet
```

You want an address like `192.168.x.x` – **the same range as your PC**. If you see `10.0.2.15`,
the network is still NAT (see Troubleshooting).

## 4. Connect from your PC over SSH (optional, but comfortable)

Copy-paste works much better than in the VM window. In Windows PowerShell:

```powershell
ssh honza@192.168.x.x
```

## 5. Install the server

```bash
sudo apt update && sudo apt install -y git
git clone -b ccr-60c3bdef-wvr1sj https://github.com/Honzza11/TiskovyServer
cd TiskovyServer
sudo ./scripts/install.sh
sudo ./scripts/enable-virtual-devices.sh
```

If the repo is private, git asks for a login: use your GitHub username and a
**personal access token** as the password (GitHub → Settings → Developer settings → Tokens).

Then fill in the e-mail settings (see the main README, step "E-mail"):

```bash
nano ~/.msmtprc                  # Gmail address + app password
sudo nano /etc/scan2email.conf   # MAIL_TO, MAIL_FROM
sudo systemctl restart scan-web
```

Log out and back in (`exit`, then ssh again) so the new groups (`lpadmin`, `scanner`) apply.

## 6. Test

On the VM:

```bash
lpstat -p                                  # VirtualPDF ... idle
echo "Ahoj" | lp -d VirtualPDF && ls ~/PDF # printing works
scan2email.sh -n                           # scan -> PDF (no e-mail)
scan2email.sh -t you@example.com           # scan -> PDF -> e-mail
```

From other devices (if `tiskarna.local` doesn't work, use the IP address):

| What | How |
|---|---|
| CUPS admin | `https://tiskarna.local:631` (accept the self-signed certificate warning) |
| Print from Windows | Settings → Bluetooth & devices → Printers & scanners → **Add device**. Not found? *Add manually* → *Select a shared printer by name* → `http://tiskarna.local:631/printers/VirtualPDF` |
| Print from Android | Settings → Connected devices → Printing → *Default Print Service* on → print from any app |
| Print from iPhone | Share → Print → the printer appears via AirPrint |
| Result of printing from PC/phone | on the VM: `ls /var/spool/cups-pdf/ANONYMOUS/` |
| Scan from phone/PC | `http://tiskarna.local:8080` → *Skenovat a odeslat* |

**Tip:** once everything works, take a snapshot (VM → *Snapshots → Take*). If you break
something while experimenting, you can roll back in seconds.

## Troubleshooting

| Problem | Fix |
|---|---|
| VM has `10.0.2.15`, phone can't see it | Network is NAT. Power off VM → Settings → Network → *Bridged Adapter*, pick the right card. |
| Bridged, but no IP / no internet | Some Wi-Fi networks (school, eduroam, hotels) block extra devices. Do it on your **home network** or a phone hotspot. |
| `tiskarna.local` not found | Use the IP. Windows/Android sometimes don't resolve `.local` names. |
| `apt` says *Unable to locate package X* | Remove that package from the list in `scripts/install.sh` and run it again (it's safe to rerun). |
| Web page shows an e-mail error | `cat ~/.msmtp.log` – usually a wrong app password. |
| Printer not visible on phone | Phone and VM must be on the same Wi-Fi; check `systemctl status avahi-daemon cups`. |

## Moving to a real Raspberry Pi later

Flash Raspberry Pi OS Lite (64-bit) onto your microSD card, then repeat **step 5** on the Pi.
Nothing else changes.
