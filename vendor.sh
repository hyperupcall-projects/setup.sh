# shellcheck shell=bash

# @name bash-core
# @description Core functions for any Bash program

# @description Adds a handler for a particular `trap` signal or event. Noticeably,
# unlike the 'builtin' trap, this does not override any other existing handlers. The first argument
# to the handler is the exit code of the last command that ran before the particular 'trap'
# @arg $1 string Function to execute on an event. Integers are forbidden
# @arg $2 string Event signal
# @example
#   some_handler() { printf '%s\n' 'This was called on USR1! ^w^'; }
#   core.trap_add 'some_handler' 'USR1'
#   kill -USR1 $$
#   core.trap_remove 'some_handler' 'USR1'
core.trap_add() {
	core._util.init
	local function="$1"

	core._util.validate_args "$function" $#
	local signal_spec=
	for signal_spec in "${@:2}"; do
		core._util.validate_signal "$function" "$signal_spec"

		___global_trap_table___["$signal_spec"]="${___global_trap_table___[$signal_spec]}"$'\x1C'"$function"

		# rho (DUPLICATED)
		local global_trap_handler_name=
		printf -v global_trap_handler_name '%q' "core._trap_handler_${signal_spec}"

		if ! eval "$global_trap_handler_name() {
		local ___exit_code_original=\$?
		if core._util.trap_handler_common '$signal_spec' \"\$___exit_code_original\"; then
			return \$___exit_code_original
		else
			local ___exit_code_user=\$?
			core.print_error_fn \"User-provided trap handler spectacularly failed with exit code \$___exit_code_user\"
			return \$___exit_code_user
		fi
	}"; then
			core.panic 'Failed to eval function'
		fi
		# shellcheck disable=SC2064
		trap "$global_trap_handler_name" "$signal_spec"
	done; unset -v signal_spec
}

# @description Removes a handler for a particular `trap` signal or event. Currently,
# if the function doest not exist, it prints an error
# @arg $1 string Function to remove
# @arg $2 string Signal that the function executed on
# @example
#   some_handler() { printf '%s\n' 'This was called on USR1! ^w^'; }
#   core.trap_add 'some_handler' 'USR1'
#   kill -USR1 $$
#   core.trap_remove 'some_handler' 'USR1'
core.trap_remove() {
	core._util.init
	local function="$1"

	core._util.validate_args "$function" $#
	local signal_spec=
	for signal_spec in "${@:2}"; do
		core._util.validate_signal "$function" "$signal_spec"

		local -a trap_handlers=()
		local new_trap_handlers=
		IFS=$'\x1C' read -ra trap_handlers <<< "${___global_trap_table___[$signal_spec]}"
		for trap_handler in "${trap_handlers[@]}"; do
			if [ -z "$trap_handler" ] || [ "$trap_handler" = $'\x1C' ]; then
				continue
			fi

			if [ "$trap_handler" = "$function" ]; then
				continue
			fi

			new_trap_handlers+=$'\x1C'"$trap_handler"
		done; unset -v trap_handler

		___global_trap_table___["$signal_spec"]="$new_trap_handlers"

		# If there are no more user-provided trap-handlers (for the particular signal spec in the global trap table),
		# then remove our handler from 'trap'
		if [ -z "$new_trap_handlers" ]; then
			# rho (DUPLICATED)
			local global_trap_handler_name=
			printf -v global_trap_handler_name '%q' "core._trap_handler_${signal_spec}"
			trap -- "$signal_spec"
			unset -f "$global_trap_handler_name"
		fi
	done; unset -v signal_spec
}

