# =============================================================
#  █████╗ ██╗   ██╗██████╗ ██╗
# ██╔══██╗██║   ██║██╔══██╗██║
# ███████║██║   ██║██████╔╝██║
# ██╔══██║██║   ██║██╔══██╗██║
# ██║  ██║╚██████╔╝██████╔╝███████╗
# ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
#  aura — motor: ventana de fondo + reproduccion + control por IPC
# =============================================================
#
#  Por que xwinwrap y no la ventana de mpv directamente:
#
#    xwinwrap crea una ventana PADRE con
#      _NET_WM_WINDOW_TYPE_DESKTOP   -> bspwm la ignora (no es un cliente)
#      _NET_WM_STATE_BELOW          -> picom la pinta debajo de todo
#    y reparenta dentro la ventana de mpv. Resultado: un fondo animado
#    que no entra en el layout, no roba el foco, no aparece en bspc node,
#    no dispara tus ExternalRules (que siénten la clase "mpv") y es visible
#    en todos los escritorios sin necesidad de sticky.
#
# =============================================================

[[ -n ${_AURA_ENGINE_SH:-} ]] && return 0
_AURA_ENGINE_SH=1

aura_engine_socket() { printf '%s/mp-%s.sock' "$AURA_RUNTIME" "$1"; }
aura_engine_log() { printf '%s/mpv-%s.log' "$AURA_RUNTIME" "$1"; }

# ── Mapa archivo por monitor ──────────────────────────────────
aura_map_file() { printf '%s/screen-map' "$AURA_CACHE"; }

aura_map_get() {
    local mon=$1 f
    f=$(aura_map_file)
    [[ -r $f ]] || return 1
    awk -F'\t' -v m="$mon" '$1==m {print $2; found=1} END{exit !found}' "$f"
}

aura_map_set() {
    local mon=$1 file=$2 f tmp
    f=$(aura_map_file)
    aura_init_dirs
    tmp=$f.$$
    [[ -r $f ]] && grep -vE "^${mon}	" "$f" >"$tmp" 2>/dev/null
    printf '%s\t%s\n' "$mon" "$file" >>"$tmp"
    mv -f "$tmp" "$f"
}

aura_map_del() {
    local mon=$1 f tmp
    f=$(aura_map_file)
    [[ -r $f ]] || return 0
    tmp=$f.$$
    grep -vE "^${mon}	" "$f" >"$tmp" 2>/dev/null
    mv -f "$tmp" "$f"
}

aura_map_list() {
    local f
    f=$(aura_map_file)
    [[ -r $f ]] && cat "$f"
}

# ── Resolucion de archivo por monitor ─────────────────────────
aura_engine_resolve() {
    local mon=$1 fallback=${2:-}
    local mapped
    if mapped=$(aura_map_get "$mon"); then
        printf '%s' "$mapped"
        return 0
    fi
    [[ -n $fallback ]] && printf '%s' "$fallback"
}

