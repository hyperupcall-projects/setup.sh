# shellcheck shell=bash

# shellcheck disable=SC2016
{
	# Set options.
	set -e
	if [ -n "$BASH_VERSION" ]; then
		# shellcheck disable=SC3044
		shopt -s extglob globstar shift_verbose
	elif [ -n "$ZSH_VERSION" ]; then
		:
	elif [ -n "$KSH_VERSION" ]; then
		set -o globstar
	fi

	declare -ga _CURL_CONFIG_SETUP=(--proto '=https' --tlsv1.2 --show-error --location)

	if [ -n "${DEBUG+x}" ]; then
		err_handler() {
			exit_code=$1
			core.print_stacktrace
		}
		core.trap_add 'err_handler' ERR EXIT
	fi
}

_main() {
	local orig_dir="$PWD"
	g_temp_dir=$(mktemp -d --suffix="-dotfiles")
	cd "$g_temp_dir"
	_setup_cleanup1() {
		cd /
		rm -rf "$g_temp_dir"
	}
	core.trap_add '_setup_cleanup1' ERR EXIT

	util.get_script_path
	local script_path=$REPLY

	if [ -n "$g_name" ]; then
		core.print_die "Expected file \"$script_path\" to not have variable \"g_name\""
	fi

	main "$@"

	cd "$orig_dir"
	rm -rf "$g_temp_dir"
}

_setup() {
	util.get_script_path
	local script_path=$REPLY

	if [ -z "$g_name" ]; then
		core.print_die "Expected file \"$script_path\" to have variable \"g_name\""
	fi

	if [ "$g_disable" = 'true' ]; then
		core.print_warn "Skipping \"$g_name\" because it is disabled"
		return 0
	fi

	if declare -f main &>/dev/null; then
		core.print_die "Expected file \"$script_path\" to not have function \"main\""
	fi

	util.install_by_setup "$@" "$g_name"
}

