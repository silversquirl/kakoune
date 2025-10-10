$hello
$ hello
$@
${hi}
"hello"

if true; then
fi

if ((a + b > 0)); then
    :
fi

while ((a + b < 0)); do
    :
done

for ((a + b)); do
    :
done

${a#b}
${a#$b}
${a#${b}/c}

"${a#b}"
"${a#$b}"
"${a#${b}/c}"

echo hi

"$(echo hi)"
"$((a + b))"
"$(echo 'hello ${f}' >/dev/null)"

(( ))
(( ))
(
([
{
>
<


declare -A colors icons # provided by ./bash.nix

_nested() {
	# Check if we're inside a nested shell
	local pid="$PPID" comm
	while [ "$pid" -ne 1 ]; do
		# FIXME: filenames can have newlines in them
		IFS=' ' read -r pid comm < <(sed -E 's/^[0-9]+ \((.+)\) \S ([0-9]+) .*/\2 \1/' "/proc/$pid/stat")

		case "$comm" in
		# TODO: detect more shells
		# TODO: filter out non-interactive shells
		bash) return 0 ;;
		foot | code | *term*) break ;;
		esac
	done
	return 1
}

declare -A _prompt_features=(
	[dir]='Show current directory'
	[exit]='Show exit status'
	[icons]='Show icon prefixes'
	[history]='Synchronize history with other shells'
	[term]='Terminal integration for working directory, command output, etc'
)

declare -A _prompt_presets=(
	[slim]="none +exit +term"
)

_prompt_usage=$(
	array_tbl() {
		local -n array=_prompt_$1
		pr -Tms$'\t' <(printf '  %s\n' "${!array[@]}") <(printf '%s\n' "${array[@]}")
	}
	tabulate() { column -ts $'\t'; }
	cat <<-EOF
		Usage: prompt (+FEATURE | -FEATURE | PRESET)...

		Features:

		$(array_tbl features | tabulate)

		Presets:

		$({
			printf '  %s\t%s\n' \
				none 'All features disabled' \
				all 'All features enabled'
			array_tbl presets
		} | tabulate)
	EOF
)

prompt() {
	case "$1" in
	'' | -h | --help | help) {
		cat <<-EOF
			$_prompt_usage

			Current features:

			 $(for feat in "${!_prompt_features[@]}"; do
				((_prompt_features[$feat])) && printf ' %s' "$feat"
			done)

		EOF
	} >&2 ;;
	esac

	while (($#)); do
		local arg="$1"
		shift

		case "$arg" in
		+*)
			if [[ -z "${_prompt_features[${arg#+}]}" ]]; then
				echo "Unknown feature: $arg" >&2
				return 1
			fi
			_prompt_features[${arg#+}]=1
			;;

		-*)
			if [[ -z "${_prompt_features[${arg#-}]}" ]]; then
				echo "Unknown feature: $arg" >&2
				return 1
			fi
			_prompt_features[${arg#-}]=0
			;;

		all)
			for feat in "${!_prompt_features[@]}"; do
				_prompt_features[$feat]=1
			done
			;;

		none)
			for feat in "${!_prompt_features[@]}"; do
				_prompt_features[$feat]=0
			done
			;;

		*)
			if [[ -z "${_prompt_presets[$arg]}" ]]; then
				echo "Unknown preset: $arg" >&2
				return 1
			fi

			# shellcheck disable=SC2086
			set -- ${_prompt_presets[$arg]} "$@"
			;;
		esac
	done
}

# Enable all features by default
prompt all

_pre_exec_hook() {
	# Update history file
	if ((_prompt_features[history])); then
		# reset HISTFILE in case it was unset by `prompt -history`
		: "${HISTFILE:="$HOME/.bash_history"}"

		history -a # Save
		# history -c # Clear
		# history -r # Read
	else
		HISTFILE= # don't save history when exiting
	fi

	if ((_prompt_features[term])); then
		# OSC 133 denoting command execution start
		p+='\[\e]133;C\e\\\]'
	fi
}

_prompt_hook() {
	local exit_code=$?
	local p

	if ((_prompt_features[term])); then
		p+='\['
		# OSC 133 denoting command execution end
		p+='\e]133;D;'
		p+="$exit_code"
		p+='\e\\'

		# OSC 133 denoting prompt start
		p+='\e]133;A\e\\'

		# OSC 7 to inform terminal of pwd
		p+='\e]7;file://'
		p+=$(
			export HOSTNAME
			jq -jn '$ENV.HOSTNAME + $ENV.PWD | split("/") | map(@uri) | join("/")'
		)
		p+='\e\\'
		p+='\]'
	fi

	# Icon prefixes
	if ((_prompt_features[icons])); then
		if [[ -n "$SSH_CONNECTION" ]]; then
			p+="\[${colors[yellow]}\e[1m\]${icons['cod-remote']}\[\e[0m\] "
		fi
		if [[ -n "$IN_NIX_SHELL" ]]; then
			p+="\[${colors[nix_lightblue]}\]${icons['md-nix']}\[\e[0m\] "
		elif _nested; then
			p+="\[${colors[yellow]}\]${icons['md-arrow_down_right']}\[\e[0m\] "
		fi
	fi

	# Path
	((_prompt_features[dir])) && p+='\w '

	# Exit code color
	if ((_prompt_features[exit])); then
		if ((exit_code == 0)); then
			p+='\[\e[92m\]'
		else
			p+='\[\e[91m\]'
		fi
	fi

	# Prompt char and reset formatting
	p+='\$\[\e[0m\] '

	if ((_prompt_features[term])); then
		# OSC 133 denoting command start
		p+='\[\e]133;B\e\\\]'
	fi

	# Escape dollar sign, to counteract promptvars
	PS1="${p//'$'/'\$'}"
}

HISTCONTROL='ignoredups'
PROMPT_COMMAND+=(_prompt_hook)
PROMPT_DIRTRIM=2
shopt -s promptvars
PS0='$(_pre_exec_hook)'
PS1='$ '

# Terrible hack because ssh usually doesn't pass through COLORTERM correctly
if [[ -n "$SSH_CONNECTION" ]] && [[ -z "$COLORTERM" ]]; then
	case "$TERM" in
	foot)
		COLORTERM=truecolor
		export COLORTERM
		;;
	esac
fi

# implemented as a bashrc function rather than a script so it can detect builtins, aliases, functions, etc
loc() (
	set -o pipefail
	local mode='human'
	while getopts "aftpP" opt; do
		case $opt in
		a | f) ;;
		t) mode='type' ;;
		p | P) mode='path' ;;
		'?')
			echo "$opt: invalid option" >&2
			echo "usage: loc [-afptP] name [name ...]" >&2
			;;
		esac
	done

	case $mode in
	human)
		type "$@" | while IFS= read -r line; do
			while
				what="${line#"$1 is "}"
				[[ "$what" = "$line" ]]
			do
				# if no match, we've finished processing this arg, so move to the next one
				shift || return
			done

			local prefix='' suffix=''
			case "$what" in
			'hashed ('*')')
				what=${what#hashed (}
				what=${what%)}
				prefix="hashed ("
				suffix=")"
				;;
			esac

			printf '%s' "$1 is $prefix$what"
			while what="$(readlink "$what")"; do
				printf ' -> %s' "$what"
			done
			printf '%s\n' "$suffix"
		done
		;;

	path)
		type "$@" | while IFS= read -r line; do
			realpath "$line"
		done
		;;

	type) type "$@" ;;
	esac
)

# Allow using <c-space> for fzf's <c-t> binding (search for files or directories)
bind '"\C- ": "\C-t"'
