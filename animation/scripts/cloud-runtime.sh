#!/usr/bin/env bash
set -euo pipefail

# Per-process cloud initialization; leave HOME and credential bindings intact.
task_runtime_dir="${CARTOONREELS_RUNTIME_DIR:-/workspace/cartoonreels-runtime}"
mkdir -p "$task_runtime_dir/config" "$task_runtime_dir/cache" "$task_runtime_dir/runtime" "$task_runtime_dir/npm"
chmod 700 "$task_runtime_dir/runtime"
export XDG_CONFIG_HOME="$task_runtime_dir/config"
export XDG_CACHE_HOME="$task_runtime_dir/cache"
export XDG_RUNTIME_DIR="$task_runtime_dir/runtime"
export npm_config_cache="$task_runtime_dir/npm"
export NODE_USE_ENV_PROXY=1
export NODE_USE_SYSTEM_CA=1

if [[ $# -eq 0 ]]; then
  echo "Usage: bash scripts/cloud-runtime.sh <command> [arguments...]" >&2
  exit 2
fi
exec "$@"
