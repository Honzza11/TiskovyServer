#!/usr/bin/env bash
# install.sh - nainstaluje a nastavi tiskovy a skenovaci server na Raspberry Pi OS.
# Spoustej:  sudo ./scripts/install.sh
# Skript muzes pustit opakovane, nic nerozbije.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Spust pres sudo: sudo $0"; exit 1; }
TARGET_USER="${SUDO_USER:-pi}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/5 Instalace balicku"
apt-get update
apt-get install -y \
    cups cups-bsd cups-client avahi-daemon \
    printer-driver-gutenprint printer-driver-hpcups hplip \
    printer-driver-brlaser printer-driver-splix printer-driver-foo2zjs foomatic-db-compressed-ppds \
    sane-utils sane-airscan libsane1 \
    img2pdf ocrmypdf tesseract-ocr-ces \
    msmtp msmtp-mta s-nail ca-certificates \
    python3-flask python3-waitress

echo "==> 2/5 Opravneni uzivatele $TARGET_USER"
# lpadmin = smi spravovat tiskarny v CUPS, scanner = smi pouzivat USB skener
usermod -aG lpadmin,scanner,lp "$TARGET_USER"

echo "==> 3/5 Sdileni tiskaren v siti (CUPS)"
systemctl enable --now cups avahi-daemon
# --remote-any:   CUPS posloucha i na siti, ne jen na localhostu
# --share-printers: tiskarny se ohlasuji pres Bonjour/mDNS (AirPrint, IPP Everywhere, Mopria)
# --remote-admin: webova sprava http://<rpi>:631 i z PC (prihlaseni uzivatelem z lpadmin)
cupsctl --remote-any --share-printers --remote-admin

echo "==> 4/5 Skript scan2email"
install -m 755 "$REPO/scripts/scan2email.sh" /usr/local/bin/scan2email.sh
if [[ ! -f /etc/scan2email.conf ]]; then
    sed "s#/home/pi#/home/$TARGET_USER#" "$REPO/config/scan2email.conf.example" > /etc/scan2email.conf
    chmod 644 /etc/scan2email.conf
    echo "    -> vytvoren /etc/scan2email.conf, UPRAV v nem MAIL_TO a MAIL_FROM"
fi
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ ! -f "$HOME_DIR/.msmtprc" ]]; then
    install -m 600 -o "$TARGET_USER" -g "$TARGET_USER" "$REPO/config/msmtprc.example" "$HOME_DIR/.msmtprc"
    echo "    -> vytvoren $HOME_DIR/.msmtprc, DOPLN v nem e-mail a heslo aplikace"
fi

echo "==> 5/5 Webove rozhrani pro skenovani (port 8080)"
install -d /opt/scan-web
install -m 644 "$REPO/web/app.py" /opt/scan-web/app.py
sed "s/__USER__/$TARGET_USER/" "$REPO/config/scan-web.service" > /etc/systemd/system/scan-web.service
systemctl daemon-reload
systemctl enable --now scan-web

IP="$(hostname -I | awk '{print $1}')"
cat <<EOF

Hotovo.
  Sprava tiskaren (CUPS): https://$IP:631   (nebo https://$(hostname).local:631)
  Skenovani z mobilu/PC:  http://$IP:8080
Dalsi krok: bez skutecneho hardwaru spust  sudo ./scripts/enable-virtual-devices.sh
Zmena skupin se projevi az po novem prihlaseni (nebo restartu).
EOF
