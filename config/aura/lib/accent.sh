# =============================================================
#  █████╗ ██╗   ██╗██████╗ ██╗
# ██╔══██╗██║   ██║██╔══██╗██║
# ███████║██║   ██║██████╔╝██║
# ██╔══██║██║   ██║██╔══██╗██║
# ██║  ██║╚██████╔╝██████╔╝███████╗
# ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
#  aura — auto-theming: color dominante del video -> tu rice
# =============================================================
#
#  No toca theme-config.bash (tu RiceSelector manda sobre el tema).
#  Escribe en los archivos GENERADOS por tus modulos y avisa por señal
#  a cada app, exactamente igual que hacen tus scripts 04-*/05-*.
#  `aura theme --reset` restaura los colores de la rice.
# =============================================================

[[ -n ${_AURA_ACCENT_SH:-} ]] && return 0
_AURA_ACCENT_SH=1

AURA_PALETTE_FILE=$AURA_RUNTIME/accent
AURA_PALETTE_HIST=$AURA_CACHE/accent-history
AURA_BACKUP_DIR=$AURA_CACHE/backup

# ── Copias de seguridad ──────────────────────────────────────
# Antes de tocar un archivo generado por tus modulos guardamos como
# estaba, para que 'aura theme --reset' lo deje exactamente igual.
# La copia se hace una sola vez (la primera) y se tira entera cuando
# cambias de rice.
aura_backup() {
    local f=$1 k
    [[ -f $f ]] || return 1
    mkdir -p "$AURA_BACKUP_DIR" || return 1
    k=$(printf '%s' "$f" | md5sum | cut -c1-16)
    [[ -f $AURA_BACKUP_DIR/$k.orig ]] || cp -f "$f" "$AURA_BACKUP_DIR/$k.orig"
    return 0
}

aura_restore() {
    local f=$1 k
    [[ -f $f ]] || return 0
    k=$(printf '%s' "$f" | md5sum | cut -c1-16)
    [[ -f $AURA_BACKUP_DIR/$k.orig ]] && cp -f "$AURA_BACKUP_DIR/$k.orig" "$f"
    return 0
}

