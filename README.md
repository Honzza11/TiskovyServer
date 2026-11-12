# TiskovyServer

Projekt na PSS: **Tiskový a skenovací server na Raspberry Pi.**

> Pomocí RPI udělejte server pro starou tiskárnu, abych mohl tisknout z PC a mobilu
> a scanovat a poslat si výsledek v PDF na e-mail.

## Architektura

```
 PC / mobil ──IPP (port 631)──►┌──────────── Raspberry Pi ────────────┐
   (AirPrint, Mopria,          │  avahi  ── ohlašuje tiskárnu v síti  │
    IPP Everywhere)            │  CUPS   ── fronta + ovladač ──USB──► │──► tiskárna
                               │                                      │
 PC / mobil ──HTTP (8080)─────►│  web/app.py (Flask)                  │
   "Skenovat a odeslat"        │     └► scan2email.sh                 │
                               │          scanimage (SANE) ◄──USB──── │◄── skener
                               │          img2pdf [+ ocrmypdf]        │
                               │          s-nail → msmtp ──SMTP──────►│──► Gmail/Seznam → e-mail
                               └──────────────────────────────────────┘
```

| Soubor | Účel |
|---|---|
| `scripts/install.sh` | instalace balíčků, sdílení tiskáren, služba webu |
| `scripts/enable-virtual-devices.sh` | virtuální tiskárna (cups-pdf) a virtuální skener (SANE `test`) pro testy bez hardwaru |
| `scripts/scan2email.sh` | sken → PDF → e-mail (lze pouštět i ručně) |
| `web/app.py` | webová stránka pro spuštění skenu z mobilu/PC |
| `config/scan2email.conf.example` | → `/etc/scan2email.conf` (skener, e-mail) |
| `config/msmtprc.example` | → `~/.msmtprc` (SMTP účet, heslo aplikace) |
| `config/scan-web.service` | systemd služba pro web |

> Nemáš Raspberry Pi? Prototyp ve VirtualBoxu: [docs/VIRTUALBOX.md](docs/VIRTUALBOX.md)

## Rychlý start

```bash
git clone <tento repozitář> && cd TiskovyServer
sudo ./scripts/install.sh                 # balíčky + konfigurace
sudo ./scripts/enable-virtual-devices.sh  # jen dokud nemám skutečný hardware
nano ~/.msmtprc                           # e-mail + heslo aplikace
sudo nano /etc/scan2email.conf            # MAIL_TO, MAIL_FROM
```

Testy:

```bash
echo "Ahoj" | lp -d VirtualPDF            # tisk → ~/PDF/
scan2email.sh -d test -n                  # sken → PDF, bez e-mailu
scan2email.sh -d test -t ja@example.com   # sken → PDF → e-mail
```

Web: `http://<ip-raspberry>:8080`, správa CUPS: `https://<ip-raspberry>:631`.

## Přechod na skutečný hardware

1. Ověř podporu modelu: tiskárna na <https://www.openprinting.org/printers>, skener na
   <http://www.sane-project.org/sane-supported-devices.html>.
2. Připoj USB, zkontroluj: `lsusb`, `lpinfo -v` (tiskárna), `scanimage -L` (skener).
3. Tiskárnu přidej ve webu CUPS (Administration → Add Printer, zaškrtni *Share This Printer*)
   nebo příkazem `lpadmin -p StaraTiskarna -E -v 'usb://…' -m <ovladač z lpinfo -m> -o printer-is-shared=true`.
4. Do `/etc/scan2email.conf` napiš `SCAN_DEVICE=` podle `scanimage -L` a uprav `SCAN_MODE`
   podle `scanimage -d "<zařízení>" --help`.
5. Virtuální tiskárnu můžeš smazat: `sudo lpadmin -x VirtualPDF`.