# @description Modifies current shell options and pushes information to stack, so
# it can later be easily undone. Note that it does not check to see if your Bash
# version supports the option
# @arg $1 string Name of shopt action. Can either be `-u` or `-s`
# @arg $2 string Name of shopt name
# @example
#   core.shopt_push -s extglob
#   [[ 'variable' == @(foxtrot|golf|echo|variable) ]] && printf '%s\n' 'Woof!'
#   core.shopt_pop
core.shopt_push() {
	core._util.init
	local shopt_action="$1"
	local shopt_name="$2"

	if [ -z "$shopt_action" ]; then
		core.panic 'First argument cannot be empty'
	fi

	if [ -z "$shopt_name" ]; then
		core.panic 'Second argument cannot be empty'
	fi

	local -i previous_shopt_errcode=
	if shopt -q "$shopt_name"; then
		previous_shopt_errcode=$?
	else
		previous_shopt_errcode=$?
	fi

	if [ "$shopt_action" = '-s' ]; then
		if shopt -s "$shopt_name"; then :; else
			core.panic "Could not set shopt option" $?
		fi
	elif [ "$shopt_action" = '-u' ]; then
		if shopt -u "$shopt_name"; then :; else
			core.panic "Could not unset shopt option" $?
		fi
	else
		core.panic "Accepted actions are either '-s' or '-u'"
	fi

	if (( previous_shopt_errcode == 0)); then
		___global_shopt_stack___+=(-s "$shopt_name")
	else
		___global_shopt_stack___+=(-u "$shopt_name")
	fi
}