# El acento de una rice no se puede arrastrar a otra
aura_backup_new_rice() {
    local rice
    rice=$(aura_rice)
    mkdir -p "$AURA_BACKUP_DIR"
    if [[ -r $AURA_BACKUP_DIR/rice && $(<"$AURA_BACKUP_DIR/rice") != "$rice" ]]; then
        rm -f "$AURA_BACKUP_DIR"/*.orig
    fi
    printf '%s' "$rice" >"$AURA_BACKUP_DIR/rice"
}

# Ficheros generados por tus modulos, uno por objetivo
aura_theme_file() {
    case $1 in
        rofi) printf '%s' "$HOME/.config/bspwm/config/rofi-themes/shared.rasi" ;;
        dunst) printf '%s' "$HOME/.config/dunst/dunstrc.d/theme.conf" ;;
        kitty) printf '%s' "$HOME/.config/kitty/current-theme.conf" ;;
        ghostty) printf '%s' "$HOME/.config/ghostty/themes/gh0stzk" ;;
        mpv) printf '%s' "$HOME/.config/mpv/script-opts/modernz.conf" ;;
        polybar)
            local rice
            rice=$(aura_rice)
            [[ -n $rice ]] && printf '%s' "$HOME/.config/bspwm/rices/$rice/config.ini"
            ;;
    esac
}

# ── Muestreo ─────────────────────────────────────────────────
# Devuelve un bloque "clave=valor" con el acento del archivo indicado.
#   accent_sample <archivo> [segundo_de_referencia]
aura_accent_sample() {
    local file=$1 at=${2:-} prev= palette
    [[ -f $file ]] || return 1
    aura_need ffmpeg python3

    # si es video y nos pasan una posicion,.sampleamos ahi (el acento sigue
    # la escena que se esta viendo, no un frame fijo)
    if [[ -n $at && $at != 0 ]] && aura_is_video "$file"; then
        :
    else
        at=${AURA_FRAME_TIME:-2}
    fi

    [[ -r $AURA_PALETTE_FILE ]] && prev=$(grep -oE 'accent=#[0-9A-Fa-f]{6}' "$AURA_PALETTE_FILE" | cut -d= -f2)

    palette=$(aura_frame_rgb "$file" "$at" | python3 "$AURA_BIN_DIR/accent.py" \
        ${prev:+--prev "$prev"} --smooth "${AURA_SMOOTH:-40}" 2>/dev/null) || return 1
    [[ -n $palette ]] || return 1

    # validar que el bloque tiene todo lo esperado (va todo en una linea)
    local key
    for key in accent dim bright on text; do
        grep -qE "(^|[[:space:]])$key=#[0-9A-Fa-f]{6}" <<<"$palette" || return 1
    done
    printf '%s\n' "$palette"
}

# Aplica el acento a los objetivos configurados
#   theme_apply [<archivo>] [etiqueta]
aura_theme_apply() {
    local file=${1:-} label=${2:-Aura} palette
    [[ -n $THEME_TARGETS && $THEME_TARGETS != 0 ]] || return 0
    if [[ -z $file ]]; then
        local mon
        mon=$(aura_theme_source_monitor)
        file=$(aura_get_state "$mon" file)
    fi
    [[ -n $file && -f $file ]] || return 1
    palette=$(aura_accent_sample "$file") || return 1
    aura_theme_write "$palette"
    # historial corto por si quieres ver la evolucion
    printf '%s %s\n' "$(date +%H:%M:%S)" "$(grep -oE 'accent=#[0-9A-Fa-f]{6}' <<<"$palette")" \
        >>"$AURA_PALETTE_HIST"
    tail -n 40 "$AURA_PALETTE_HIST" >"$AURA_PALETTE_HIST.tmp" 2>/dev/null &&
        mv -f "$AURA_PALETTE_HIST.tmp" "$AURA_PALETTE_HIST"
    [[ -n $label ]] && aura_log "acento $label -> ${palette%% *}"
    return 0
}

# Escribe la paleta y la propaga
aura_theme_write() {
    local palette=$1
    aura_init_dirs || return 1
    printf '%s\n' "$palette" >"$AURA_PALETTE_FILE"
    aura_backup_new_rice

    # variables para el hook del usuario
    local accent dim bright on text
    accent=$(grep -oE 'accent=#[0-9A-Fa-f]{6}' <<<"$palette" | cut -d= -f2)
    dim=$(grep -oE 'dim=#[0-9A-Fa-f]{6}' <<<"$palette" | cut -d= -f2)
    bright=$(grep -oE 'bright=#[0-9A-Fa-f]{6}' <<<"$palette" | cut -d= -f2)
    on=$(grep -oE 'on=#[0-9A-Fa-f]{6}' <<<"$palette" | cut -d= -f2)
    text=$(grep -oE 'text=#[0-9A-Fa-f]{6}' <<<"$palette" | cut -d= -f2)
    export AURA_ACCENT=$accent AURA_ACCENT_DIM=$dim AURA_ACCENT_BRIGHT=$bright
    export AURA_ACCENT_ON=$on AURA_ACCENT_TEXT=$text
    printf 'export AURA_ACCENT=%s\nexport AURA_ACCENT_DIM=%s\nexport AURA_ACCENT_BRIGHT=%s\nexport AURA_ACCENT_ON=%s\nexport AURA_ACCENT_TEXT=%s\n' \
        "$accent" "$dim" "$bright" "$on" "$text" >"$AURA_RUNTIME/accent.env"

    local target
    for target in $THEME_TARGETS; do
        case $target in
            bspwm) theme_bspwm "$accent" "$dim" ;;
            polybar) theme_polybar "$accent" ;;
            rofi) theme_rofi "$accent" ;;
            dunst) theme_dunst "$accent" ;;
            kitty) theme_kitty "$accent" ;;
            ghostty) theme_ghostty "$accent" "$dim" ;;
            mpv) theme_mpv "$accent" "$dim" ;;
            *) aura_warn "objetivo de tema desconocido: $target" ;;
        esac
    done

    # hook del usuario (fuente opcional para lo que no cubrimos)
    [[ -x $AURA_HOME/aura-theme.sh ]] && "$AURA_HOME/aura-theme.sh" >/dev/null 2>&1
    return 0
}

# ── Objetivos ────────────────────────────────────────────────
# bspwm: bordes de ventana (efecto inmediato, sin recargar nada)
theme_bspwm() {
    local accent=$1 dim=$2
    aura_have bspc || return 0
    bspc config focused_border_color "$accent" 2>/dev/null
    bspc config normal_border_color "$dim" 2>/dev/null
    bspc config presel_feedback_color "$accent" 2>/dev/null
    return 0
}

# polybar: retocamos la seccion [color] del config de la rice y recargamos
theme_polybar() {
    local accent=${1:-#5884d4}
    local rice cfg key line value alpha new
    new=${accent#\#}
    rice=$(aura_rice)
    [[ -n $rice ]] || return 0
    cfg=$HOME/.config/bspwm/rices/$rice/config.ini
    [[ -w $cfg ]] || return 0
    aura_backup "$cfg"

    for key in ${POLYBAR_KEYS:-bc}; do
        while IFS= read -r line; do
            # solo las lineas "clave = color" de nuestras claves
            [[ $line =~ ^[[:space:]]*${key}[[:space:]]*=(.*)$ ]] || {
                printf '%s\n' "$line"
                continue
            }
            value=${BASH_REMATCH[1]// /}
            alpha=
            # #B36272a4: los dos primeros digitos son el canal alfa y se
            # respetan, para no volver opaca la barra
            if [[ $value =~ ^#[[:xdigit:]]{8}$ ]]; then
                alpha=${value:1:2}      # los 2 digitos de alfa, sin la "#"
            fi
            printf '%s = #%s%s\n' "$key" "$alpha" "$new"
        done <"$cfg" >"$cfg.aura.$$" && mv -f "$cfg.aura.$$" "$cfg"
    done

    if aura_have polybar-msg && pgrep -x polybar >/dev/null 2>&1; then
        polybar-msg cmd reload >/dev/null 2>&1
    fi
    return 0
}

# rofi: el color "selected" vive en shared.rasi (lo regenera tu 04-rofi.sh)
theme_rofi() {
    local accent=$1
    local shared=$HOME/.config/bspwm/config/rofi-themes/shared.rasi
    [[ -w $shared ]] || return 0
    aura_backup "$shared"
    sed -i -E "s/^([[:space:]]*selected:[[:space:]]*).*/\1${accent};/" "$shared"
    return 0
}

