#!/bin/sh

if [ -z "$PROFILE_JSON" ]; then
    echo "profile not supplied" >&2
    exit 1
fi
if [ -z "$PREFIX" ]; then
    echo "aws prefix not supplied" >&2
    exit 1
fi

export TMPDIR="${TMPDIR:-/tmp}"
if [ "$USER" = "" ]; then
    export USER="kopia"
fi
if [ "$HOME" = "" ]; then
    export HOME="$TMPDIR/kopia"
fi

AWS_BUCKET="$(echo $PROFILE_JSON | jq -r .Location.bucket)"
AWS_ENDPOINT="$(echo $PROFILE_JSON | jq -r .Location.endpoint)"
KOPIA_PASSWORD="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
export KOPIA_CHECK_FOR_UPDATES="false"
export AWS_ACCESS_KEY_ID="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
export AWS_SECRET_ACCESS_KEY="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.Secret)"
export AWS_REGION="$(echo $PROFILE_JSON | jq -r .Location.region)"

if ! kopia repository connect s3 \
    --bucket="$AWS_BUCKET" \
    --endpoint="$AWS_ENDPOINT" \
    --password="$KOPIA_PASSWORD" \
    --prefix="$PREFIX/"; then
    kopia repository create s3 \
        --bucket="$AWS_BUCKET" \
        --endpoint="$AWS_ENDPOINT" \
        --password="$KOPIA_PASSWORD" \
        --prefix="$PREFIX/"
fi
kopia "$@"
kopia repository disconnect
rm -rf "$HOME/.config/kopia"