# @description Modifies current shell options based on most recent item added to stack.
# @noargs
# @example
#   core.shopt_push -s extglob
#   [[ 'variable' == @(foxtrot|golf|echo|variable) ]] && printf '%s\n' 'Woof!'
#   core.shopt_pop
core.shopt_pop() {
	core._util.init

	if (( ${#___global_shopt_stack___[@]} == 0 )); then
		core.panic 'Unable to pop as nothing is in the shopt stack'
	fi

	if (( ${#___global_shopt_stack___[@]} & 1 )); then
		core.panic 'Shopt stack is malformed'
	fi

	# Stack now guaranteed to have at least 2 elements (so the following accessors won't error)
	local shopt_action="${___global_shopt_stack___[-2]}"
	local shopt_name="${___global_shopt_stack___[-1]}"

	if shopt -u "$shopt_name"; then :; else
		core.panic 'Could not restore previous shopt option' $?
	fi

	___global_shopt_stack___=("${___global_shopt_stack___[@]::${#___global_shopt_stack___[@]}-2}")
}

# @description Use when a serious fault occurs. It will print the current ERR (if it exists)
core.panic() {
	local code='1'
	if [[ $1 =~ [0-9]+ ]]; then
		code=$1
	elif [ -n "$1" ]; then
		if [ -n "$2" ]; then
			code=$2
		fi
		if core._should_print_color 2; then
			printf "\033[1;31m\033[4m%s:\033[0m %s\n" 'Panic' "$1" >&2
		else
			printf "%s: %s\n" 'Panic' "$1" >&2
		fi
	fi

	if core.err_exists; then
		printf '%s\n' 'Error found:' >&2
		printf '%s\n' "  ERRCODE: $ERRCODE" >&2
		printf '%s\n' "  ERR: $ERR" >&2
	fi

	core.print_stacktrace
	exit "$code"
}

# @description Prints stacktrace
# @noargs
# @example
#  err_handler() {
#    local exit_code=$1 # Note that this isn't `$?`
#    core.print_stacktrace
#
#    # Note that we're not doing `exit $exit_code` because
#    # that is handled automatically
#  }
#  core.trap_add 'err_handler' ERR
core.print_stacktrace() {
	printf '%s\n' 'Stacktrace:'

	local old_cd="$PWD" cd_failed='no'
	local i=
	for ((i=0; i<${#FUNCNAME[@]}-1; ++i)); do
		local file="${BASH_SOURCE[$i]}"

		# If the 'cd' has previous failed, then do not attempt to 'cd' as the current
		# directory is not in '$old_cd' (so the 'cd' will almost certainly fail)
		if [ "$cd_failed" = 'no' ]; then
			# shellcheck disable=SC1007
			if CDPATH= cd -- "${file%/*}"; then
				file="$PWD/${file##*/}"
			else
				cd_failed='yes'
			fi
		fi

		printf '%s\n' "  in ${FUNCNAME[$i]} ($file:${BASH_LINENO[$i-1]})"

		# shellcheck disable=SC1007
		if ! CDPATH= cd -- "$old_cd"; then
			cd_failed='yes'
		fi
	done; unset -v i

	if [ "$cd_failed" = 'yes' ]; then
		# Do NOT 'core.panic'
		core.print_error "A 'cd' failed, so the stacktrace may include relative paths"
	fi
} >&2

# @description Print a fatal error message including the function name of the callee
# to standard error
# @arg $1 string message
core.print_fatal_fn() {
	local msg="$1"

	core.print_fatal "${FUNCNAME[1]}()${msg:+": "}$msg"
}

# @description Print an error message including the function name of the callee
# to standard error
# @arg $1 string message
core.print_error_fn() {
	local msg="$1"

	core.print_error "${FUNCNAME[1]}()${msg:+": "}$msg"
}

# @description Print a warning message including the function name of the callee
# to standard error
# @arg $1 string message
core.print_warn_fn() {
	local msg="$1"

	core.print_warn "${FUNCNAME[1]}()${msg:+": "}$msg"
}

# @description Print an informative message including the function name of the callee
# to standard output
# @arg $1 string message
core.print_info_fn() {
	local msg="$1"

	core.print_info "${FUNCNAME[1]}()${msg:+": "}$msg"
}
# @description Print a debug message including the function name of the callee
# to standard output
# @arg $1 string message
core.print_debug_fn() {
	local msg="$1"

	core.print_debug "${FUNCNAME[1]}()${msg:+": "}$msg"
}

# @description Print a fatal error message to standard error
# @arg $1 string message
core.print_fatal() {
	local msg="$1"

	if core._should_print_color 2; then
		printf "\033[1;35m%s:\033[0m %s\n" 'Fatal' "$msg" >&2
	else
		printf "%s: %s\n" 'Fatal' "$msg" >&2
	fi
}

# @description Print an error message to standard error
# @arg $1 string message
core.print_error() {
	local msg="$1"

	if core._should_print_color 2; then
		printf "\033[1;31m%s:\033[0m %s\n" 'Error' "$msg" >&2
	else
		printf "%s: %s\n" 'Error' "$msg" >&2
	fi
}

# @description Print a warning message to standard error
# @arg $1 string message
core.print_warn() {
	local msg="$1"

	if core._should_print_color 2; then
		printf "\033[1;33m%s:\033[0m %s\n" 'Warn' "$msg" >&2
	else
		printf "%s: %s\n" 'Warn' "$msg" >&2
	fi
}

# @description Print an informative message to standard output
# @arg $1 string message
core.print_info() {
	local msg="$1"

	if core._should_print_color 1; then
		printf "\033[1;32m%s:\033[0m %s\n" 'Info' "$msg"
	else
		printf "%s: %s\n" 'Info' "$msg"
	fi
}

# @description Print a debug message to standard output if the environment variable "DEBUG" is present
# @arg $1 string message
core.print_debug() {
	local msg="$1"

	if [[ -v DEBUG ]]; then
		printf "%s: %s\n" 'Debug' "$msg"
	fi
}

core.ifs_save() {
	local new_ifs="$1"

	___global_ifs_variable_saved___=$IFS
	IFS=$new_ifs
}

core.ifs_restore() {
	IFS=$___global_ifs_variable_saved___
}

# @description (DEPRECATED) Sets an error.
# @arg $1 Error code
# @arg $2 Error message
# @set number ERRCODE Error code
# @set string ERR Error message
core.err_set() {
	if (($# == 1)); then
		ERRCODE=1
		ERR=$1
	elif (($# == 2)); then
		ERRCODE=$1
		ERR=$2
	else
		core.panic 'Incorrect function arguments'
	fi

	if [ -z "$ERR" ]; then
		core.panic "Argument for 'ERR' cannot be empty"
	fi
}

# @description (DEPRECATED) Clears any of the global error state (sets to empty string).
# This means any `core.err_exists` calls after this _will_ `return 1`
# @noargs
# @set number ERRCODE Error code
# @set string ERR Error message
core.err_clear() {
	ERRCODE=
	ERR=
}

# @description (DEPRECATED) Checks if an error exists. If `ERR` is not empty, then an error
# _does_ exist
# @noargs
core.err_exists() {
	if [ -z "$ERR" ]; then
		return 1
	else
		return 0
	fi
}

# @description (DEPRECATED). Determine if color should be printed. Note that this doesn't
# use tput because simple environment variable checking heuristics suffice. Deprecated because this code
# has been moved to bash-std
core.should_output_color() {
	if core._should_print_color "$@"; then :; else
		return $?
	fi
}

# @description (DEPRECATED) Gets information from a particular package. If the key does not exist, then the value
# is an empty string. Deprecated as this code has been moved to bash-std
# @arg $1 string The `$BASALT_PACKAGE_DIR` of the caller
# @set directory string The full path to the directory
core.get_package_info() {
	unset REPLY; REPLY=
	local basalt_package_dir="$1"
	local key_name="$2"

	local toml_file="$basalt_package_dir/basalt.toml"

	if [ ! -f "$toml_file" ]; then
		core.panic "File '$toml_file' could not be found"
	fi

	local regex=$'^[ \t]*'"${key_name}"$'[ \t]*=[ \t]*[\'"](.*)[\'"]'
	while IFS= read -r line || [ -n "$line" ]; do
		if [[ $line =~ $regex ]]; then
			REPLY=${BASH_REMATCH[1]}
			break
		fi
	done < "$toml_file"; unset -v line
}

# @description (DEPRECATED) Initiates global variables used by other functions. Deprecated as
# this function is called automatically by functions that use global variables
# @noargs
core.init() {
	core._util.init
}

# @description (DEPRECATED) Prints stacktrace
# @see core.print_stacktrace
core.stacktrace_print() {
	core.print_warn "The function 'core.stacktrace_print' is deprecated in favor of 'core.print_stacktrace'"
	core.print_stacktrace "$@"
}

# @description (DEPRECATED) Print a error message to standard error including the function name
# of the callee to standard error and die
# @arg $1 string message
core.print_die_fn() {
	local msg="$1"

	core.print_die "${FUNCNAME[1]}()${msg:+": "}$msg"
}

# @description (DEPRECATED) Print a error message to standard error and die
# @arg $1 string message
core.print_die() {
	core.print_fatal "$1"
	exit 1
}

# @description Initialize global variables required for shopt and trap functions
# @internal
core._util.init() {
	if [ ${___global_bash_core_has_init__+x} ]; then
		return
	fi

	___global_bash_core_has_init__=
	declare -gA ___global_trap_table___=()
	declare -ga ___global_shopt_stack___=()
}

# @description Function that runs handlers for a particular signal
# @internal
core._util.trap_handler_common() {
	local signal_spec="$1"
	local code="$2"

	local trap_handlers=
	if [ -n "$BASH_VERSION" ]; then
		IFS=$'\x1C' read -ra trap_handlers <<< "${___global_trap_table___[$signal_spec]}"
	elif [ -n "$ZSH_VERSION" ]; then
		IFS=$'\x1C' read -rA trap_handlers <<< "${___global_trap_table___[$signal_spec]}"
	else
		core.panic 'bash-core only supports bash and zsh'
	fi

	local trap_handler=
	for trap_handler in "${trap_handlers[@]}"; do
		if [ -z "$trap_handler" ]; then
			continue
		fi

		if declare -f "$trap_handler" &>/dev/null; then
			if "$trap_handler" "$code"; then :; else
				return $?
			fi
		else
			core.print_warn "Trap handler function '$trap_handler' that was registered for signal '$signal_spec' no longer exists. Skipping" >&2
		fi
	done; unset -v trap_handler
}

# @internal
core._util.validate_args() {
	local function="$1"
	local arg_count="$2"

	if [ -z "$function" ]; then
		core.panic 'First argument must not be empty'
	fi

	if ((arg_count <= 1)); then
		core.panic 'Must specify at least one signal'
	fi
}

# @internal
core._util.validate_signal() {
	local function="$1"
	local signal_spec="$2"

	if [ -z "$signal_spec" ]; then
		core.panic 'Signal must not be an empty string'
	fi

	local regex='^[0-9]+$'
	if [[ "$signal_spec" =~ $regex ]]; then
		core.panic 'Passing numbers for the signal specs is prohibited'
	fi; unset -v regex
	signal_spec=${signal_spec#SIG}
	if ! declare -f "$function" &>/dev/null; then
		core.panic "Function '$function' is not defined"
	fi
}

# @description Determine if should print color, given a file descriptor
# @arg 1 File descriptor for terminal check
# @internal
core._should_print_color() {
	local fd="$1"

	if [ ${NO_COLOR+x} ]; then
		return 1
	fi

	if [[ $FORCE_COLOR == @(1|2|3) ]]; then
		return 0
	elif [[ $FORCE_COLOR == '0' ]]; then
		return 1
	fi

	if [ "$TERM" = 'dumb' ]; then
		return 1
	fi

	if [ -t "$fd" ]; then
		return 0
	fi

	return 1
}

# -------------------------------------------------------- #
#                          Cursor                          #
# -------------------------------------------------------- #

# @description Move the cursor position to a supplied row and column. Both default to `0` if not supplied
# @arg $1 int row
# @arg $1 int column
term.cursor_to() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 2 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local row="${1:-0}"
	local column="${2:-0}"

	# Note that 'f' instead of 'H' is the 'force' variant
	term._util_set_reply2 '\033[%s;%sH' "$row" "$column"
}

# @description Moves cursor position to a supplied _relative_ row and column. Both default to `0` if not supplied (FIXME: implement)
# @arg $1 int row
# @arg $1 int column
term.cursor_moveto() {
	:
}

# @description Moves the cursor up. Defaults to `1` if not supplied
# @arg $1 int count
term.cursor_up() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local count="${1:-1}"

	term._util_set_reply2 '\033[%sA' "$count"
}

# @description Moves the cursor down. Defaults to `1` if not supplied
# @arg $1 int count
term.cursor_down() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local count="${1:-1}"

	term._util_set_reply2 '\033[%sB' "$count"
}

# @description Moves the cursor forward. Defaults to `1` if not supplied
# @arg $1 int count
term.cursor_forward() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local count="${1:-1}"

	term._util_set_reply2 '\033[%sC' "$count"
}

# @description Moves the cursor backwards. Defaults to `1` if not supplied
# @arg $1 int count
term.cursor_backward() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local count="${1:-1}"

	term._util_set_reply2 '\033[%sD' "$count"
}

# @description Moves the cursor to the next line. Defaults to `1` if not supplied
# @arg $1 int count
term.cursor_line_next() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local count="${1:-1}"

	term._util_set_reply2 '\033[%sE' "$count"
}

# @description Moves the cursor to the previous line. Defaults to `1` if not supplied
# @arg $1 int count
term.cursor_line_prev() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local count="${1:-1}"

	term._util_set_reply2 '\033[%sF' "$count"
}

# FIXME: docs
# @description Moves the cursor ?
# @arg $1 int count
term.cursor_horizontal() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local count="${1:-1}"

	term._util_set_reply2 '\033[%sG' "$count"
}

# @description Saves the current cursor position
# @noargs
term.cursor_savepos() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	if [ "$TERM_PROGRAM" = 'Apple_Terminal' ]; then
		REPLY=$'\u001B7'
	else
		REPLY=$'\e[s'
	fi
	term._util_replyprint
}

# @description Restores cursor to the last saved position
# @noargs
term.cursor_restorepos() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	if [ "$TERM_PROGRAM" = 'Apple_Terminal' ]; then
		REPLY=$'\u001B8'
	else
		REPLY=$'\e[u'
	fi
	term._util_replyprint
}

# FIXME: docs
# @description Saves
# @noargs
term.cursor_save() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[7'
}

# FIXME: docs
# @description Restores
# @noargs
term.cursor_restore() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[8'
}

# @description Hides the cursor
# @noargs
term.cursor_hide() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[?25l'
}

# @description Shows the cursor
# @noargs
term.cursor_show() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[?25h'
}

# @description Reports the cursor position to the application as (as though typed at the keyboard)
# @noargs
term.cursor_getpos() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[6n'
}

# -------------------------------------------------------- #
#                           Erase                          #
# -------------------------------------------------------- #

# @description Erase from the current cursor position to the end of the current line
# @noargs
term.erase_line_end() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	# Same as '\e[0K'
	term._util_set_reply $'\e[K'
}

# @description Erase from the current cursor position to the start of the current line
# @noargs
term.erase_line_start() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[1K'
}

# @description Erase the entire current line
# @noargs
term.erase_line() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[2K'
}

# @description Erase the screen from the current line down to the bottom of the screen
# @noargs
term.erase_screen_end() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	# Same as '\e[0J'
	term._util_set_reply $'\e[J'
}

# @description Erase the screen from the current line up to the top of the screen
# @noargs
term.erase_screen_start() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[1J'
}

# @description Erase the screen and move the cursor the top left position
# @noargs
term.erase_screen() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[2J'
}

# @noargs
term.erase_saved_lines() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[3J'
}

# -------------------------------------------------------- #
#                          Scroll                          #
# -------------------------------------------------------- #

# @noargs
term.scroll_down() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	# REPLY=$'\e[T'
	term._util_set_reply $'\e[D'
}

# @noargs
term.scroll_up() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	# REPLY=$'\e[S'
	term._util_set_reply $'\e[M'
}

