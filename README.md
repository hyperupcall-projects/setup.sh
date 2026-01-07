# setup.sh

`setup.sh` simplifies installing software for Linux.

Below is an example. It can be placed at, say, `~/scripts/setup/vscode.sh`.

```bash
#!/usr/bin/env bash

source ~/.dotfiles/vendor/setup/setup.sh

declare -g g_name='VSCode and VSCode Insiders'

main() {
	util.install_by_setup "$@"
}

install.arch() {
	yay -S visual-studio-code-bin visual-studio-code-insiders-bin
}

install.debian() {
	local gpg_file="/etc/apt/keyrings/microsoft.asc"

	pkg.add_apt_key \
		'https://packages.microsoft.com/keys/microsoft.asc' \
		"$gpg_file"

	pkg.add_apt_repository \
		'/etc/apt/sources.list.d/vscode.sources' "
			Types: deb
			URIs: https://packages.microsoft.com/repos/code
			Suites: stable
			Components: main
			Architectures: $(dpkg --print-architecture)
			signed-by: $gpg_file"

	sudo apt-get -y update
	sudo apt-get -y install code code-insiders
}

install.ubuntu() {
	install.debian "$@"
}

install.fedora() {
	sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
	printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" \
		| sudo tee '/etc/yum.repos.d/vscode.repo' >/dev/null

	sudo dnf -y update
	sudo dnf -y install code code-insiders
}

install.opensuse() {
	sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
	printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" \
		| sudo tee '/etc/zypp/repos.d/vscode.repo' >/dev/null

	sudo zypper refresh
	sudo zypper -n install code code-insiders
}

installed() {
	command -v code &>/dev/null && command -v code-insiders &>/dev/null
}

util.if_file_sourced || _setup "$@"
```

Some APIs are more experimental:

```sh
configure() {
	util.write_shellfile 'dircolors' \
		--bash 'eval "$(dircolors -b "$XDG_CONFIG_HOME/dircolors/dir_colors")"' \
		--zsh 'eval "$(dircolors -b "$XDG_CONFIG_HOME/dircolors/dir_colors")"' \
		--tcsh 'eval "$(dircolors -c "$XDG_CONFIG_HOME/dircolors/dir_colors")"'
}

caveats() {
	cat <<"EOF"
To  fix the scollbar, write to `~/.config/gtk-4.0/settings.ini`:

gtk-overlay-scrolling=false
gtk-primary-button-warps-slider = false

More information: https://github.com/dbeaver/dbeaver/issues/10950
EOF
}
```

See more examples [here](https://github.com/hyperupcall/dotfiles/tree/trunk/os-unix/setup-apps), [here](https://github.com/hyperupcall/dotfiles/tree/trunk/os-unix/setup-devtool), and [here](https://github.com/hyperupcall/dotfiles/tree/trunk/os-unix/setup-other).

This isn't quite ready to be used yet. I have to remove hardcoded `~/.dotfiles` paths and vendor dependencies like `bash-core` and `bash-term` in this repository.
