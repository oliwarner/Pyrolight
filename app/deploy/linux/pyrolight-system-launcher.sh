#!/bin/sh
APPDIR=/opt/pyrolight
LD_LIBRARY_PATH="$APPDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$APPDIR/bin/pyrolight" "$@"