# -------------------------------------------------------- #
#                            Tab                           #
# -------------------------------------------------------- #

# @noargs
term.tab_set() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[H'
}

# @noargs
term.tab_clear() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[g'
}

# @noargs
term.tab_clearall() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[3g'
}

# -------------------------------------------------------- #
#                          Screen                          #
# -------------------------------------------------------- #

# @description Save screen
# @noargs
term.screen_save() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[?1049h'
}

# @description Restore screen
# @noargs
term.screen_restore() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 0 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\e[?1049l'
}

# -------------------------------------------------------- #
#                           Color                          #
# -------------------------------------------------------- #

# @description Construct reset
# @arg $1 string text
term.style_reset() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 '\e[0m%s' "$text"
}

# @description Construct bold
# @arg $1 string text
term.style_bold() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1m%s%s" "$text" "$end"
}

# @description Construct dim
# @arg $1 string text
term.style_dim() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[2m%s%s" "$text" "$end"
}

# @description Construct italic
# @arg $1 string text
term.style_italic() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[3m%s%s" "$text" "$end"
}

# @description Construct underline
# @arg $1 string text
term.style_underline() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[4m%s%s" "$text" "$end"
}

# @description Construct inverse
# @arg $1 string text
term.style_inverse() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[7m%s%s" "$text" "$end"
}

