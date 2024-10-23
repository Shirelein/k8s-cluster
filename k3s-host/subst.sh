#!/bin/bash

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source $SELF_DIR/variables.sh

eval "cat <<EOF
$(<$1)
EOF
"
