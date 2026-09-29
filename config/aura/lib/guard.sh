# =============================================================
#  █████╗ ██╗   ██╗██████╗ ██╗
# ██╔══██╗██║   ██║██╔══██╗██║
# ███████║██║   ██║██████╔╝██║
# ██╔══██║██║   ██║██╔══██╗██║
# ██║  ██║╚██████╔╝██████╔╝███████╗
# ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
#  aura — guard: el daemon que hace inteligente al fondo
# =============================================================
#
#  Un solo proceso, todo en un bucle:
#    1. revive el fondo si alguien lo mata (cambio de rice, etc.)
#    2. pausa al detectar un juego en pantalla completa -> 0% GPU
#    3. pausa en bateria -> alargar la autonomia
#    4. se entera de monitores enchufados/desenchufados (hotplug)
#    5. muestrea el color dominante del video y propaga el tema
# =============================================================

[[ -n ${_AURA_GUARD_SH:-} ]] && return 0
_AURA_GUARD_SH=1

aura_guard_usage() {
    cat <<-EOF
	aura guard -- demonio del fondo (lo arranca 'aura --daemon')
	EOF
}

# ── Estado actual del motor ──────────────────────────────────
aura_guard_engine_alive() {
    local mon pid any=0
    while read -r mon _; do
        pid=$(aura_get_state "$mon" pid)
        if [[ -n $pid ]] && aura_alive "$pid" && [[ -S $(aura_engine_socket "$mon") ]]; then
            any=1
        else
            return 1
        fi
    done < <(aura_monitors)
    return $((1 - any))
}

# El juego de monitores y el de motores no cuadran: o hay un monitor en
# pantalla sin motor (monitor nuevo) o sobran motores de monitores que ya no
# estan. Las dos cosas exigen reconstruir entero.
# IMPORTANTE mirar tambien el segundo caso: si solo se mirase "falta motor",
# un motor huerfano (monitor desconectado mientras se reconstruia) se
# quedaria vivo para siempre, porque con todos los monitores sanos ni el
# watchdog ni el hotplug vuelven a mirar nada.
# 0 = desajuste (reconstruir), 1 = cuadra
aura_guard_desajuste() {
    local mon
    local -a en_pantalla con_estado
    mapfile -t en_pantalla < <(aura_monitor_names)
    mapfile -t con_estado  < <(aura_state_monitors)
    # 1) monitor en pantalla sin motor: no llega a existir monitor sin pid
    for mon in "${en_pantalla[@]}"; do
        [[ -n $mon ]] || continue
        [[ -e $AURA_RUNTIME/wall-$mon.pid ]] || return 0
    done
    # 2) estado de un monitor que no esta en pantalla: sobran motores
    for mon in "${con_estado[@]}"; do
        [[ -n $mon ]] || continue
        printf '%s\n' "${en_pantalla[@]}" | grep -qx "$mon" || return 0
    done
    return 1
}

# ── Pausa automatica ─────────────────────────────────────────
# Devuelve 0 si hay que pausar
aura_guard_should_pause() {
    local class
    (( ${AUTO_PAUSE:-1} )) || return 1

    if command -v bspc >/dev/null; then
        # 1) Pantalla completa nativa (instantaneo)
        bspc query -N -n focused.fullscreen >/dev/null 2>&1 && return 0
        
        # 2) Clases configuradas
        if [[ -n ${GAME_CLASSES:-} ]]; then
            class=$(xprop -id "$(bspc query -N -n focused 2>/dev/null)" WM_CLASS 2>/dev/null | sed -n 's/.*"\(.*\)", "\(.*\)"$/\1/p' | head -1)
            [[ -n $class ]] && grep -qiE "$GAME_CLASSES" <<<"$class" && return 0
        fi
        return 1
    fi

    local wid=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}')
    [[ -n $wid && $wid != 0x0 ]] || return 1
    local state=$(xprop -id "$wid" _NET_WM_STATE WM_CLASS 2>/dev/null)
    grep -q '_NET_WM_STATE_FULLSCREEN' <<<"$state" && return 0
    if [[ -n ${GAME_CLASSES:-} ]]; then
        class=$(sed -n 's/.*"\(.*\)", "\(.*\)"$/\1/p' <<<"$state" | head -1)
        [[ -n $class ]] && grep -qiE "$GAME_CLASSES" <<<"$class" && return 0
    fi
    return 1
}

