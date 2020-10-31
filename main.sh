#!/bin/sh
# Jin's Auto Rice Boostrapping Script (JARBS)
# forked from Luke Smith's LARBS <luke@lukesmith.xyz>
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

while getopts ":a:r:b:p:h" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit ;;
	r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit ;;
	b) repobranch=${OPTARG} ;;
	p) progsfile=${OPTARG} ;;
	a) aurhelper=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
esac done

[ -z "$aurhelper" ] && aurhelper="yay"
[ -z "$repobranch" ] && repobranch="main"
[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/jcguu95/tilde.git"
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/jcguu95/JARBS/master/aux/progs.csv"

### FUNCTIONS ###

installpkg(){ pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 ;}

error() { printf "ERROR:\\n%s\\n" "$1"; exit;}

getuserandpass() { \
	echo -e "\nPrompts user for new username an password."
	echo "Enter a name for the user account:"
	read name || exit
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		echo "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _:"
		read name || exit
	done
	echo "Enter a password for that user:"
	read -s pass1 || exit
	echo "Retype password:"
	read -s pass2 || exit
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		echo "Passwords do not match. Enter password again:"
		read -s pass1 || exit
		echo "Retype password:"
		read -s pass2 || exit
	done ;}

usercheck() { \
	! (id -u "$name" >/dev/null) 2>&1 ||
	error "The user \`$name\` already exists on this system. JARBS can install for a user already existing. Exiting."
	}

adduserandpass() { \
	# Adds user `$name` with password $pass1.
	echo -e "\nAdding user \"$name\"..."
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2 ;}

refreshkeys() { \
	echo -e "\nRefreshing Arch Keyring..."
	pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
	}

newperms() { # Set special sudoers settings for install (or after).
	sed -i "/#JARBS/d" /etc/sudoers
	echo "$* #JARBS" >> /etc/sudoers ;}

maininstall() { # Installs all needed programs from main repo.
	echo "Installing \`$1\` ($n of $total). $1 $2"
	installpkg "$1"
	}

gitmakeinstall() {
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	echo "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2"
	sudo -u "$name" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return ; sudo -u "$name" git pull --force origin master;}
	cd "$dir" || exit
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return ;}

aurinstall() { \
	echo "Installing \`$1\` ($n of $total) from the AUR. $1 $2"
	echo "$aurinstalled" | grep -q "^$1$" && return
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
	}

pipinstall() { \
	echo "Installing the Python package \`$1\` ($n of $total). $1 $2"
	command -v pip || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
	}

installationloop() { \
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"I") ;; ## Ignored. Do nothing.
			"A") aurinstall "$program" "$comment" ;;
			"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			*) maininstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv ;}

putgitrepo() { # Downloads a gitrepo $1 with repobranch $2 and places the files in $3 only overwriting conflicts
	[ -z "$2" ] && branch="master" || branch="$repobranch"
	echo -e "\nPutting configs.."
	echo "Downloading gitrepo $1 from repobranch $2 and installing to $3.."
	echo "  (account and password might be required)"
	dir=$(mktemp -d)
	[ ! -d "$3" ] && mkdir -p "$3"
	chown -R "$name":wheel "$dir" "$3"
	sudo -u "$name" git clone --recursive -b "$branch" --depth 1 "$1" "$dir" >/dev/null 2>&1
	sudo -u "$name" cp -rfT "$dir" "$3"
	}

#### SPECIAL INSTALL METHODS
install_aurhelper() { # Installs $1 if not installed. Used only for AUR helper (e.g. yay) here.
	[ -f "/usr/bin/$1" ] || (
	echo "Installing \"$1\", an AUR helper..."
	cd /tmp || exit
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp || return) ;}

install_doomemacs() { # Installs doomemacs if not installed.
	echo "Installing doomemacs, a greate emacs distribution..."
	sudo -u "$name" git clone --depth 1 https://github.com/hlissner/doom-emacs /home/$name/.emacs.d || exit
	/bin/su -c "yes | /home/$name/.emacs.d/bin/doom install" - $name ;}

install_libxft_bgra() { # Installs libxft-bgra.
	echo "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes."
	yes | sudo -u "$name" $aurhelper -S libxft-bgra-git >/dev/null 2>&1
	}

systembeepoff() { echo "Getting rid of that retarded error beep sound..."
	rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}

finalize(){ \
	echo "DONE!"
	}



### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Check if user is root on Arch distro. Install dialog.
pacman --noconfirm --needed -Sy dialog || error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

# Get packages for installing and configuring other programs.
for x in curl base-devel git ntp zsh; do
	echo "Installing \`x\` which is required to install and configure other programs."
	installpkg "$x"
done

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exists. Exit with error."

### The rest of the script requires no user input.

# Add a new user.
adduserandpass && echo "done!" || error "Error adding username and/or password."

# Install the dotfiles in the plug directory
plugdir="/home/$name/.+PLUGS"
[ ! -d "$plugdir" ] && mkdir -p "$plugdir"
tildedir="$plugdir/tilde-git"
[ ! -d "$tildedir" ] && mkdir -p "$tildedir"
putgitrepo "$dotfilesrepo" "$repobranch" "$tildedir" 
echo "Running \"symlinker\" in the repo."
/bin/su -c "cd "$tildedir"; zsh "$tildedir/linker"" - "$name"

# Backup pacnew
[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

install_aurhelper $aurhelper || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop
# Most packages are installed at this point. Below are some patches to the system.

# Install doomemacs
install_doomemacs || error "Failed to install doomemacs."

# Install libxft-bgra
install_libxft_bgra || error "Failed to install ibxft-bgra."

# Most important command! Get rid of the beep!
systembeepoff

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# Tap to click
### [ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
###         Identifier "libinput touchpad catchall"
###         MatchIsTouchpad "on"
###         MatchDevicePath "/dev/input/event*"
###         Driver "libinput"
### 	# Enable left mouse button by tapping
### 	Option "Tapping" "on"
### EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

# Fix fluidsynth/pulseaudio issue.
### grep -q "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" /etc/conf.d/fluidsynth ||
### 	echo "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" >> /etc/conf.d/fluidsynth

# Start/restart PulseAudio.
### killall pulseaudio; sudo -u "$name" pulseaudio --start

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL #JARBS
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm"

# Last message! Install complete!
finalize
clear