util.install_by_setup() {
	local orig_dir2="$PWD"
	g_temp_dir2=$(mktemp -d --suffix="-dotfiles")
	cd "$g_temp_dir2"
	_setup_cleanup2() {
		cd /
		rm -rf "$g_temp_dir2"
	}
	core.trap_add '_setup_cleanup2' ERR EXIT

	local flag_configure_only=no
	local flag_dev=false
	local flag_fn_prefix=install
	local flag_force=no
	local flag_is_script=no
	local flag_help=no
	local flag_no_confirm=no
	local flag_no_install_check=no
	local program_name=

	local arg=
	for arg; do
		case $arg in
		--configure-only)
			flag_configure_only=yes
			shift
			;;
		--dev)
			flag_dev=true
			;;
		--fn-prefix*)
			core.shopt_push -s nullglob on
			flag_fn_prefix=${arg#--fn-prefix}
			flag_fn_prefix=${flag_fn_prefix#=}
			core.shopt_pop
			if [ -z "$flag_fn_prefix" ]; then
				core.print_die "Expected a value for --fn-prefix"
			fi
			shift
			;;
		--force)
			flag_force=yes
			shift
			;;
		--help)
			flag_help=yes
			shift
			;;
		--is-script)
			flag_is_script=yes
			shift
			;;
		--no-confirm)
			flag_no_confirm=yes
			shift
			;;
		--no-install-check)
			flag_no_install_check=yes
			shift
			;;
		--)
			break
			;;
		-*)
			core.print_die "Invalid flag \"$arg\""
			;;
		esac
	done
	unset -v arg

	if [ -n "$1" ]; then
		program_name="$1"
	else
		core.print_die "Expected program name as first argument"
	fi

	if [ "$flag_help" = 'yes' ]; then
		local exec=
		if [ "$flag_is_script" = 'yes' ]; then
			util.get_script_path
			local script_path=$REPLY

			exec=~${script_path/#"$HOME"/}
		else
			exec='util.install_by_setup'
		fi

		cat <<EOF
$exec [--configure-only] [--dev] [--force] [--help] [--no-confirm] [--no-install-check]
EOF
		return
	fi

	if ! declare -f "$flag_fn_prefix.installed" &>/dev/null && [ "$flag_no_install_check" = no ]; then
		core.print_die "Expected file \"$script_path\" to have function \"$flag_fn_prefix.installed\""
		
	fi

	# Configure first.
	if declare -f "$flag_fn_prefix.configure" &>/dev/null; then
		core.print_info "Configuring '$program_name'..."
		local orig_dir3="$PWD"
		g_temp_dir3=$(mktemp -d --suffix="-dotfiles")
		cd "$g_temp_dir3"
		_setup_cleanup3() {
			cd /
			rm -rf "$g_temp_dir3"
		}
		core.trap_add '_setup_cleanup3' ERR EXIT

		(
			"$flag_fn_prefix.configure" "$@"
		)

		cd "$orig_dir3"
		rm -rf "$g_temp_dir3"
	fi

	if [ "$flag_configure_only" = 'yes' ]; then
		return
	fi

	if [ "$flag_no_install_check" = no ] && "$flag_fn_prefix.installed" && [ "$flag_force" = no ]; then
		core.print_info "$program_name is already installed"
		return
	fi

	if [ "$flag_no_confirm" = 'no' ]; then
		if [ "$flag_no_install_check" = no ] && "$flag_fn_prefix.installed"; then
			# Variable "flag_force" is "yes".
			core.print_info "Would you like to force install \"$program_name\"?"
		else
			core.print_info "Program \"$program_name\" not fully installed"
		fi
		if ! util.confirm 'Fix?'; then
			return
		fi
	fi

	(
		# A list of 'os-release' files can be found at https://github.com/which-distro/os-release.
		# In some distros, like CachyOS, /usr/lib/os-release has the wrong contents.
		source /etc/os-release

		# Normalize values that are missing or have bad capitalization.
		[[ "$ID" == +(arch|blackarch) ]] && ID_LIKE=arch
		[ "$ID" = 'debian' ] && ID_LIKE=debian
		[ "$ID" = 'Deepin' ] && ID=deepin
		[[ "$ID_LIKE" == +(*debian*|*ubuntu*) ]] && ID_LIKE=ubuntu
		[[ "$ID_LIKE" == *debian* ]] && ID_LIKE=debian
		[[ "$ID_LIKE" == +(*fedora*|*centos*|*rhel*) ]] && ID_LIKE=fedora
		[[ "$ID_LIKE" == +(*opensuse*|*suse*) ]] && ID_LIKE=opensuse

		local ran_function=no
		local id=
		for id in source "$ID" "$ID_LIKE" any; do
			if declare -f "$flag_fn_prefix.$id" &>/dev/null; then
				ran_function=yes
				if [ "$flag_no_install_check" = yes ]; then
					"$flag_fn_prefix.$id" "$@"
					break
				fi

				if ! "$flag_fn_prefix.installed" || [ "$flag_force" = 'yes' ]; then
					"$flag_fn_prefix.$id" "$@"
					break
				fi
			fi
		done
		unset -v id
		if [ "$ran_function" = no ]; then
			local text="\"$flag_fn_prefix.$ID\" or \"$flag_fn_prefix.$ID_LIKE\""
			if [ "$ID" = "$ID_LIKE" ]; then
				text="\"$flag_fn_prefix.$ID\""
			fi
			core.print_die "Function not found: $text"
		fi
	)
	# When installation fails
	if (($? > 0)); then
		core.print_die "Failed to install \"$program_name\""
	fi

	if [ "$flag_no_install_check" = no ] && ! "$flag_fn_prefix.installed"; then
		core.print_die "Attempted to install \"$program_name\", but failed"
	fi

	if declare -f "$flag_fn_prefix.caveats" &>/dev/null; then
		"$flag_fn_prefix.caveats"
	fi

	cd "$orig_dir2"
	rm -rf "$g_temp_dir2"
}

util.install_by_setup_distro_package() {
	local name="$1"
	local package="$2"
	local command="$3"
	shift 3

	_by_distro_package.debian() {
		sudo apt-get install -y "$package"
	}
	_by_distro_package.ubuntu() {
		_by_distro_package.debian "$@"
	}
	_by_distro_package.fedora() {
		sudo dnf install -y "$package"
	}
	_by_distro_package.opensuse() {
		sudo zypper -n install "$package"
	}
	_by_distro_package.arch() {
		yay -Syu --noconfirm "$package"
	}
	_by_distro_package.installed() {
		command -v "$command" &>/dev/null
	}
	util.install_by_setup --fn-prefix=_by_distro_package "$@" "$name"
}

pkg.add_apt_key() {
	local source_url=$1
	local dest_file="$2"

	if [ ! -f "$dest_file" ] || [ ! -s "$dest_file" ]; then
		core.print_info "Downloading and writing key to $dest_file"
		sudo mkdir -p "${dest_file%/*}"
		curl "${_CURL_CONFIG_SETUP[@]}" "$source_url" |
			sudo tee "$dest_file" >/dev/null
	fi
}

