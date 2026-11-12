#!/usr/bin/env bash
# enable-virtual-devices.sh - virtualni tiskarna a virtualni skener pro testovani BEZ hardwaru.
#
#  * Virtualni tiskarna "VirtualPDF" (cups-pdf): vse, co na ni vytisknes z PC/mobilu,
#    se ulozi jako PDF do /var/spool/cups-pdf/ANONYMOUS/. Pro sit vypada jako normalni tiskarna.
#  * Virtualni skener "test" (SANE backend test): misto skutecneho skenu vraci testovaci obrazec.
#
# Spoustej:  sudo ./scripts/enable-virtual-devices.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Spust pres sudo: sudo $0"; exit 1; }

echo "==> Virtualni tiskarna"
apt-get install -y printer-driver-cups-pdf
# Najdi PPD (popis "ovladace") pro cups-pdf - cesta se lisi podle verze systemu
MODEL="$(lpinfo -m 2>/dev/null | awk '/(CUPS-PDF|cups-pdf)/ {print $1; exit}')"
[[ -n "$MODEL" ]] || { echo "PPD pro cups-pdf nenalezeno"; exit 1; }
# -E = povolit tiskarnu,  -v = kam se posilaji data (URI),  -m = ovladac
lpadmin -p VirtualPDF -E -v cups-pdf:/ -m "$MODEL" \
        -D "Virtualni tiskarna (PDF)" -L "Raspberry Pi" \
        -o printer-is-shared=true
lpadmin -d VirtualPDF   # vychozi tiskarna
# Vystup do spolecne slozky (anonymni uloha ze site nema lokalniho uzivatele)
sed -i 's|^#\?\s*AnonDirName.*|AnonDirName /var/spool/cups-pdf/ANONYMOUS|' /etc/cups/cups-pdf.conf || true
systemctl restart cups

echo "==> Virtualni skener"
# Backend "test" je v /etc/sane.d/dll.conf ve vychozim stavu zakomentovany
sed -i 's/^#\s*test\s*$/test/' /etc/sane.d/dll.conf
grep -qx 'test' /etc/sane.d/dll.conf || echo test >> /etc/sane.d/dll.conf

echo
echo "Kontrola:"
lpstat -p VirtualPDF
scanimage -L | grep -i test || true
cat <<EOF

Test tisku:   echo "Ahoj z Raspberry" | lp -d VirtualPDF   -> ls ~/PDF  (z PC/mobilu: /var/spool/cups-pdf/ANONYMOUS/)
Test skenu:   scan2email.sh -d test -n                    -> vypise cestu k PDF
EOF