# Ultimo recurso cuando no hay nada en el mapa: el ANIMATED_WALL de la
# rice activa y, si no existe, el primer video del pool.
aura_default_file() {
    local f
    f=$(aura_rice_var ANIMATED_WALL)
    f=${f//\$HOME/$HOME}
    if [[ -n $f && -f $f ]]; then
        printf '%s' "$f"
        return 0
    fi
    f=$(aura_pool_files_kind video | head -1)
    [[ -n $f ]] && printf '%s' "$f"
    return 0
}

# ── Arranque ─────────────────────────────────────────────────
# engine_start [archivo] [monitor]
#   Si no se pasa archivo usa el mapa por monitor o ANIMATED_WALL de la rice.
aura_engine_start() {
    local file=${1:-} only=${2:-}
    aura_need xwinwrap mpv
    aura_init_dirs || aura_die "no se pudo crear $AURA_RUNTIME"

    local mon geo
    while read -r mon geo; do
        [[ -n $only && $mon != "$only" ]] && continue
        local target
        target=$(aura_engine_resolve "$mon" "$file")
        [[ -z $target ]] && target=$(aura_default_file)
        if [[ -z $target || ! -f $target ]]; then
            aura_warn "$mon: sin archivo que reproducir"
            continue
        fi
        aura_engine_spawn "$mon" "$geo" "$target"
    done < <(aura_monitors)
}

# Lanza (o relanza) el fondo de un monitor
aura_engine_spawn() {
    local mon=$1 geo=$2 file=$3
    local sock pid prev
    sock=$(aura_engine_socket "$mon")
    prev=$(aura_get_state "$mon" pid)
    [[ -n $prev ]] && aura_alive "$prev" && aura_engine_kill "$mon"

    # quien tiene el teclado ahora, para devolverselo si el fondo se lo queda
    local focus_before
    focus_before=$(xdotool getwindowfocus 2>/dev/null) || focus_before=

    rm -f "$sock"
    # xwinwrap -g geo: tamaño exacto del monitor
    #          -un  sin decoraciones   -fdt  tipo DESKTOP
    #          -b   debajo             -nf   no roba el foco
    #          -ni  no enfoca al mapear  -st/-sp  fuera de taskbar/paginador
    local vol dim
    vol=${VOLUME:-0}
    dim=${BRIGHTNESS:-0}

    local args=(
        --no-config --no-terminal --no-osc --no-input-default-bindings
        --no-osd-bar --no-sub --no-border
        --volume="$vol" --brightness="$dim"
        --title="aura-wallpaper-$mon"
        # mpv por defecto hace --focus-on=open: al mapear pide el foco, bspwm
        # lo Managea como cliente flotante y se lo queda. El teclado se
        # entonces en el fondo. -nf de xwinwrap solo afecta a su ventana.
        --focus-on=never
        --hwdec=auto --vo=gpu-next --gpu-api=auto --vd-lavc-threads=1
        --loop-file=inf --keep-open=yes --image-display-duration=inf
        --autofit-larger=100%x100% --force-window=immediate
        --input-ipc-server="$sock"
        --geometry="$geo"
    )
    aura_is_image "$file" && args+=(--image-display-duration=inf)

    # Leer SCALE_Monitor del config (default FILL) y mapear a opciones de mpv
    local safe_mon="${mon//-/_}"
    local scale_var="SCALE_${safe_mon}"
    local scale_mode="${!scale_var:-FILL}"
    case "$scale_mode" in
        STRETCH) args+=(--keepaspect=no --video-unscaled=no) ;;
        FIT)     args+=(--keepaspect=yes --video-unscaled=no --panscan=0) ;;
        CENTER)  args+=(--video-unscaled=yes) ;;
        FILL|*)  args+=(--keepaspect=yes --video-unscaled=no --panscan=1) ;;
    esac

    # setsid --wait: el pid guardado es tambien el process-group id, para matar
    # xwinwrap y bash (con exec mpv) juntos. xwinwrap reemplaza "WID" exacto
    # por su window id en hex. Así que usamos bash -c para inyectarlo en --wid=
    setsid --wait xwinwrap -g "$geo" -b -nf -ni -un -fs -fdt -st -sp -s -- \
        bash -c 'exec mpv --wid="$1" "${@:2}"' _ WID "${args[@]}" "$file" \
        </dev/null >"$(aura_engine_log "$mon")" 2>&1 &
    pid=$!
    disown 2>/dev/null || true

    aura_set_state "$mon" pid "$pid"
    aura_set_state "$mon" file "$file"
    aura_set_state "$mon" geo "$geo"
    aura_set_state "$mon" paused 0

    # esperar a que el socket exista (arranque cold de mpv)
    local i
    for i in {1..40}; do
        [[ -S $sock ]] && break
        sleep 0.05
    done
    if [[ -S $sock ]]; then
        aura_set_state "$mon" paused "${AURA_START_PAUSED:-0}"
        # Aplicar regla bspwm para que la ventana quede below y no robe foco
        (aura_engine_apply_bspwm_rule "$mon") >/dev/null 2>&1 &
        # en segundo plano: bspwm no decide al vuelo cuando quedarse con el
        # teclado y bloquear aqui retardsaria al guard
        [[ -n $focus_before ]] && {
            (aura_engine_give_focus_back "$focus_before") >/dev/null 2>&1 &
            disown 2>/dev/null || true
        }
        return 0
    fi
    aura_err "$mon: mpv no arranco (revisa $(aura_engine_log "$mon"))"
    return 1
}