aura_guard_pause_state() {
    local mon
    mon=$(aura_monitor_names | head -1)
    local v
    v=$("$AURA_BIN_DIR/aura-ipc" "$(aura_engine_socket "$mon")" --get pause 2>/dev/null)
    [[ $v == true ]] && echo 1 || echo 0
}

# ── Bateria (sin depender de acpi) ───────────────────────────
# 0 = descargando, 1 = cargando, 2 = sin bateria
aura_guard_battery() {
    local d status cap
    for d in /sys/class/power_supply/BAT*; do
        [[ -r $d/status ]] || continue
        status=$(<"$d/status")
        cap=$(<"$d/capacity" 2>/dev/null || echo 100)
        if [[ $status == Discharging ]]; then
            (( cap <= ${BATTERY_PAUSE_BELOW:-60} )) && { echo 0; return 0; }
        fi
    done
    echo 2
}

# ── Monitores ────────────────────────────────────────────────
aura_guard_monitor_snapshot() { xrandr --listmonitors 2>/dev/null; }

# Reconstruye el fondo y deja la foto de monitores SIEMPRE coherente con lo
# que se acaba de arrancar de verdad.
# Hace falta porque stop+start tardan unos segundos: si en medio cambia el
# juego de monitores, la foto no puede ser la de "antes" (si no, al comparar
# luego se creeria que no ha cambiado nada y el motor de un monitor ya
# desconectado se quedaria vivo para siempre, con --loop y sin dueño).
aura_guard_reconcile() {
    local snapshot=$1 antes ahora intentos=0
    while (( intentos++ < 3 )); do
        antes=$(aura_guard_monitor_snapshot)
        aura_engine_stop
        aura_engine_start
        ahora=$(aura_guard_monitor_snapshot)
        printf '%s\n' "$ahora" >"$snapshot"
        [[ $antes == "$ahora" ]] && return 0
        aura_log "los monitores cambiaron al reajustar, otra vuelta"
    done
    return 0
}

# ── Cambio de acento suficiente ──────────────────────────────
# 0 = hay que propagar, 1 = el color es casi igual
aura_theme_changed() {
    local new=$1 old_file=$AURA_RUNTIME/accent.applied old
    old=$(grep -oE 'accent=#[0-9A-Fa-f]{6}' "$old_file" 2>/dev/null | cut -d= -f2)
    printf '%s\n' "$new" >"$old_file"
    [[ -z $old ]] && return 0
    python3 - "$old" "$new" "${THEME_MIN_DELTA:-7}" <<'PY'
import sys
def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
try:
    a, b, tol = rgb(sys.argv[1]), rgb(sys.argv[2]), float(sys.argv[3])
except Exception:
    sys.exit(0)
dist = sum(abs(x - y) for x, y in zip(a, b)) / 3.0
sys.exit(1 if dist < tol else 0)
PY
}

