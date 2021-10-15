#!/bin/bash

mkdir -p ~/.terraform

zcat <(curl -q $(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '"\(.current_download_url)/terraform_\(.current_version)_linux_amd64.zip"')) > ~/.terraform/terraform

chmod +x ~/.terraform/terraform