# bspwm no ignora la ventana del fondo: mpv no deja que xwinwrap le imponga
# el tipo DESKTOP, asi que bspwm la gestiona como un cliente flotante mas y al
# mapear se puede quedar con el teclado. Cuando pasa, el foco vuelve a donde
# estaba.
#
# Se vigila durante toda la ventana en vez de mirar una sola vez: bspwm decide
# con su propio bucle y puede quedarse con el teclado casi un segundo despues
# del map, y mientras tanto el foco pasa por estados intermedios al morir la
# ventana anterior. Solo se toca si el foco ha acabado en una ventana de aura.
aura_engine_give_focus_back() {
    local before=$1 i now name
    [[ -n $before && $before != 0x0 ]] || return 0
    aura_have xdotool || return 0

    for i in {1..30}; do
        now=$(xdotool getwindowfocus 2>/dev/null) || return 0
        if [[ -n $now && $now != "$before" ]]; then
            name=$(xdotool getwindowname "$now" 2>/dev/null)
            case $name in
                aura-wallpaper-*|aura-preview*)
                    xdotool windowactivate --sync "$before" >/dev/null 2>&1
                    return 0
                    ;;
            esac
        fi
        sleep 0.1
    done
    return 0
}

# Aplica configuración bspwm a la ventana del wallpaper para que quede below y no robe foco
aura_engine_apply_bspwm_rule() {
    local mon=$1 i wid title
    sleep 0.5  # dar tiempo a que mpv cree la ventana tras el socket
    for i in {1..100}; do
        wid=$(xdotool search --name "aura-wallpaper-$mon" 2>/dev/null | head -1)
        if [[ -n $wid ]]; then
            title=$(xdotool getwindowname "$wid" 2>/dev/null)
            case $title in
                aura-wallpaper-*)
                    # Configurar nodo existente: floating, layer=below
                    bspc node "$wid" -t floating -l below 2>/dev/null
                    return 0
                    ;;
            esac
        fi
        sleep 0.1
    done
    return 1
}

# ── Parada ───────────────────────────────────────────────────
aura_engine_kill() {
    local mon=$1 pid sock p
    pid=$(aura_get_state "$mon" pid)
    sock=$(aura_engine_socket "$mon")
    if [[ -S $sock ]]; then
        "$AURA_BIN_DIR/aura-ipc" "$sock" quit >/dev/null 2>&1
    fi
    if [[ -n $pid ]] && aura_alive "$pid"; then
        # xwinwrap relay: matar al grupo deja limpio a mpv
        aura_kill_tree "$pid" TERM
        local i
        for i in {1..20}; do
            aura_alive "$pid" || break
            sleep 0.1
        done
        aura_alive "$pid" && aura_kill_tree "$pid" KILL
    fi
    # red de seguridad: si el pid guardado no cuadra (sesion vieja), nos
    # deshacemos de cualquier xwinwrap/mpv marcado con el nombre del monitor
    for p in $(aura_wall_pids "$mon"); do
        aura_kill_tree "$p" TERM 2>/dev/null
    done
    rm -f "$sock"
    aura_del_state "$mon" pid
    return 0
}