# ── Bucle principal ──────────────────────────────────────────
aura_guard_run() {
    aura_init_dirs || aura_die "no se pudo crear $AURA_RUNTIME"
    aura_need mpv xwinwrap ffmpeg

    if aura_daemon_running; then
        aura_err "ya hay un guard activo (pid $(cat "$AURA_RUNTIME/guard.pid"))"
        return 1
    fi
    printf '%s\n' "$BASHPID" >"$AURA_RUNTIME/guard.pid"

    if command -v bspc >/dev/null; then
        bspc subscribe node_state node_focus desktop_focus 2>/dev/null | while read -r _; do
            kill -USR1 "$BASHPID" 2>/dev/null
        done &
        BSPC_PID=$!
        trap "kill $BSPC_PID 2>/dev/null; aura_guard_cleanup" EXIT INT TERM
        trap "true" USR1
    else
        trap 'aura_guard_cleanup' EXIT INT TERM
    fi

    local tick=0 paused=0 battery_paused=0 last_battery=2
    local snapshot="$AURA_RUNTIME/monitors.snapshot"
    local last_reconcile=0
    aura_guard_monitor_snapshot >"$snapshot"

    aura_log "guard activo (pid $BASHPID, watcher ${BSPC_PID:-ninguno})"

    while :; do
        sleep "${AURA_TICK:-2}" &
        wait $! 2>/dev/null
        ((tick++))
        
        # Recargar configuracion dinamicamente
        [ -f "$AURA_CONF" ] && . "$AURA_CONF"

        if aura_guard_desajuste; then
            if (( $(date +%s) - last_reconcile >= ${AURA_RECONCILE_EVERY:-20} )); then
                last_reconcile=$(date +%s)
                aura_log "cambio de monitores, reajustando el fondo"
                aura_guard_reconcile "$snapshot"
                paused=0
            fi
        elif ! aura_guard_engine_alive; then
            aura_log "el fondo no esta corriendo, reiniciando..."
            aura_engine_start
            paused=0
        fi

        if (( tick % 15 == 0 )) && (( ${BATTERY_PAUSE:-1} )); then
            last_battery=$(aura_guard_battery)
            case $last_battery in
                0) (( battery_paused )) || {
                    aura_engine_pause on
                    battery_paused=1
                    paused=1
                    aura_notify "bateria" "pausado en bateria"
                    aura_log "bateria baja: pausa"
                } ;;
                *) (( battery_paused )) && {
                    battery_paused=0
                    aura_engine_pause off
                    aura_log "en linea: reanudado"
                } ;;
            esac
        fi

        # Evaluar pausa de ventana enfocada en cada iteración (incluyendo USR1)
        if aura_guard_should_pause; then
            if (( ! paused )); then
                aura_engine_pause on
                paused=1
                aura_log "pantalla completa detectada: pausa instantánea"
            fi
        elif (( paused && ! battery_paused )); then
            aura_engine_pause off
            paused=0
            aura_log "reanudado instantáneo"
        fi

        if (( tick % 5 == 0 )); then
            if ! aura_guard_monitor_snapshot | cmp -s - "$snapshot"; then
                aura_log "cambio de monitores, reajustando el fondo"
                aura_guard_reconcile "$snapshot"
                paused=0
            fi
        fi

        # Slideshow (SLIDESHOW is in minutes)
        if (( ${SLIDESHOW:-0} > 0 )); then
            local sl_ticks=$(( ${SLIDESHOW} * 60 / ${AURA_TICK:-2} ))
            if (( sl_ticks > 0 && tick > 0 && tick % sl_ticks == 0 )); then
                aura_log "slideshow: rotando fondo automáticamente"
                "$AURA_BIN_DIR/aura" next &
            fi
        fi

        if (( ${THEME:-1} && tick % $(( ${THEME_INTERVAL:-15} / ${AURA_TICK:-2} )) == 0 )); then
            local mon file t pos
            mon=$(aura_theme_source_monitor)
            file=$(aura_get_state "$mon" file)
            if [[ -n $file && -f $file ]]; then
                if aura_is_video "$file"; then
                    pos=$("$AURA_BIN_DIR/aura-ipc" "$(aura_engine_socket "$mon")" --get time-pos 2>/dev/null | tr -d '"')
                    t=${pos%.*}
                    [[ -z $t ]] && t=${AURA_FRAME_TIME:-2}
                else
                    t=${AURA_FRAME_TIME:-2}
                fi
                local palette
                if palette=$(aura_accent_sample "$file" "$t"); then
                    local new
                    new=$(grep -oE 'accent=#[0-9A-Fa-f]{6}' <<<"$palette" | cut -d= -f2)
                    if aura_theme_changed "$new"; then
                        aura_theme_write "$palette"
                        printf '%s %s\n' "$(date +%H:%M:%S)" "accent=$new" \
                            >>"$AURA_PALETTE_HIST" 2>/dev/null
                    fi
                fi
            fi
        fi
    done
}

aura_guard_cleanup() {
    rm -f "$AURA_RUNTIME/guard.pid" "$AURA_RUNTIME/guard.lock"
    # no paramos el motor: 'aura stop' es el unico que lo detiene
    exit 0
}
