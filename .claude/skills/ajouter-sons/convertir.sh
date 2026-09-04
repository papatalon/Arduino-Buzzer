#!/usr/bin/env bash
# Convertit au standard de la banque les sons qui n'y sont pas encore.
#
# Detection : tout fichier de la bibliotheque dont le md5 differe de son
# homologue dans les assets de l'app (ou qui n'y existe pas). Ca attrape
# aussi bien un ajout qu'un remplacement en place, ce qu'une comparaison
# par nom de fichier raterait.
#
# Sortie : $SCRATCH/conv_new/<dossier>/<nom>.mp3, rien n'est ecrase.
#
# Usage :  bash convertir.sh [chemin/du/scratchpad]
#          bash convertir.sh --liste 01_Intro/018_foo 02_Buzzer/032_bar

set -uo pipefail

BIBLIO="/c/Users/MarcLindsay/OneDrive/Developpement/Arduino/Buzzer/sons/Bibliothèque"
ASSETS="D:/dev/Arduino/Buzzer/app/buzzer_companion/assets/sounds"
DOSSIERS="01_Intro 02_Buzzer 03_Good 04_Bad 05_Waiting 06_Divers"

FF=$(command -v ffmpeg || ls -d /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg*/*/bin/ffmpeg.exe 2>/dev/null | head -1)
FP="${FF%ffmpeg*}ffprobe${FF##*ffmpeg}"
[ -x "$FF" ] || { echo "ffmpeg introuvable. Installer : winget install Gyan.FFmpeg"; exit 1; }

# --- liste des fichiers a traiter -------------------------------------------
CIBLES=()
if [ "${1:-}" = "--liste" ]; then
  shift; CIBLES=("$@")
  SCRATCH="${SCRATCH:-$PWD/.moulinette}"
else
  SCRATCH="${1:-$PWD/.moulinette}"
  for d in $DOSSIERS; do
    for f in "$BIBLIO/$d"/*.mp3; do
      [ -e "$f" ] || continue
      b=$(basename "${f%.mp3}"); a="$ASSETS/$d/$b.mp3"
      if [ ! -f "$a" ] || [ "$(md5sum "$f" | cut -d' ' -f1)" != "$(md5sum "$a" | cut -d' ' -f1)" ]; then
        CIBLES+=("$d/$b")
      fi
    done
  done
fi

if [ ${#CIBLES[@]} -eq 0 ]; then
  echo "Rien a convertir : la bibliotheque et les assets sont deja identiques."
  exit 0
fi

W="$SCRATCH/wav_new"; C="$SCRATCH/conv_new"
rm -rf "$W" "$C"; mkdir -p "$W" "$C"

# Rognage du silence : le meme filtre sert aux deux bouts, applique une fois
# a l'endroit puis une fois a l'envers. ffmpeg n'a pas de filtre qui coupe
# la queue sans toucher aussi aux silences du milieu.
TRIM="silenceremove=start_periods=1:start_duration=0:start_threshold=-50dB:detection=peak"
AF="aformat=channel_layouts=mono,$TRIM,areverse,$TRIM,afade=t=in:st=0:d=0.005,areverse,afade=t=in:st=0:d=0.005,aresample=44100"

# Plafond de duree des buzzers. BUZZ_MAX_MS vaut 2000 dans Mp3.h ; la marge
# couvre le delai entre playFolder() et le premier echantillon sorti par le
# DFPlayer, pendant lequel le minuteur du firmware tourne deja.
BUZZ_CAP_S=1.90
BUZZ_FADE_S=0.030

printf "%-38s %8s %8s %9s %10s\n" "fichier" "avant" "apres" "rogne" "loudness"
printf '%.0s-' {1..78}; echo

for p in "${CIBLES[@]}"; do
  d="${p%%/*}"; b="${p##*/}"
  src="$BIBLIO/$d/$b.mp3"
  [ -f "$src" ] || { echo "ABSENT $p"; continue; }
  mkdir -p "$W/$d" "$C/$d"

  # Passe A : mono, rognage des deux bouts, fondus anti-clic, vers du WAV.
  # -vn est obligatoire : la majorite des fichiers telecharges portent une
  # pochette d'album, et ffmpeg refuse d'ecrire un MP3 sans ID3 tant qu'il
  # croit devoir la conserver.
  if ! "$FF" -hide_banner -loglevel error -y -i "$src" -map 0:a:0 -vn -af "$AF" \
       -c:a pcm_s16le -ar 44100 -ac 1 "$W/$d/$b.wav"; then
    echo "ECHEC passe A : $p"; continue
  fi

  # Plafond des buzzers. Le firmware coupe a BUZZ_MAX_MS avec un mp3.stop()
  # SEC, en plein milieu de la forme d'onde : sur un son soutenu ca claque.
  # On coupe donc ici, avec un fondu de sortie, pour que le fichier se termine
  # tout seul avant que le firmware n'ait a intervenir.
  #
  # La marge n'est pas cosmetique : le minuteur du firmware demarre a l'appel
  # de playFolder(), alors que le DFPlayer met quelques dizaines de ms a
  # sortir le premier echantillon. Sans marge, la fin du fichier tomberait
  # quand meme sous le stop().
  # Duree apres rognage mais avant plafonnement : c'est elle qui donne la
  # colonne « rogne », qu'il ne faut pas melanger avec la coupe a 2 s.
  dpre=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$W/$d/$b.wav")
  cap=""
  if [ "$d" = "02_Buzzer" ]; then
    if awk -v x="$dpre" -v c="$BUZZ_CAP_S" 'BEGIN{exit !(x>c)}'; then
      fst=$(awk -v c="$BUZZ_CAP_S" -v f="$BUZZ_FADE_S" 'BEGIN{printf "%.3f", c-f}')
      "$FF" -hide_banner -loglevel error -y -i "$W/$d/$b.wav" \
        -af "atrim=0:$BUZZ_CAP_S,asetpts=N/SR/TB,afade=t=out:st=$fst:d=$BUZZ_FADE_S" \
        -c:a pcm_s16le -ar 44100 -ac 1 "$W/$d/$b.capped.wav" \
        && mv "$W/$d/$b.capped.wav" "$W/$d/$b.wav"
      cap=" plafonne ${BUZZ_CAP_S}s"
    fi
  fi

  # 05_Waiting joue en fond pendant que les equipes reflechissent : l'aligner
  # sur les bruitages transformerait un tic d'horloge en buzzer.
  case "$d" in 05_Waiting) I=-20;; *) I=-16;; esac

  # Passe B : mesure sur le WAV deja rogne. Mesurer avant le rognage
  # fausserait le resultat, le silence comptant dans la loudness integree.
  j=$("$FF" -hide_banner -i "$W/$d/$b.wav" \
        -af "loudnorm=I=$I:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
  gv(){ echo "$j" | grep "\"$1\"" | sed 's/.*: "//; s/".*//'; }
  mi=$(gv input_i); mtp=$(gv input_tp); mlra=$(gv input_lra); mth=$(gv input_thresh)

  # Passe C : normalisation puis encodage. Un seul encodage lossy au bout.
  if [ "$mi" = "-inf" ]; then
    # Fichier trop court pour le gating EBU R128 : aucune loudness mesurable.
    # On l'aligne sur sa crete a la place, et on le signale pour ecoute.
    g=$(awk "BEGIN{printf \"%.2f\", -1.5-($mtp)}")
    post="volume=${g}dB"; note="repli crete ${g}dB"
  else
    post="loudnorm=I=$I:TP=-1.5:LRA=11:measured_I=$mi:measured_TP=$mtp:measured_LRA=$mlra:measured_thresh=$mth:linear=true,aresample=44100"
    note="$mi -> $I"
  fi
  "$FF" -hide_banner -loglevel error -y -i "$W/$d/$b.wav" -af "$post" \
    -c:a libmp3lame -b:a 128k -ac 1 -ar 44100 \
    -map_metadata -1 -id3v2_version 0 -write_xing 0 "$C/$d/$b.mp3" || { echo "ECHEC passe C : $p"; continue; }

  da=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$src")
  db=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$C/$d/$b.mp3")
  printf "%-38s %7.2fs %7.2fs %8.3fs %10s%s\n" "$b" "$da" "$db" "$(awk "BEGIN{print $da-$dpre}")" "$note" "$cap"
done

echo
echo "Converti dans : $C"
echo "Rien n'a ete ecrase. Ecouter avant de deployer."
