#!/bin/sh

export TMPDIR="${TMPDIR:-/tmp}"
if [ "$USER" = "" ]; then
    export USER="kopia"
fi
if [ "$HOME" = "" ] || [ "$HOME" = "/" ]; then
    export HOME="$TMPDIR/kopia"
fi

_kopia() {
    if [ -z "$PROFILE_JSON" ]; then
        echo "profile not supplied" >&2
        exit 1
    fi
    if [ -z "$PREFIX" ]; then
        echo "aws prefix not supplied" >&2
        exit 1
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
}

_backup() {
    PROFILE="${PROFILE:-kanister}"
    if [ "$1" != "" ]; then
        BLUEPRINT="$1"
    fi
    if [ "$2" != "" ]; then
        NAME="$2"
    fi
    if [ "$3" != "" ]; then
        NAMESPACE="$3"
    fi
    if [ "$BLUEPRINT" = "" ]; then
        echo "blueprint not supplied" >&2
        exit 1
    fi
    if [ "$NAME" = "" ]; then
        echo "name not supplied" >&2
        exit 1
    fi
    _BLUEPRINT_NAME="$NAMESPACE.$BLUEPRINT"
    if [ "$NAMESPACE" != "" ]; then
        _NAMESPACE_ARG="--namespace $NAMESPACE"
    fi
    _BLUEPRINT_JSON="$(kubectl get blueprint "$_BLUEPRINT_NAME" -n "$NAMESPACE" -o json)"
    _KIND="$(echo "$BLUEPRINT_JSON" | jq -r '.actions.backup.kind' | tr '[:upper:]' '[:lower:]')"
    if [ "$_KIND" = "statefulset" ]; then
        _STATEFULSET_ARG="--statefulset $NAME"
    elif [ "$_KIND" = "deployment" ]; then
        _DEPLOYMENT_ARG="--deployment $NAME"
    elif [ "$_KIND" = "daemonset" ]; then
        _DAEMONSET_ARG="--daemonset $NAME"
    elif [ "$_KIND" = "replicaset" ]; then
        _REPLICASET_ARG="--replicaset $NAME"
    else
        echo "unknown kind: $_KIND" >&2
        exit 1
    fi
    kanctl create actionset \
        $_NAMESPACE_ARG \
        $_STATEFULSET_ARG \
        $_DEPLOYMENT_ARG \
        $_DAEMONSET_ARG \
        $_REPLICASET_ARG \
        --blueprint "$_BLUEPRINT_NAME" \
        --profile "$PROFILE" \
        --action backup "$@"
}

_restore() {
    PROFILE="${PROFILE:-kanister}"
    if [ "$1" != "" ]; then
        BLUEPRINT="$1"
    fi
    if [ "$2" != "" ]; then
        NAME="$2"
    fi
    if [ "$3" != "" ]; then
        FROM="$3"
    fi
    if [ "$4" != "" ]; then
        NAMESPACE="$4"
    fi
    if [ "$BLUEPRINT" = "" ]; then
        echo "blueprint not supplied" >&2
        exit 1
    fi
    if [ "$NAME" = "" ]; then
        echo "name not supplied" >&2
        exit 1
    fi
    if [ "$FROM" = "" ]; then
        echo "from not supplied" >&2
        exit 1
    fi
    _BLUEPRINT_NAME="$NAMESPACE.$BLUEPRINT"
    if [ "$NAMESPACE" != "" ]; then
        _NAMESPACE_ARG="--namespace $NAMESPACE"
    fi
    _BLUEPRINT_JSON="$(kubectl get blueprint "$_BLUEPRINT_NAME" -n "$NAMESPACE" -o json)"
    _KIND="$(echo "$BLUEPRINT_JSON" | jq -r '.actions.restore.kind' | tr '[:upper:]' '[:lower:]')"
    if [ "$_KIND" = "statefulset" ]; then
        _STATEFULSET_ARG="--statefulset $NAME"
    elif [ "$_KIND" = "deployment" ]; then
        _DEPLOYMENT_ARG="--deployment $NAME"
    elif [ "$_KIND" = "daemonset" ]; then
        _DAEMONSET_ARG="--daemonset $NAME"
    elif [ "$_KIND" = "replicaset" ]; then
        _REPLICASET_ARG="--replicaset $NAME"
    else
        echo "unknown kind: $_KIND" >&2
        exit 1
    fi
    kanctl create actionset \
        $_NAMESPACE_ARG \
        $_STATEFULSET_ARG \
        $_DEPLOYMENT_ARG \
        $_DAEMONSET_ARG \
        $_REPLICASET_ARG \
        --blueprint "$_BLUEPRINT_NAME" \
        --profile "$PROFILE" \
        --action restore \
        --from "$FROM" "$@"
}

_COMMAND="$1"
shift
if [ "$_COMMAND" = "kopia" ]; then
    _kopia "$@"
    exit $?
elif [ "$_COMMAND" = "backup" ]; then
    _backup "$@"
    exit $?
elif [ "$_COMMAND" = "restore" ]; then
    _restore "$@"
    exit $?
else
    echo "unknown command" >&2
    exit 1
fi
