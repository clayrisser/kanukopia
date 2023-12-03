#!/bin/sh

if [ -z "$1" ]; then
    echo "profile not supplied" >&2
    exit 1
fi
PROFILE_JSON="$(echo $1 | base64 --decode)"
shift
if [ -z "$1" ]; then
    echo "aws prefix not supplied" >&2
    exit 1
fi
AWS_PREFIX="$1"
shift

AWS_BUCKET="$(echo $PROFILE_JSON | jq -r .Location.bucket)"
AWS_ENDPOINT="$(echo $PROFILE_JSON | jq -r .Location.endpoint)"
KOPIA_CHECK_FOR_UPDATES="false"
KOPIA_PASSWORD="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
export AWS_ACCESS_KEY_ID="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
export AWS_SECRET_ACCESS_KEY="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.Secret)"
export AWS_REGION="$(echo $PROFILE_JSON | jq -r .Location.region)"

if ! kopia repository connect s3 \
    --bucket="$AWS_BUCKET" \
    --endpoint="$AWS_ENDPOINT" \
    --password="$KOPIA_PASSWORD" \
    --prefix="$AWS_PREFIX/"; then
    kopia repository create s3 \
        --bucket="$AWS_BUCKET" \
        --endpoint="$AWS_ENDPOINT" \
        --password="$KOPIA_PASSWORD" \
        --prefix="$AWS_PREFIX/"
fi
kopia "$@"
kopia repository disconnect