# dunst: frame y color del titulo en el archivo que genera tu 04-dunst.sh
theme_dunst() {
    local accent=$1
    local f=$HOME/.config/dunst/dunstrc.d/theme.conf
    [[ -w $f ]] || return 0
    aura_backup "$f"
    sed -i -E "s/^(frame_color[[:space:]]*=[[:space:]]*).*/\1\"${accent}\"/" "$f"
    sed -i -E "s/foreground='#[0-9A-Fa-f]{6}'>%s/foreground='${accent}'>%s/" "$f"
    aura_have dunstctl && dunstctl reload >/dev/null 2>&1
    return 0
}

# kitty:Selection/borde + recarga con SIGUSR1 (igual que tu 05-kitty.sh)
theme_kitty() {
    local accent=$1
    local f=$HOME/.config/kitty/current-theme.conf
    [[ -w $f ]] || return 0
    aura_backup "$f"
    sed -i -E "s/^(selection_background[[:space:]]+).*/\1${accent}/" "$f"
    sed -i -E "s/^(active_border_color[[:space:]]+).*/\1${accent}/" "$f"
    pgrep -x kitty >/dev/null 2>&1 && pkill -USR1 -x kitty
    return 0
}

# ghostty: seleccion con acento y texto en el color apagado, recarga con SIGUSR2
theme_ghostty() {
    local accent=$1 dim=${2:-#000000}
    local f=$HOME/.config/ghostty/themes/gh0stzk
    [[ -w $f ]] || return 0
    aura_backup "$f"
    sed -i -E "s/^(selection-background[[:space:]]*=[[:space:]]*).*/\1${accent}/" "$f"
    sed -i -E "s/^(selection-foreground[[:space:]]*=[[:space:]]*).*/\1${dim}/" "$f"
    pgrep -x ghostty >/dev/null 2>&1 && pkill -USR2 -x ghostty
    return 0
}

# mpv: script modernz (OSC y barra de busqueda)
theme_mpv() {
    local accent=$1 dim=$2
    local f=$HOME/.config/mpv/script-opts/modernz.conf
    [[ -w $f ]] || return 0
    aura_backup "$f"
    sed -i -E "s/^(osc_color=).*/\1${dim}/" "$f"
    sed -i -E "s/^(seekbarfg_color=).*/\1${accent}/" "$f"
    return 0
}

# ── Reset ────────────────────────────────────────────────────
# Vuelca la ultima paleta guardada en los ficheros de los objetivos.
# Se usa cuando otro script regenera un fichero de los que toca aura
# (tu Theme.sh vuelve a correr 04-rofi.sh, por ejemplo): sin esto, el
# acento se perderia al cambiar de rice con el fondo puesto.
aura_theme_reapply() {
    local palette
    [[ -r $AURA_PALETTE_FILE ]] || return 1
    palette=$(<"$AURA_PALETTE_FILE")
    [[ -n $palette ]] || return 1
    aura_theme_write "$palette" || return 1
    aura_log "acento reaplicado -> ${palette%% *}"
    return 0
}

# ── Reset ────────────────────────────────────────────────────
# Devuelve cada objetivo al estado en que estaba antes del primer
# acento: los ficheros se restauran desde las copias que hace aura,
# y bspwm (que vive en memoria) se vuelve a poner con la rice.
aura_theme_reset() {
    local rice NORMAL_BC FOCUSED_BC blue target f
    rice=$(aura_rice)
    if [[ -n $rice ]]; then
        NORMAL_BC=$(aura_rice_var NORMAL_BC)
        FOCUSED_BC=$(aura_rice_var FOCUSED_BC)
        blue=$(aura_rice_var blue)
    fi
    NORMAL_BC=${NORMAL_BC:-#353c52}
    FOCUSED_BC=${FOCUSED_BC:-#353c52}
    blue=${blue:-#5884d4}

    for target in $THEME_TARGETS; do
        f=$(aura_theme_file "$target") || continue
        [[ -n $f ]] && aura_restore "$f"
    done

    aura_have bspc && {
        bspc config normal_border_color "$NORMAL_BC" 2>/dev/null
        bspc config focused_border_color "$FOCUSED_BC" 2>/dev/null
        bspc config presel_feedback_color "$blue" 2>/dev/null
    }
    aura_have polybar-msg && pgrep -x polybar >/dev/null 2>&1 && polybar-msg cmd reload >/dev/null 2>&1
    aura_have dunstctl && dunstctl reload >/dev/null 2>&1
    pgrep -x kitty >/dev/null 2>&1 && pkill -USR1 -x kitty
    pgrep -x ghostty >/dev/null 2>&1 && pkill -USR2 -x ghostty

    # El marcador del guard va en RUNTIME, no en CACHE: si se queda, el proximo
    # ciclo ve "el acento no ha cambiado" y el tema no vuelve a aplicarse
    # hasta que cambie el fondo.
    rm -f "$AURA_PALETTE_FILE" "$AURA_RUNTIME/accent.applied"
    aura_log "tema restaurado a los colores de la rice (${rice:-?})"
    return 0
}