pkg.add_apt_repository() {
	local dest_file="$1"
	local content="$2"

	sudo mkdir -p "${dest_file%/*}"
	sudo rm -f "${dest_file%.*}.list"
	sudo rm -f "$dest_file"

	if [ "${content::1}" != $'\n' ]; then
		core.print_die "Failed to find starting newline in content for \"$dest_file\""
	fi

	local line= file_content=
	if [[ $content == *@(\'|\"|\\)* ]]; then
		core.print_die "Invallid character found in content for \"$dest_file\""
	fi
	while IFS= read -r line; do
		line="${line#"${line%%[![:space:]]*}"}"
		if [[ $line != @(Types|URIs|Suites|Components|Architectures|signed-by):* ]]; then
			core.print_die "Invalid start of entry in content for \"$dest_file\""
		fi
		file_content+="$line"$'\n'
	done <<<"${content:1}"

	printf '%s' "${file_content::-1}" | sudo tee "$dest_file" >/dev/null
}

pkg.add_dnf_repository() {
	local repo_url="$1"
	local repo_name=${repo_url##*/}

	sudo rm -f "/etc/yum.repos.d/$repo_name"

	local dnf_version=
	dnf_version=$(dnf --version)
	if [[ $dnf_version == *dnf5* ]]; then
		sudo dnf install -y dnf-plugins-core
		sudo dnf config-manager addrepo --overwrite --from-repofile="$repo_url"
	else
		sudo dnf install -y dnf-plugins-core
		sudo dnf config-manager --add-repo "$repo_url"
	fi
}

util.clone() {
	local dir="$1"
	local repo="$2"
	shift 2

	if [ ! -d "$dir" ]; then
		core.print_info "Cloning '$repo' to $dir"
		git clone "$repo" "$dir" "$@" # lint-ignore:no-git-clone

		local git_remote=
		git_remote=$(git -C "$dir" remote)
		if [ "$git_remote" = 'origin' ]; then
			git -C "$dir" remote rename origin me
		fi
		unset -v git_remote
	fi
}

util.confirm() {
	local message=${1:-Confirm?}
	local args=('-rN1')
	if [ -n "$ZSH_VERSION" ]; then
		args=('-rsk')
	fi

	local input=
	until [[ $input =~ ^[yYnN]$ ]]; do
		printf '%s' "$message "
		read -r "${args[@]}"
		input=$REPLY
		printf '\n'
	done

	if [[ $input =~ ^[yY]$ ]]; then
		return 0
	else
		return 1
	fi
}

util.get_latest_github_release() {
	unset -v REPLY
	REPLY=

	local flag_min_release_age=$((24 * 14)) # 14 days.

	local arg=
	for arg; do
		case $arg in
		--min-release-age*)
			flag_min_release_age=${arg#--min-release-age}
			flag_min_release_age=${flag_min_release_age#=}
			if [ -z "$flag_min_release_age" ]; then
				core.print_die "Expected a value for --min-release-age"
			fi
			shift
			;;
		-*)
			core.print_die "Invalid flag \"$arg\""
			;;
		*)
			break
			;;
		esac
	done
	unset -v arg

	local repo="$1"

	local -a authorization=()
	if [ -n "$GITHUB_TOKEN" ]; then
		authorization=(-H "Authorization: token $GITHUB_TOKEN")
	else
		core.print_warn "Expected GITHUB_TOKEN to be non-empty"
	fi

	core.print_info "Fetching releases for $repo"
	local latest_tag_name=
	latest_tag_name=$(curl "${_CURL_CONFIG_SETUP[@]}" "${authorization[@]}" \
		"https://api.github.com/repos/$repo/releases/latest" | jq -r '.tag_name')

	local tag_name=
	if [ -z "$flag_min_release_age" ]; then
		tag_name=$latest_tag_name
		core.print_info "Using version $tag_name"
	else
		local page=1
		while true; do
			local releases=
			releases=$(curl "${_CURL_CONFIG_SETUP[@]}" "${authorization[@]}" \
				"https://api.github.com/repos/$repo/releases?per_page=100&page=$page")

			local count=
			count=$(printf '%s' "$releases" | jq 'length')

			if (( count == 0 )); then
				core.print_die "No releases found for $repo older than $flag_min_release_age hours"
			fi

			tag_name=$(printf '%s' "$releases" | jq -r \
				--argjson min_age_hours "$flag_min_release_age" \
				'[.[] | select(.prerelease == false and .draft == false and ((now - (.published_at | fromdateiso8601)) >= ($min_age_hours * 3600)))] | first | .tag_name // empty')

			if [ -n "$tag_name" ]; then
				break
			fi

			page=$((page + 1))
		done

		if [ "$tag_name" = "$latest_tag_name" ]; then
			core.print_info "Using version $tag_name (is latest, older than $flag_min_release_age hours)"
		else
			core.print_info "Using version $tag_name (not latest, $latest_tag_name is too recent)"
		fi
	fi

	REPLY=$tag_name
}

util.update_system() {
	update_system.debian() {
		sudo apt-get -y update
		sudo apt-get -y upgrade
	}
	update_system.ubuntu() {
		update_system.debian "$@"
	}
	update_system.neon() {
		sudo apt-get -y update
		if sudo pkcon -y update; then :; else
			# Exit code for "Nothing useful was done".
			if (($? != 5)); then
				core.print_die "Failed to run 'pkgcon'"
			fi
		fi
	}
	update_system.fedora() {
		sudo dnf -y update
	}
	update_system.opensuse() {
		sudo zypper -n update
	}
	update_system.arch() {
		sudo pacman -Syyu --noconfirm
	}
	update_system.installed() {
		# Always update.
		return 1
	}

	util.install_by_setup --fn-prefix=update_system --no-install-check 'util.update_system'
}

util.install_by_setup_package() {
	local package="$1"

	install_package.debian() {
		sudo apt-get install -y "$package"
	}
	install_package.fedora() {
		sudo dnf install -y "$package"
	}
	install_package.opensuse() {
		sudo zypper -n install "$package"
	}
	install_package.arch() {
		sudo pacman -Syu --noconfirm "$package"
	}

	util.install_by_setup --fn-prefix=install_package
}

util.uninstall_package() {
	local package="$1"

	uninstall_package.debian() {
		sudo apt-get remove -y "$package"
	}
	uninstall_package.fedora() {
		sudo dnf remove -y "$package"
	}
	uninstall_package.opensuse() {
		sudo zypper -n remove "$package"
	}
	uninstall_package.arch() {
		sudo pacman -R --noconfirm "$package"
	}

	util.install_by_setup --fn-prefix=uninstall_package
}

util.if_file_sourced() {
	if [ -n "$BASH_VERSION" ]; then
		if [ "${BASH_SOURCE[1]}" = "$0" ]; then
			return 1
		else
			return 0
		fi
	elif [ -n "$ZSH_VERSION" ]; then
		case $ZSH_EVAL_CONTEXT in
		toplevel:file*) return 0 ;;
		*) return 1 ;;
		esac
	else
		return 0
	fi
}

util.get_script_path() {
	if [ -n "$ZSH_VERSION" ]; then
		REPLY=$ZSH_ARGZERO
	else
		REPLY=$0
	fi
}

util.write_shellfile() {
	local name="$1"
	shift

	while (($# >= 2)); do
		local shell="${1#--}"
		local content="$2"
		shift 2

		local dirname=
		case $shell in
		sh) dirname='shell.d' ;;
		bash) dirname='bash.d' ;;
		zsh) dirname='zsh.d' ;;
		ksh) dirname='ksh.d' ;;
		fish) dirname='fish.d' ;;
		elvish) dirname='elvish.d' ;;
		tcsh) dirname='tcsh.d' ;;
		*) core.print_die "Invalid shell \"$shell\"" ;;
		esac

		local output_file="${XDG_CONFIG_HOME:-$HOME/.config}/$shell/$dirname/_$name.$shell"
		core.print_debug "Writing to \"~${output_file#"$HOME"}\""
		mkdir -p "${output_file%/*}"
		: >"$output_file"
		local line=
		while IFS= read -r line; do
			line="${line#"${line%%[![:space:]]*}"}"
			printf '%s\n' "$line" >>"$output_file"
		done <<<"$content"
		unset -v line
	done
}

