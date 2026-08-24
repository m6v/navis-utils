#!/usr/bin/bash

source_dir=$(dirname "$(realpath "$0")")

rsync -av --exclude="$source_dir/.*" $source_dir/ $1
