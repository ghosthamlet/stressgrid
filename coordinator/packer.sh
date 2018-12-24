#!/bin/bash
pushd packer/
packer build -var git_hash=$(git rev-parse --short=8 HEAD) packer.json
popd