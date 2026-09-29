# Aura Studio v1.0 🌌
A lightweight, open-source Animated Wallpaper Engine for X11 Window Managers (BSPWM, i3, Awesome, etc.) with Live Shaders, Multi-Monitor support, and Auto-Theming capabilities.

![Aura Studio](https://raw.githubusercontent.com/gh0stzk/dotfiles/master/misc/preview.png) *(You can replace this image later)*

## ✨ Features
* **Online Catalog:** Integrated search and download for MotionBgs and MoeWalls.
* **Live Visual Filters:** Apply real-time shaders (Blur, Cyberpunk, Sepia, Invert, etc.) seamlessly using dynamic MPV hardware decoding transitions.
* **Multi-Monitor Native:** Assign specific wallpapers and filters to different screens.
* **System Integration:** Extracts dominant colors from your video to dynamically theme your window borders (BSPWM), Polybar, Rofi, Kitty, and Ghostty. (Fully compatible out-of-the-box with gh0stzk dotfiles).
* **Smart Pausing:** Automatically pauses playback when a fullscreen app or game is running to save resources.
* **System Tray:** Ghost mode and quick-controls from your system tray.

## 🚀 Installation

### Arch Linux (Recommended)
You can easily install Aura Studio by cloning this repository and running the automated install script:

```bash
git clone https://github.com/YOUR_USERNAME/Aura-Studio.git
cd Aura-Studio
./install.sh
```
*The script will automatically detect and install dependencies using `pacman` and `yay/paru`.*

### Manual / Other Distros
1. Ensure you have the following dependencies installed: `mpv`, `xwinwrap`, `xdotool`, `xrandr`, `yt-dlp`, `python3`, `python-pyqt6`, and `colorthief` (pip).
2. Copy the `config/aura` directory to `~/.config/aura`.
3. Copy the scripts in `bin/` to `~/.local/bin/` and make them executable.

## 🎨 Auto-Theming Setup
If you are NOT using the gh0stzk dotfiles structure, you can disable the Auto-Theming module to use Aura purely as a Wallpaper Engine:
1. Open `~/.config/aura/aura.conf`
2. Change `THEME=1` to `THEME=0`.

## 🤝 Contributing
Feedback, bug reports, and pull requests are highly appreciated! Let's build the best open-source wallpaper engine for Linux.
