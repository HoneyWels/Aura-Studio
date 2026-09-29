[[ -n ${_AURA_CONTROL_SH:-} ]] && return 0
_AURA_CONTROL_SH=1

aura_control_toggle_conf() {
    local key=$1
    local current_val
    # Leer valor actual de aura.conf, asume 1 si no está o está vacío
    current_val=$(grep -E "^${key}=" "$AURA_HOME/aura.conf" | cut -d= -f2)
    [[ -z $current_val ]] && current_val=1
    
    local new_val=0
    [[ "$current_val" == "0" ]] && new_val=1
    
    if grep -q "^${key}=" "$AURA_HOME/aura.conf"; then
        sed -i "s/^${key}=.*/${key}=${new_val}/" "$AURA_HOME/aura.conf"
    else
        echo "${key}=${new_val}" >> "$AURA_HOME/aura.conf"
    fi
    
    aura_notify "Aura Control" "$key cambiado a $new_val"
    
    # Reiniciar para aplicar cambios
    aura_cmd_stop >/dev/null 2>&1
    sleep 0.5
    aura_cmd_start
}

aura_cmd_control() {
    aura_init_dirs
    local theme="$AURA_HOME/rofi/switcher.rasi"
    
    # Recargar config real para los estados
    aura_load_conf

    local st_pause="⏸️ Pausar"
    local mon
    mon=$(aura_monitor_names | head -1)
    if [[ "$("$AURA_BIN_DIR/aura-ipc" "$(aura_engine_socket "$mon")" --get pause 2>/dev/null)" == "true" ]]; then
        st_pause="▶️ Reanudar"
    fi

    local st_theme="[ON]"
    [[ "${THEME:-1}" == "0" ]] && st_theme="[OFF]"
    
    local st_bat="[ON]"
    [[ "${BATTERY_PAUSE:-1}" == "0" ]] && st_bat="[OFF]"
    
    local st_game="[ON]"
    [[ "${AUTO_PAUSE:-1}" == "0" ]] && st_game="[OFF]"

    local options="1. $st_pause\n2. ⏭️ Siguiente Fondo\n3. 🖼️ Selector Rápido (HUD)\n4. 🎨 Auto-Theming $st_theme\n5. 🎮 Auto-Pausa Juegos $st_game\n6. 🔋 Pausa por Batería $st_bat\n7. ⬇️ Descargar Fondo (URL)\n8. ⚙️ Editar aura.conf"

    local choice
    choice=$(echo -e "$options" | rofi -dmenu -i -p "  Aura Panel " -theme "$theme" -l 8)

    case "$choice" in
        1.*)
            aura_engine_pause toggle
            ;;
        2.*)
            aura_step_apply next
            ;;
        3.*)
            aura_switcher_run
            ;;
        4.*)
            aura_control_toggle_conf "THEME"
            ;;
        5.*)
            aura_control_toggle_conf "AUTO_PAUSE"
            ;;
        6.*)
            aura_control_toggle_conf "BATTERY_PAUSE"
            ;;
        7.*)
            local url
            url=$(rofi -dmenu -p "  Pega URL de YouTube/Imagen " -theme "$theme" -l 0)
            [[ -n $url ]] && aura_cmd_fetch "$url"
            ;;
        8.*)
            local term="${TERMINAL:-kitty}"
            $term -e nano "$AURA_HOME/aura.conf" &
            ;;
    esac
}