aura_engine_stop() {
    local only=${1:-} mon
    #_union de lo que hay en pantalla y lo que quedo en el runtime-, porque un
    # monitor que se desconecta ya no sale de aura_monitors pero su motor sigue
    # vivo: si solo recorriéramos la lista actual, su mpv se quedaria huérfano
    # (con --loop, para siempre) y sus ficheros de estado zombis.
    local -a con_estado=()
    while read -r mon; do
        [[ -n $mon ]] && con_estado+=("$mon")
    done < <(aura_state_monitors)
    while read -r mon; do
        [[ -n $mon ]] || continue
        [[ -n $only && $mon != "$only" ]] && continue
        aura_engine_kill "$mon"
        aura_del_state "$mon" file
    done < <({ aura_monitor_names; printf '%s\n' "${con_estado[@]}"; } | sort -u)
    # respaldos: cualquier xwinwrap de aura que quedara vivo
    pkill -f '[a]ura-wallpaper-' >/dev/null 2>&1
    rm -f "$AURA_RUNTIME"/mp-*.sock
    # se le pasa la lista capturada antes de matar: aura_engine_kill ya borro
    # wall-<mon>.pid, y sin esto el monitor desconectado seria indistinguible
    # de uno que nunca existio y se quedaria con geo/paused zombis
    aura_engine_reap_gone "${con_estado[@]}"
}

# Limpia los monitores con estado que ya no estan en pantalla (desconectados
# entre dos reinicios del motor). Sin esto su mpv se queda con --loop
# reproduciendo en un monitor que ya no existe. Con lista de argumentos usa esa
# en vez de leer el runtime.
aura_engine_reap_gone() {
    local mon onscreen
    local -a mons=("$@")
    if [[ ${#mons[@]} -eq 0 ]]; then
        while read -r mon; do
            mons+=("$mon")
        done < <(aura_state_monitors)
    fi
    for mon in "${mons[@]}"; do
        [[ -n $mon ]] || continue
        onscreen=$(aura_monitor_names | grep -cx "$mon")
        [[ $onscreen == 0 ]] || continue
        aura_engine_kill "$mon"
        aura_del_monitor_state "$mon"
    done
}

# ── Control ──────────────────────────────────────────────────
# El motor de un monitor esta de verdad en marcha?
# OJO: mirar solo el socket NO vale. Si mpv peta, el socket se queda en el
# disco y [[ -S ]] sigue dando true, asi que el motor parece vivo cuando
# esta muerto (y aura apply no arrancaba nada). Hay que mirar el pid.
aura_engine_alive() {
    local mon=$1 pid sock
    pid=$(aura_get_state "$mon" pid)
    sock=$(aura_engine_socket "$mon")
    [[ -n $pid ]] && aura_alive "$pid" && [[ -S $sock ]] && return 0
    return 1
}

# Si el motor esta muerto, se limpian sus restos (socket huerfano, pid)
aura_engine_reap() {
    local mon=$1
    aura_engine_alive "$mon" && return 1
    rm -f "$(aura_engine_socket "$mon")"
    aura_del_state "$mon" pid
    return 0
}

aura_engine_pause() {
    local mode=$1 mon sock
    while read -r mon _; do
        aura_engine_alive "$mon" || continue
        sock=$(aura_engine_socket "$mon")
        local cur
        cur=$("$AURA_BIN_DIR/aura-ipc" "$sock" --get pause 2>/dev/null)
        local want
        case $mode in
            on) want=true ;;
            off) want=false ;;
            toggle) [[ $cur == true ]] && want=false || want=true ;;
            *) aura_die "pause: modo invalido ($mode)" ;;
        esac
        "$AURA_BIN_DIR/aura-ipc" "$sock" --set pause "$want" >/dev/null 2>&1
        aura_set_state "$mon" paused "$([[ $want == true ]] && echo 1 || echo 0)"
    done < <(aura_monitors)
}

