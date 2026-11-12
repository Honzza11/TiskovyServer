#!/usr/bin/env bash
# scan2email.sh - naskenuje dokument, vytvori PDF a posle ho e-mailem.
#
# Pipeline:  scanimage (SANE)  ->  obrazky stranek  ->  img2pdf  ->  [ocrmypdf]  ->  s-nail -> msmtp -> SMTP
#
# Nastaveni se cte z /etc/scan2email.conf (nebo ze souboru v $SCAN2EMAIL_CONF).
# Prepinace na prikazove radce maji prednost pred konfiguraci.

set -euo pipefail

CONF="${SCAN2EMAIL_CONF:-/etc/scan2email.conf}"
# shellcheck source=/dev/null
[[ -r "$CONF" ]] && source "$CONF"

# --- vychozi hodnoty (prepisuje konfigurace / prepinace) ---------------------
SCAN_DEVICE="${SCAN_DEVICE:-}"          # prazdne = prvni nalezeny skener; virtualni = "test"
SCAN_RESOLUTION="${SCAN_RESOLUTION:-200}"
SCAN_MODE="${SCAN_MODE:-}"              # napr. Color / Gray / Lineart (zavisi na skeneru!)
SCAN_SOURCE="${SCAN_SOURCE:-}"          # napr. Flatbed / ADF (zavisi na skeneru!)
SCAN_FORMAT="${SCAN_FORMAT:-jpeg}"      # jpeg = male PDF, png = bezeztratove
SCAN_BATCH="${SCAN_BATCH:-0}"           # 1 = skenovat vic stran z podavace (ADF)
SCAN_OCR="${SCAN_OCR:-0}"               # 1 = pridat textovou vrstvu (ocrmypdf), na RPi pomale
SCAN_OCR_LANG="${SCAN_OCR_LANG:-ces+eng}"
SCAN_ARCHIVE="${SCAN_ARCHIVE:-$HOME/scans}"
MAIL_TO="${MAIL_TO:-}"
MAIL_FROM="${MAIL_FROM:-}"
MAIL_SUBJECT="${MAIL_SUBJECT:-Sken}"
SEND_MAIL=1

usage() {
    cat <<EOF
Pouziti: $(basename "$0") [volby]
  -t ADRESA     prijemce e-mailu (vychozi: MAIL_TO z $CONF)
  -d ZARIZENI   SANE zarizeni (viz 'scanimage -L'), napr. "test" pro virtualni skener
  -r DPI        rozliseni (vychozi $SCAN_RESOLUTION)
  -m REZIM      barevny rezim skeneru (Color/Gray/Lineart...)
  -b            davkove skenovani z podavace (ADF)
  -O            zapnout OCR (prohledavatelne PDF)
  -n            neposilat e-mail, jen vytvorit PDF (test)
  -h            napoveda
Vysledne PDF se vzdy ulozi do $SCAN_ARCHIVE a jeho cesta se vypise na stdout.
EOF
}

while getopts ":t:d:r:m:bOnh" opt; do
    case "$opt" in
        t) MAIL_TO="$OPTARG" ;;
        d) SCAN_DEVICE="$OPTARG" ;;
        r) SCAN_RESOLUTION="$OPTARG" ;;
        m) SCAN_MODE="$OPTARG" ;;
        b) SCAN_BATCH=1 ;;
        O) SCAN_OCR=1 ;;
        n) SEND_MAIL=0 ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

log() { echo "[scan2email] $*" >&2; }
die() { log "CHYBA: $*"; exit 1; }

for cmd in scanimage img2pdf; do
    command -v "$cmd" >/dev/null || die "chybi program '$cmd' (spust install.sh)"
done
if [[ "$SEND_MAIL" == 1 ]]; then
    [[ -n "$MAIL_TO" ]] || die "neni zadan prijemce (-t nebo MAIL_TO v $CONF)"
    command -v s-nail >/dev/null || die "chybi program 's-nail'"
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- 1) skenovani ------------------------------------------------------------
scan_args=(--format="$SCAN_FORMAT" --resolution "$SCAN_RESOLUTION")
[[ -n "$SCAN_DEVICE" ]] && scan_args+=(-d "$SCAN_DEVICE")
[[ -n "$SCAN_MODE"   ]] && scan_args+=(--mode "$SCAN_MODE")
[[ -n "$SCAN_SOURCE" ]] && scan_args+=(--source "$SCAN_SOURCE")

ext="$SCAN_FORMAT"; [[ "$ext" == jpeg ]] && ext=jpg

log "skenuji (zarizeni: ${SCAN_DEVICE:-auto}, ${SCAN_RESOLUTION} DPI)..."
if [[ "$SCAN_BATCH" == 1 ]]; then
    # scanimage skonci s chybou "Document feeder out of documents", kdyz dojdou stranky - to je OK
    scanimage "${scan_args[@]}" --batch="$WORKDIR/page%03d.$ext" || true
else
    scanimage "${scan_args[@]}" > "$WORKDIR/page001.$ext" || die "skenovani selhalo"
fi

shopt -s nullglob
pages=("$WORKDIR"/page*."$ext")
(( ${#pages[@]} > 0 )) && [[ -s "${pages[0]}" ]] || die "skener nevratil zadnou stranku"
log "naskenovano stran: ${#pages[@]}"

# --- 2) prevod na PDF ----------------------------------------------------------
mkdir -p "$SCAN_ARCHIVE"
PDF="$SCAN_ARCHIVE/sken_$(date +%Y-%m-%d_%H-%M-%S).pdf"
img2pdf --pagesize A4 --imgsize "${SCAN_RESOLUTION}dpi" -o "$PDF" "${pages[@]}" \
    || img2pdf -o "$PDF" "${pages[@]}" || die "vytvoreni PDF selhalo"

if [[ "$SCAN_OCR" == 1 ]]; then
    if command -v ocrmypdf >/dev/null; then
        log "OCR ($SCAN_OCR_LANG)..."
        ocrmypdf -q -l "$SCAN_OCR_LANG" "$PDF" "$PDF" || log "OCR selhalo, posilam PDF bez textu"
    else
        log "ocrmypdf neni nainstalovany, OCR preskakuji"
    fi
fi
log "PDF: $PDF ($(du -h "$PDF" | cut -f1))"

# --- 3) odeslani e-mailem -------------------------------------------------------
if [[ "$SEND_MAIL" == 1 ]]; then
    log "odesilam na $MAIL_TO..."
    from_args=()
    [[ -n "$MAIL_FROM" ]] && from_args=(-r "$MAIL_FROM")
    printf 'Dobry den,\n\nv priloze je naskenovany dokument (%s stran).\n\n-- tiskovy server %s\n' \
        "${#pages[@]}" "$(hostname)" \
      | s-nail -S sendwait -s "$MAIL_SUBJECT $(date '+%d.%m.%Y %H:%M')" -a "$PDF" "${from_args[@]}" "$MAIL_TO" \
      || die "odeslani e-mailu selhalo (zkontroluj ~/.msmtprc a ~/.msmtp.log)"
    log "odeslano"
fi

echo "$PDF"
