# Sourced by the shell tools: loads local.env and checks the required settings.
HADES_ROOT="${0:A:h:h}"
[[ -f "$HADES_ROOT/local.env" ]] && source "$HADES_ROOT/local.env"
: "${HADES_SRC:=$HOME/Library/Application Support/Steam/steamapps/common/Hades II/Hades II.app}"
hades_require() {
  for v in "$@"; do
    [[ -n "${(P)v}" ]] || { echo "error: $v is not set - copy local.env.example to local.env" >&2; exit 1; }
  done
}