util.remove_shellfile() {
	local name="$1"

	local shell=
	for shell in sh bash zsh ksh fish elvish tcsh; do
		local output_file="${XDG_CONFIG_HOME:-$HOME/.config}/$shell/$dirname/_$name.$shell"
		if [ -f "$output_file" ]; then
			core.print_info "Removing from \"$output_file\""
			rm -f "$output_file"
		fi
	done
}

util.write_promptfile() {
	local name="$1"
	shift

	while (($# >= 2)); do
		local shell="${1#--}"
		local content="$2"
		shift 2

		local dirname=
		case $shell in
		sh) dirname='shell.d' ;;
		bash) dirname='bash.d' ;;
		zsh) dirname='zsh.d' ;;
		ksh) dirname='ksh.d' ;;
		fish) dirname='fish.d' ;;
		elvish) dirname='elvish.d' ;;
		tcsh) dirname='tcsh.d' ;;
		*) core.print_die "Invalid shell \"$shell\"" ;;
		esac

		local output_file="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-shell-prompts/${shell%.d}/_$name.txt"
		core.print_debug "Writing to \"~${output_file#"$HOME"}\""
		mkdir -p "${output_file%/*}"
		: >"$output_file"
		local line=
		while IFS= read -r line; do
			line="${line#"${line%%[![:space:]]*}"}"
			printf '%s\n' "$line" >>"$output_file"
		done <<<"$content"
		unset -v line
	done
}