# @description Construct hidden
# @arg $1 string text
term.style_hidden() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[8m%s%s" "$text" "$end"
}

# @description Construct strikethrough
# @arg $1 string text
term.style_strikethrough() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[9m%s%s" "$text" "$end"
}

# @description Construct hyperlink
# @arg $1 string text
# @arg $2 string url
term.style_hyperlink() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 2 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"
	local url="$2"

	term._util_set_reply2 '\e]8;;%s\a%s\e]8;;\a' "$url" "$text"
}

# @description Construct black color
# @arg $1 string text
term.color_black() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[30m%s%s" "$text" "$end"
}

# @description Construct red color
# @arg $1 string text
term.color_red() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[31m%s%s" "$text" "$end"
}

# @description Construct green color
# @arg $1 string text
term.color_green() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[32m%s%s" "$text" "$end"
}

# @description Construct orange color
# @arg $1 string text
term.color_orange() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[33m%s%s" "$text" "$end"
}

# @description Construct blue color
# @arg $1 string text
term.color_blue() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[34m%s%s" "$text" "$end"
}

# @description Construct purple color
# @arg $1 string text
term.color_purple() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[35m%s%s" "$text" "$end"
}

# @description Construct cyan color
# @arg $1 string text
term.color_cyan() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[36m%s%s" "$text" "$end"
}

