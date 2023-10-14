#!/bin/sh

# Rentib's Arch Installing Script (RAIS)
# by Rentib
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

dotfilesrepo="https://github.com/Rentib/dotfiles.git"
aurhelper="yay"
repobranch="master"

### FUNCTIONS ###

die() {
  echo "$1" >&2
  exit 1
}

installpkg() {
  idx=0
  num=$(echo "$@" | wc -w)
  for pkg in "$@"; do
    echo "Installing $pkg... [$((++idx))/$num]"
    pacman -Q "$pkg" >/dev/null 2>&1 && continue
    pacman --noconfirm --needed -S "$pkg" >/dev/null 2>&1
  done
}

prompt() {
  while true; do
    read -p "$1 [Y/n]" yn
    [ -z "$yn" ] && yn="y"
    case $yn in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
    esac
    echo "Please answer y or n"
  done
}

install_nerd_fonts() {
  path="/home/$name/.local/share/fonts"

  for font in $@; do
    sudo -u $user curl -OL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/"$font.tar.xz"
    sudo -u $user mkdir -p "$path/$font"
    sudo -u $user tar -xf "$font.tar.xz" -C "$path/$font"
    sudo -u $user rm "$font.tar.xz"
  done

  sudo -u "$name" fc-cache -fv >/dev/null 2>&1
}

getuser() {
  while true; do
    read -p "Enter username: " name
    ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$" && echo "Invalid username! Use lowercase letters, numbers, underscores and dashes only." && continue
    id "$name" >/dev/null 2>&1 && echo "User $name already exists!" && continue
  done
}

getpass() {
  while true; do
    read -sp "Enter password: " pass1; echo
    read -sp "Confirm password: " pass2; echo
    [ "$pass1" = "$pass2" ] && break
    echo "Passwords do not match!"
  done
}

adduserandpass() {
  echo "Adding user \"$name\"..."
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1
  export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

manualinstall() {
	# Installs $1 manually. Used only for AUR helper here.
	# Should be run after repodir is created and var is set.
	pacman -Qq "$1" && return 0
  echo "Installing \"$1\" manually."
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{
			cd "$repodir/$1" || return 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$repodir/$1" || exit 1
	sudo -u "$name" -D "$repodir/$1" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

putgitrepo() {
  # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
  echo "Downloading and installing config files..."
  [ -z "$3" ] && branch="master" || branch="$repobranch"
  dir=$(mktemp -d)
  [ ! -d "$2" ] && mkdir -p "$2"
  chown "$name":wheel "$dir" "$2"
  sudo -u "$name" git -C "$repodir" clone --depth 1 \
  	--single-branch --no-tags -q --recursive -b "$branch" \
  	--recurse-submodules "$1" "$dir"
  sudo -u "$name" cp -rfT "$dir" "$2"
}

### THE ACTUAL SCRIPT ###

trap 'die "Aborted."' INT
echo "Welcome to RAIS (Rentib's Arch Installing Script)!"

getuser
getpass
prompt "Do you want to parallelize pacman?" && parallel="y" || parallel="n"

echo "The rest of the script requires no user input."
echo "You can safely leave the script unattended."
echo "When you come back, you will have a fully configured Arch Linux system."
prompt "Proceed with installation?" || die "Aborted."

echo "Refreshing Arch keyring..."
case "$(readlink -f /sbin/init)" in
  *systemd*) pacman --noconfirm -S archlinux-keyring > /dev/null 2>&1
  ;;
  *) die "RAIS only works on systemd systems!"
esac

installpkg curl ca-certificates base-devel git zsh ntp

echo "Synchronizing system time to ensure successful and secure installation of software..."
ntpd -q -g >/dev/null 2>&1

adduserandpass || die "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

trap 'rm -f /etc/sudoers.d/larbs-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/larbs-temp

grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "/^#Color$/s/#//" /etc/pacman.conf
[ "$parallel" = "y" ] && {
  sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/" /etc/pacman.conf
  sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
}

manualinstall $aurhelper || die "Error installing AUR helper."

$aurhelper -Y --save --devel

pkginstall \
  xorg-server xorg-xinit xorg-xbacklight xorg-xprop xorg-xrandr \
  xclip xdotool xwallpaper \
  xdg-user-dirs \
  xf86-video-intel xf86-video-vesa \
  yt-dlp \
  zathura zathura-pdf-mupdf zathura-ps \
  bat btop dunst nsxiv \
  pamixer \
  pass \
  pipewire-pulse \
  lf ffmpegthumbnailer \
  fd ripgrep fzf tokei \
  bluez bluez-utils \
  zip unzip \
  clang cmake gdb valgrind \
  openssh \
  github-cli \
  gtk2 gtk3 gtk4 \
  thunar gvfs \
  hacksaw shotgun \
  dialog \
  man-db man-pages \
  mpd mpc ncmpcpp mpv \
  vi neovim python-pynvim python-pip \
  wget \
  discord

sudo -u "$name" systemctl --user enable mpd pipewire pipewire-pulse

echo "Installing AUR packages..."
sudo -u "$name" $aurhelper -S --noconfirm brave-bin ueberzugpp napi-bash xbanish

for repo in dwm st dmenu slstatus; do
  echo "Installing $repo..."
  sudo -u "$name" \
    git -C "/home/$name/.local/src" \
    clone --depth 1 --single-branch --no-tags -q \
    "https://github.com/Rentib/$repo.git"
  sudo -u "$name" \
    make -C "/home/$name/.local/src/$repo" -j \
    clean install >/dev/null 2>&1
done

putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -rf "/home/$name/.git/" "/home/$name/README.md" "/home/$name/LICENSE"
rm -rf "/home/$name/.config/nvim"
sudo -u "$name" \
  git -C "/home/$name/.config/" \
  clone --depth 1 --single-branch --no-tags -q \
  "https://github.com/Rentib/nvim.git"

install_nerd_fonts Hack

chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' >/etc/X11/xorg.conf.d/40-libinput.conf

echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-larbs-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu" >/etc/sudoers.d/01-larbs-cmds-without-password

echo "All done"
echo "Congrats! Provided that there were no errors, the script completed successfully."
echo "All programs and configuration files should be installed."
echo "You can now logout and log back in as your new user."
echo "~Rentib"
