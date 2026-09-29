# =============================================================
#  █████╗ ██╗   ██╗██████╗ ██╗
# ██╔══██╗██║   ██║██╔══██╗██║
# ███████║██║   ██║██████╔╝██║
# ██╔══██║██║   ██║██╔══██╗██║
# ██║  ██║╚██████╔╝██████╔╝███████╗
# ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
#  aura — utilidades comunes
# =============================================================
#  Author: aura (para bspwm / X11)
#  Basado en la idea de Aura (Wayland layer-shell) pero para X11:
#  la "capa de fondo" se emula con una ventana _NET_WM_WINDOW_TYPE_DESKTOP
#  envuelta en xwinwrap, que bspwm ignora por completo y picom coloca
#  por debajo de todo (gracias a _NET_WM_STATE_BELOW).
# =============================================================

[[ -n ${_AURA_UTIL_SH:-} ]] && return 0
_AURA_UTIL_SH=1

# ── Rutas ────────────────────────────────────────────────────
AURA_HOME=${AURA_HOME:-$HOME/.config/aura}
AURA_RUNTIME=${XDG_RUNTIME_DIR:-/tmp}/aura-$UID
AURA_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/aura
AURA_CONF=$AURA_HOME/aura.conf
AURA_BIN_DIR=$AURA_HOME/bin
AURA_LIB=$AURA_HOME/lib

aura_init_dirs() {
    mkdir -p "$AURA_RUNTIME" "$AURA_CACHE" || return 1
    chmod 700 "$AURA_RUNTIME" 2>/dev/null
    return 0
}

# ── Log ──────────────────────────────────────────────────────
aura_quiet() { [[ ${AURA_QUIET:-0} == 1 ]]; }

aura_log() {
    aura_quiet && return 0
    printf '\033[38;5;141maura\033[0m %s\n' "$*" >&2
}

aura_warn() {
    printf '\033[38;5;215maura\033[0m %s\n' "$*" >&2
}

aura_err() {
    printf '\033[38;5;203maura\033[0m %s\n' "$*" >&2
}

aura_die() {
    aura_err "$*"
    exit 1
}

aura_have() { command -v "$1" >/dev/null 2>&1; }