# @description Construct light gray color
# @arg $1 string text
term.color_light_gray() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[37m%s%s" "$text" "$end"
}

# @description Construct dark gray color
# @arg $1 string text
term.color_dark_gray() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1;30m%s%s" "$text" "$end"
}

# @description Construct light red color
# @arg $1 string text
term.color_light_red() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1;31m%s%s" "$text" "$end"
}

# @description Construct light green color
# @arg $1 string text
term.color_light_green() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1;32m%s%s" "$text" "$end"
}

# @description Construct yellow color
# @arg $1 string text
term.color_yellow() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1;33m%s%s" "$text" "$end"
}

# @description Construct light blue color
# @arg $1 string text
term.color_light_blue() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1;34m%s%s" "$text" "$end"
}

# @description Construct light purple color
# @arg $1 string text
term.color_light_purple() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1;35m%s%s" "$text" "$end"
}

# @description Construct light cyan color
# @arg $1 string text
term.color_light_cyan() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1;36m%s%s" "$text" "$end"
}

# @description Construct white color
# @arg $1 string text
term.color_white() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_pd 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	local text="$1"

	term._util_set_reply2 "\e[1;37m%s%s" "$text" "$end"
}

# -------------------------------------------------------- #
#                       Miscellaneous                      #
# -------------------------------------------------------- #

