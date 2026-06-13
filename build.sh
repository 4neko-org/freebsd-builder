#!/bin/bash

set -euxo pipefail

OS_VERSION="$1"; shift
ARCHITECTURE="$1"; shift

packer init .

flags=(
  "-var"      "os_version=$OS_VERSION"
  "-var-file" "var_files/common.pkrvars.hcl"
  "-var-file" "var_files/$ARCHITECTURE.pkrvars.hcl"
)

export PACKER_GETTER_READ_TIMEOUT=60m

flags=(
  "-var"      "os_version=$OS_VERSION"
  "-var-file" "var_files/common.pkrvars.hcl"
  "-var-file" "var_files/$ARCHITECTURE.pkrvars.hcl"
)

if [ -e "var_files/$OS_VERSION/$ARCHITECTURE.pkrvars.hcl" ]; then
  flags+=("-var-file")
  flags+=("var_files/$OS_VERSION/$ARCHITECTURE.pkrvars.hcl")
fi

packer build "${flags[@]}" "$@" freebsd.pkr.hcl