# Carga un archivo en el(los) monitor(es) indicado(s)
aura_engine_load() {
    local file=$1 only=${2:-}
    [[ -f $file ]] || aura_die "no existe: $file"
    file=$(readlink -f "$file")
    local mon geo
    while read -r mon geo; do
        [[ -n $only && $mon != "$only" ]] && continue
        if aura_engine_alive "$mon"; then
            if "$AURA_BIN_DIR/aura-ipc" "$(aura_engine_socket "$mon")" \
                --load "$file" >/dev/null 2>&1; then
                aura_set_state "$mon" file "$file"
                aura_del_state "$mon" paused
                continue
            fi
            # estaba vivo pero no contesta: lo relanzamos con el archivo nuevo
            aura_warn "$mon: el motor no respondia, relanzando"
            aura_engine_kill "$mon"
        else
            aura_engine_reap "$mon"
        fi
        aura_engine_spawn "$mon" "$geo" "$file" || return 1
    done < <(aura_monitors)
    return 0
}

# Siguiente/anterior en el pool
aura_engine_step() {
    local dir=$1 mon current next
    # archivo actual del monitor enfocado (o el primero)
    mon=$(aura_primary_monitor | cut -d' ' -f1)
    current=$(aura_get_state "$mon" file)
    [[ -z $current ]] && current=$(aura_get_state "$(aura_monitor_names | head -1)" file)
    local -a files=()
    mapfile -t files < <(aura_pool_files)
    ((${#files[@]})) || aura_die "el pool esta vacio"
    local idx=-1 i
    for i in "${!files[@]}"; do
        [[ ${files[$i]} == "$current" ]] && idx=$i && break
    done
    case $dir in
        next) next=$(( (idx + 1) % ${#files[@]} )) ;;
        prev) next=$(( (idx - 1 + ${#files[@]}) % ${#files[@]} )) ;;
        *) aura_die "step: direccion invalida" ;;
    esac
    [[ $idx -eq -1 ]] && { [[ $dir == next ]] && next=0 || next=$((${#files[@]} - 1)); }
    printf '%s' "${files[$next]}"
}

# ── Estado ───────────────────────────────────────────────────
aura_engine_status() {
    local running=0 mon
    printf '\033[1maura\033[0m — estado del fondo\n\n'
    while read -r mon geo; do
        local pid file paused sock
        pid=$(aura_get_state "$mon" pid)
        sock=$(aura_engine_socket "$mon")
        file=$(aura_get_state "$mon" file)
        paused=$(aura_get_state "$mon" paused)
        if [[ -n $pid ]] && aura_alive "$pid" && [[ -S $sock ]]; then
            running=1
            local live
            live=$("$AURA_BIN_DIR/aura-ipc" "$sock" --get pause 2>/dev/null)
            [[ $live == true ]] && paused=1 || paused=${paused:-0}
            printf '  \033[38;5;141m●\033[0m %-10s %-14s %s  \033[2m%s\033[0m\n' \
                "$mon" "$geo" "$([[ ${paused:-0} == 1 ]] && echo 'en pausa' || echo 'reproduciendo')" "${file#$HOME/}"
        else
            printf '  \033[38;5;240m○\033[0m %-10s %-14s %s\n' "$mon" "$geo" 'detenido'
        fi
    done < <(aura_monitors)
    printf '\n'
    if aura_daemon_running; then
        printf '  guard     \033[38;5;141mactivo\033[0m (pid %s)\n' "$(cat "$AURA_RUNTIME/guard.pid")"
    else
        printf '  guard     inactivo\n'
    fi
    if [[ -r $AURA_RUNTIME/accent ]]; then
        printf '  acento    %s\n' "$(grep -oE 'accent=#[0-9A-Fa-f]{6}' "$AURA_RUNTIME/accent")"
    fi
    [[ -n ${POOL[0]-} ]] && printf '  pool      %s\n' "$(aura_pool_files | wc -l) archivos"
    return $((1 - running))
}