aura_need() {
    local missing=()
    for dep in "$@"; do
        aura_have "$dep" || missing+=("$dep")
    done
    ((${#missing[@]})) && aura_die "faltan dependencias: ${missing[*]}"
    return 0
}

# ── Notificaciones ───────────────────────────────────────────
aura_notify() {
    local icon=${AURA_ICON:-🎬} title=$1; shift
    aura_have notify-send || return 0
    notify-send -a aura -i "$icon" -t 2600 -h string:x-canonical-private-synchronous:false \
        "aura · $title" "$*" >/dev/null 2>&1 &
}

# ── Monitores ────────────────────────────────────────────────
# Imprime "NOMBRE WxH+X+Y" por monitor habilitado (de xrandr).
# xrandr --listmonitors da:  " 0: +*HDMI-0 1360/1600x768/900+0+0  HDMI-0"
# es decir WIDTHpx/WIDTHmmxHEIGHTpx/HEIGHTmm+X+Y, y solo interested el +.
aura_monitors() {
    xrandr --listmonitors 2>/dev/null |
        sed -nE 's/^[[:space:]]+[0-9]+:[[:space:]]+\+\*?([A-Za-z0-9_-]+)[[:space:]]+([0-9]+)\/[0-9]+x([0-9]+)\/[0-9]+(([+-][0-9]+){2}).*/\1 \2x\3\4/p'
}

#IMARY -> geometria del monitor enfocado
aura_primary_monitor() {
    xrandr --listmonitors 2>/dev/null |
        sed -nE 's/^[[:space:]]+[0-9]+:[[:space:]]+\+\*([A-Za-z0-9_-]+)[[:space:]]+([0-9]+)\/[0-9]+x([0-9]+)\/[0-9]+(([+-][0-9]+){2}).*/\1 \2x\3\4/p'
}

# Lista simple de nombres de monitor
aura_monitor_names() { aura_monitors | cut -d' ' -f1; }

# Solo la geometria del monitor enfocado (WxH+X+Y)
aura_primary_geo() { aura_primary_monitor | cut -d' ' -f2-; }

# Monitor del que sale el tema: el primario y, si no hay ninguno marcado o su
# motor esta muerto, el primero que este en marcha. Con varios monitores cada
# uno puede tener su fondo, asi que "el primero de la lista de xrandr" NO es lo
# mismo que "el que estas viendo", y el acento tiene que salir del segundo.
aura_theme_source_monitor() {
    local mon
    mon=$(aura_primary_monitor | cut -d' ' -f1)
    if [[ -n $mon ]] && aura_engine_alive "$mon"; then
        printf '%s' "$mon"
        return 0
    fi
    while read -r mon _; do
        aura_engine_alive "$mon" && { printf '%s' "$mon"; return 0; }
    done < <(aura_monitors)
    aura_monitor_names | head -1
}

# ── Estado ───────────────────────────────────────────────────
# Un archivo por monitor: $AURA_RUNTIME/wall-$MON.{pid,file,paused}
aura_state_file() { printf '%s/wall-%s.%s' "$AURA_RUNTIME" "$1" "$2"; }

aura_get_state() {
    local mon=$1 key=$2 f
    f=$(aura_state_file "$mon" "$key")
    [ -f "$f" ] && cat "$f"
}

aura_set_state() {
    local mon=$1 key=$2
    aura_init_dirs || return 1
    printf '%s\n' "$3" > "$(aura_state_file "$mon" "$key")"
}

aura_del_state() { rm -f "$(aura_state_file "$1" "$2")"; }

# Monitores que tienen algo en el runtime, aunque ya no existan en xrandr.
# Al desconectar un monitor desaparece de aura_monitors, asi que recorrer solo
# esa lista deja su mpv huérfano y su estado zombi para siempre.
# Se mira cualquier wall-<MON>.<clave>, no solo el .pid: si el pid ya se perdio
# (sesion vieja, kill a medias) pero quedan geo/paused, ese monitor tiene que
# seguir siendo visible o sus restos no se limpian nunca.
aura_state_monitors() {
    local f
    for f in "$AURA_RUNTIME"/wall-*.*; do
        [[ -e $f ]] || continue
        f=${f##*/wall-}
        printf '%s\n' "${f%.*}"
    done | sort -u
}

# Borra TODO el estado de un monitor (pid, geo, file, paused).
aura_del_monitor_state() { rm -f "$AURA_RUNTIME"/wall-"$1".*; }

# El PID de xwinwrap (o mpv) del fondo de un monitor esta vivo?
aura_alive() { [[ -n ${1:-} ]] && kill -0 "$1" 2>/dev/null; }

# ── Procesos ─────────────────────────────────────────────────
# PGID de un pid (/proc/<pid>/stat, campo pgrp)
aura_pgid() {
    local pid=${1:-} stat rest
    [[ -r /proc/$pid/stat ]] || return 1
    stat=$(<"/proc/$pid/stat")
    rest=${stat##*') '}
    # tras el comm quedan: state ppid pgrp session ...
    awk '{print $3}' <<<"$rest"
}

# Matar un proceso y su grupo entero, sin tocar jamas nuestro propio grupo
# (los procesos de aura se lanzan con setsid, asi que grupo == xwinwrap+mpv)
aura_kill_tree() {
    local pid=${1:-} sig=${2:-TERM} pgid mine
    [[ -n $pid ]] || return 1
    mine=$(aura_pgid $$)
    pgid=$(aura_pgid "$pid")
    if [[ -n $pgid && $pgid -gt 1 && $pgid != "$mine" && $pgid != $$ ]]; then
        kill -"$sig" -- "-$pgid" 2>/dev/null && return 0
    fi
    kill -"$sig" "$pid" 2>/dev/null
}

# Pids de los procesos del fondo de un monitor (xwinwrap + mpv)
aura_wall_pids() {
    local mon=$1 p
    for p in $(pgrep -f -- "--title=aura-wallpaper-$mon" 2>/dev/null); do
        printf '%s\n' "$p"
    done
}

# ── Bloqueo de instancia unica ───────────────────────────────
aura_daemon_running() { aura_alive "$(cat "$AURA_RUNTIME/guard.pid" 2>/dev/null)"; }

# ── Foco ─────────────────────────────────────────────────────
# El menu del switcher es modal y ademas abre una preview que bspwm
# gestiona como cliente flotante (y le da el foco). Sin guardar y
# restaurar, al cerrarse rofi el foco cae en la preview, que ya esta
# muerta, y el teclado se queda colgando.
aura_focus_save() {
    local f name
    f=$(xdotool getwindowfocus 2>/dev/null) || f=
    # la ventana del fondo (aura-wallpaper-*) no es un sitio util
    # donde devolver el foco: no se le puede escribir
    if [[ -n $f ]]; then
        name=$(xdotool getwindowname "$f" 2>/dev/null)
        [[ $name == aura-wallpaper-* ]] && f=
    fi
    printf '%s\n' "${f:-}" >"$AURA_RUNTIME/focus.saved"
    aura_have bspc || return 0
    bspc query -T -n 2>/dev/null | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1 \
        >"$AURA_RUNTIME/focus.node"
}

aura_focus_restore() {
    local wid node
    aura_init_dirs || return 0
    [[ -f $AURA_RUNTIME/focus.saved ]] || return 0
    wid=$(<"$AURA_RUNTIME/focus.saved")
    rm -f "$AURA_RUNTIME/focus.saved" "$AURA_RUNTIME/focus.node"

    # 1) si la ventana de antes sigue viva, la recuperamos
    if [[ -n $wid ]] && xdotool getwindowname "$wid" >/dev/null 2>&1; then
        xdotool windowactivate --sync "$wid" 2>/dev/null
        [[ $(xdotool getwindowfocus 2>/dev/null) == "$wid" ]] && return 0
    fi

    # 2) si no, devolvemos el nodo que tenia bspwm enfocado (por si la
    #    ventana cambio pero el nodo sigue). Nada de esto es imprescindible
    #    para el menu: es solo para no dejar el teclado en el limbo.
    [[ -r $AURA_RUNTIME/focus.node ]] || return 0
    node=$(<"$AURA_RUNTIME/focus.node")
    [[ -n $node ]] || return 0
    bspc node -f "@$node" 2>/dev/null
    return 0
}

# ── Utilidades varias ────────────────────────────────────────
# Primer frame de un archivo como pixeles RGB24 (32x32) en stdout
aura_frame_rgb() {
    local file=$1 t=${2:-0} tmp
    [ -f "$file" ] || return 1
    aura_init_dirs
    tmp=$AURA_CACHE/.frame.$$
    rm -f "$tmp"
    if [[ $t != 0 ]] && ffmpeg -hide_banner -loglevel error -ss "$t" -i "$file" \
        -frames:v 1 -vf 'scale=32:32:flags=area,format=rgb24' -f rawvideo - \
        >"$tmp" 2>/dev/null && [[ -s $tmp ]]; then
        cat "$tmp"
    else
        # imagen fija o video mas corto que el offset: sin seek
        ffmpeg -hide_banner -loglevel error -i "$file" \
            -frames:v 1 -vf 'scale=32:32:flags=area,format=rgb24' -f rawvideo - \
            >"$tmp" 2>/dev/null
        cat "$tmp"
    fi
    rm -f "$tmp"
}

# Duracion en segundos (0 si es imagen)
aura_duration() {
    local file=$1
    ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 \
        "$file" 2>/dev/null | head -1
}

aura_is_video() {
    case ${1,,} in
        *.mp4|*.mkv|*.webm|*.avi|*.mov|*.m4v|*.flv|*.wmv|*.mpg|*.mpeg|*.gif) return 0 ;;
        *) return 1 ;;
    esac
}

aura_is_image() {
    case ${1,,} in
        *.jpg|*.jpeg|*.png|*.webp|*.bmp|*.jpg.xz|*.avif|*.jxl) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Tema de la rice activa (para integrar con gh0stzk/dotfiles)
aura_rice() {
    local f=$HOME/.config/bspwm/.rice
    [ -r "$f" ] && cat "$f"
}

# Lee una variable del theme-config.bash de la rice activa
aura_rice_var() {
    local name=$1 rice cfg
    rice=$(aura_rice) || return 1
    cfg=$HOME/.config/bspwm/rices/$rice/theme-config.bash
    [ -r "$cfg" ] || return 1
    # shellcheck disable=SC2016
    ( set -a; . "$cfg" >/dev/null 2>&1; printf '%s' "${!name-}" )
}
