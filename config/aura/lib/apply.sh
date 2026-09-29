# =============================================================
#  █████╗ ██╗   ██╗██████╗ ██╗
# ██╔══██╗██║   ██║██╔══██╗██║
# ███████║██║   ██║██████╔╝██║
# ██╔══██║██║   ██║██╔══██╗██║
# ██║  ██║╚██████╔╝██████╔╝███████╗
# ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
#  aura — apply: poner un wallpaper y propagar su color
# =============================================================

[[ -n ${_AURA_APPLY_SH:-} ]] && return 0
_AURA_APPLY_SH=1

# Extrae un frame representativo a webp (para WallSync / cabeceras rofi)
aura_still() {
    local file=$1 out=$2 t=${3:-${AURA_FRAME_TIME:-2}}
    if aura_is_video "$file"; then
        ffmpeg -hide_banner -loglevel error -y -ss "$t" -i "$file" \
            -frames:v 1 "$out" 2>/dev/null && return 0
        ffmpeg -hide_banner -loglevel error -y -i "$file" \
            -frames:v 1 "$out" 2>/dev/null && return 0
        return 1
    fi
    magick "$file" -auto-orient "$out" 2>/dev/null && return 0
    cp -f "$file" "$out" 2>/dev/null
}

# Mantiene al dia lo que WallSync deja para el resto de la rice:
#   ~/.cache/current_wall        -> symlink al frame actual
#   ~/.cache/rofi_header.webp    -> cabecera de los temas style_1/2/3
aura_wallsync() {
    local file=${1:-} cache still hash
    [[ -n $file && -f $file ]] || return 1
    aura_have magick || return 0
    cache=${XDG_CACHE_HOME:-$HOME/.cache}
    mkdir -p "$cache" 2>/dev/null || return 1
    still=$cache/aura-current.webp
    aura_still "$file" "$still" || return 1

    ln -sf "$still" "$cache/current_wall" 2>/dev/null
    hash=$(md5sum "$still" 2>/dev/null | cut -d' ' -f1)
    if [[ -n $hash && $hash != "$(cat "$cache/current_wall.hash" 2>/dev/null)" ]]; then
        printf '%s' "$hash" >"$cache/current_wall.hash"
        magick "$still" -strip -resize 30% -gravity center -crop 760x196+0+0 +repage \
            -quality 65 -define webp:method=3 -define webp:thread-level=1 \
            "$cache/rofi_header.webp" 2>/dev/null
    fi
    return 0
}

# Fichero que hay puesto ahora mismo (el del primer monitor con motor vivo).
# Es lo que WallSync necesita para saber que foto poner de cabecera.
aura_current_file() {
    local mon f
    while read -r mon _; do
        aura_engine_alive "$mon" || continue
        f=$(aura_map_get "$mon" 2>/dev/null) || f=
        [[ -z $f ]] && f=$(aura_get_state "$mon" file)
        [[ -n $f && -f $f ]] && { readlink -f "$f"; return 0; }
    done < <(aura_monitors)
    return 1
}

# Nombre bonito para la notificacion
aura_label() {
    local f=$1
    f=${f##*/}
    printf '%s' "${f%.*}"
}

# ── Aplicar un wallpaper ─────────────────────────────────────
#   aura_apply <archivo> [monitor]
aura_apply() {
    local file=${1:-} only=${2:-}
    [[ -n $file ]] || aura_die "aura apply: falta el archivo"
    [[ -e $file ]] || aura_die "aura apply: no existe $file"
    file=$(readlink -f "$file")

    if aura_is_video "$file" || aura_is_image "$file"; then
        :
    else
        aura_warn "formato no reconocido, mpv intentará: ${file##*.}"
    fi

    aura_init_dirs
    aura_engine_load "$file" "$only" || aura_die "no se pudo reproducir $file"

    # recordar que archivo va en cada monitor (lo usa el guard al revivir)
    local mon
    while read -r mon _; do
        [[ -n $only && $mon != "$only" ]] && continue
        aura_map_set "$mon" "$file"
    done < <(aura_monitors)

    # el accent va detras del fondo: si falla el video, el tema no cambia
    if (( ${THEME:-1} )); then
        aura_theme_apply "$file" "$(aura_label "$file")" ||
            aura_warn "no se pudo calcular el acento de ${file##*/}"
    fi

    aura_wallsync "$file" || aura_warn "WallSync: no se pudo generar el frame"
    aura_notify "$(aura_label "$file")" "fondo aplicado"
    return 0
}

# ── Siguiente / anterior ─────────────────────────────────────
aura_step_apply() {
    local dir=$1
    local next
    next=$(aura_engine_step "$dir") || return 1
    aura_apply "$next"
}
