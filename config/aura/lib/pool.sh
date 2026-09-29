# =============================================================
#  █████╗ ██╗   ██╗██████╗ ██╗
# ██╔══██╗██║   ██║██╔══██╗██║
# ███████║██║   ██║██████╔╝██║
# ██╔══██║██║   ██║██╔══██╗██║
# ██║  ██║╚██████╔╝██████╔╝███████╗
# ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
#  aura — pool de wallpapers (imagenes y videos) y cache de miniaturas
# =============================================================

[[ -n ${_AURA_POOL_SH:-} ]] && return 0
_AURA_POOL_SH=1

AURA_VIDEO_EXT='mp4|mkv|webm|avi|mov|m4v|flv|wmv|mpg|mpeg|ogv'
AURA_IMAGE_EXT='jpg|jpeg|png|webp|bmp|avif|jxl'

# Directorios del pool (los definidos en aura.conf, con la rice actual)
aura_pool_dirs() {
    local d
    for d in "${POOL[@]-}"; do
        [[ -n $d ]] || continue
        d=${d//\$HOME/$HOME}
        d=${d//\$RICE/$(aura_rice)}
        d=${d//rices\/\/walls/rices\/$(aura_rice)\/walls}
        d=${d//\~/$HOME}
        [ -d "$d" ] && printf '%s\n' "$d"
    done
}

# Expresion de find con la lista de extensiones del pool.
# (el -iregex de este find no trae alternancia "|", asi que se repite -iname)
aura_pool_find_expr() {
    local e
    AURA_FIND_EXT=()
    local IFS='|'          # las extensiones van separadas por "|"
    for e in $AURA_VIDEO_EXT $AURA_IMAGE_EXT; do
        ((${#AURA_FIND_EXT[@]})) && AURA_FIND_EXT+=(-o)
        AURA_FIND_EXT+=(-iname "*.$e")
    done
}

# Todos los archivos del pool, sin repetir, ordenados
aura_pool_files() {
    local dir f
    aura_pool_find_expr
    while IFS= read -r dir; do
        [[ -d $dir ]] || continue
        while IFS= read -r f; do
            printf '%s\n' "$f"
        done < <(find "$dir" -maxdepth "${POOL_DEPTH:-2}" -type f \
            \( "${AURA_FIND_EXT[@]}" \) \
            -printf '%f\t%p\n' 2>/dev/null | sort -t$'\t' -k1,1 | cut -f2-)
    done < <(aura_pool_dirs)
}

# Solo videos / solo imagenes
aura_pool_files_kind() {
    local kind=$1 f
    while IFS= read -r f; do
        case $kind in
            video) aura_is_video "$f" && printf '%s\n' "$f" ;;
            image) aura_is_image "$f" && printf '%s\n' "$f" ;;
            *) printf '%s\n' "$f" ;;
        esac
    done < <(aura_pool_files)
}

# ── Miniaturas ───────────────────────────────────────────────
# OJO: este mkdir es imprescindible; sin el, aura_thumb genera la miniatura
# pero el mv final falla (directorio inexistente) y se rehace siempre.
aura_thumb_dir() {
    aura_init_dirs
    mkdir -p "$AURA_CACHE/thumbs" 2>/dev/null
    printf '%s/thumbs' "$AURA_CACHE"
}

# Ruta de la miniatura cacheada de un archivo
aura_thumb_path() {
    local file=$1
    file=$(readlink -f "$file" 2>/dev/null || printf '%s' "$file")
    local key
    key=$(printf '%s' "$file" | md5sum | cut -c1-16)
    printf '%s/%s.png' "$(aura_thumb_dir)" "$key"
}

# Genera (o reutiliza) la miniatura de un archivo
# OJO: el temporal TIENE que acabar en .png; si no, ffmpeg no puede deducir
# el muxer, falla y la miniatura nunca llega a la cache (todo se rehace).
aura_thumb() {
    local file=$1 size=${2:-200} out tmp
    out=$(aura_thumb_path "$file")
    [ -s "$out" ] && { printf '%s' "$out"; return 0; }
    aura_init_dirs
    tmp=$AURA_CACHE/.thumb.$$.${RANDOM}.png
    if aura_is_video "$file"; then
        ffmpeg -hide_banner -loglevel error -y -ss 2 -i "$file" -frames:v 1 \
            -vf "scale=$size:$size:force_original_aspect_ratio=increase,crop=$size:$size" \
            -f image2 "$tmp" 2>/dev/null \
            || ffmpeg -hide_banner -loglevel error -y -i "$file" -frames:v 1 \
                -vf "scale=$size:$size:force_original_aspect_ratio=increase,crop=$size:$size" \
                -f image2 "$tmp" 2>/dev/null
    else
        magick "$file[0]" -auto-orient -resize "${size}x${size}^" -gravity center \
            -extent "${size}x${size}" "$tmp" 2>/dev/null \
            || magick "$file" -auto-orient -resize "${size}x${size}^" -gravity center \
                -extent "${size}x${size}" "$tmp" 2>/dev/null
    fi
    if [[ -s $tmp ]]; then
        mv -f "$tmp" "$out"
    else
        rm -f "$tmp"
        # miniatura de emergencia (degradado) para no romper el menu
        magick -size "${size}x${size}" gradient:'#2A2F3A-#12151B' "$out" 2>/dev/null
    fi
    printf '%s' "$out"
}

# Calienta las miniaturas de golpe y en paralelo: la primera vez que se
# abre el menu, ffmpeg y magick tardan ~1s por archivo y sin esto se
# nota el paron antes de que aparezca rofi.
aura_thumbs_warm() {
    (($#)) || return 0
    local jobs=${AURA_THUMB_JOBS:-4} f
    local -a pids=()
    for f in "$@"; do
        aura_thumb "$f" 96 >/dev/null &
        pids+=("$!")
        ((${#pids[@]} >= jobs)) && {
            wait "${pids[0]}" 2>/dev/null
            pids=("${pids[@]:1}")
        }
    done
    ((${#pids[@]})) && wait 2>/dev/null
    return 0
}

# Limpia miniaturas viejas (conservador: solo por antiguedad)
aura_thumbs_gc() {
    local dir
    dir=$(aura_thumb_dir)
    [[ -d $dir ]] || return 0
    find "$dir" -name '*.png' -mtime "+${AURA_THUMB_GC_DAYS:-30}" -delete 2>/dev/null
    return 0
}
