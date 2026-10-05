#!/usr/bin/env bash
set -euo pipefail

# GW_SH, else $GOWIN_HOME/IDE/bin/gw_sh, else gw_sh on PATH
if [ -z "${GW_SH:-}" ]; then
    if [ -n "${GOWIN_HOME:-}" ]; then
        GW_SH=$GOWIN_HOME/IDE/bin/gw_sh
    elif command -v gw_sh > /dev/null; then
        GW_SH=$(command -v gw_sh)
    else
        echo "gw_sh not found: set GOWIN_HOME to your Gowin EDA install directory (or GW_SH)" >&2
        exit 1
    fi
fi

export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-minimal}
export QT_OPENGL=${QT_OPENGL:-software}
export QT_QUICK_BACKEND=${QT_QUICK_BACKEND:-software}
export LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-1}
export LD_PRELOAD=${LD_PRELOAD:-/lib/x86_64-linux-gnu/libfreetype.so.6}

cd "$(dirname "$0")"
exec "$GW_SH" "${1:-build.tcl}"