# @description Construct a beep
# @noargs
term.beep() {
	unset -v REPLY

	local flag_print='no' end=
	term._util_validate_p 1 "$@"
	shift "$REPLY_SHIFT" || core.panic 'Failed to shift'
	unset -v REPLY_SHIFT

	term._util_set_reply $'\a'
}

# -------------------------------------------------------- #
#                        Deprecated                        #
# -------------------------------------------------------- #

# @description (DEPRECATED) Construct hyperlink
# @arg $1 string text
# @arg $2 string url
term.hyperlink() {
	term.style_hyperlink "$@"
}

# @description (DEPRECATED) Construct bold
# @arg $1 string text
term.bold() {
	term.style_bold "$@"
}

# @description (DEPRECATED) Construct italic
# @arg $1 string text
term.italic() {
	term.style_italic "$@"
}

# @description (DEPRECATED) Construct underline
# @arg $1 string text
term.underline() {
	term.style_underline "$@"
}

# @description (DEPRECATED) Construct strikethrough
# @arg $1 string text
term.strikethrough() {
	term.style_strikethrough "$@"
}

term._util_validate_p() {
	local args_excluding_flags="$1"
	if ! shift; then core.panic 'Failed to shift'; fi

	if (($# - 1 > args_excluding_flags)); then
		core.panic 'Incorrect argument count'
	elif (($# - 1 == args_excluding_flags)); then
		if [[ $1 == -?(@(p|P)) ]]; then
			case $1 in
			*p*) flag_print='yes' ;;
			*P*) flag_print='yes-newline' ;;
			esac
			REPLY_SHIFT=1
		else
			core.panic 'Invalid flag'
		fi
	else
		REPLY_SHIFT=0
	fi

}

term._util_validate_pd() {
	local args_excluding_flags="$1"
	if ! shift; then core.panic 'Failed to shift'; fi

	if (($# - 1 == args_excluding_flags)); then
		if [[ $1 == -?(d|@(p|P)|d@(p|P)|@(p|P)d) ]]; then
			case $1 in
			*p*) flag_print='yes' ;;
			*P*) flag_print='yes-newline' ;;
			esac
			if [[ $1 == *d* ]]; then
				end=$'\e[0m'
			fi
			REPLY_SHIFT=1
		else
			core.panic 'Invalid flag'
		fi
	elif (($# > args_excluding_flags)); then
		core.panic 'Incorrect argument count'
	else
		REPLY_SHIFT=0
	fi
}

term._util_set_reply() {
	local value="$1"

	REPLY="$value"
	term._util_replyprint
}

term._util_set_reply2() {
	# shellcheck disable=SC2059
	printf -v REPLY "$@"
	term._util_replyprint
}

term._util_replyprint() {
	if [ "$flag_print" = 'yes' ]; then
		printf '%s' "$REPLY"
	elif [ "$flag_print" = 'yes-newline' ]; then
		printf '%s\n' "$REPLY"
	fi
}
