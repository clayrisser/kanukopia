#!/bin/sh

export TMPDIR="${TMPDIR:-/tmp}"
if [ "$USER" = "" ]; then
    export USER="kopia"
fi
if [ "$HOME" = "" ] || [ "$HOME" = "/" ]; then
    export HOME="$TMPDIR/kopia"
fi
KANISTER_NAMESPACE="${KANISTER_NAMESPACE:-kanister}"

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
        shift
    fi
    if [ "$1" != "" ]; then
        WORKLOAD="$1"
        shift
    fi
    if [ "$1" != "" ]; then
        NAMESPACE="$1"
        shift
    fi
    if [ "$BLUEPRINT" = "" ]; then
        echo "blueprint not supplied" >&2
        exit 1
    fi
    if [ "$WORKLOAD" = "" ]; then
        echo "workload not supplied" >&2
        exit 1
    fi
    if [ "$NAMESPACE" = "" ]; then
        NAMESPACE="$(kubectl config view --minify --output 'jsonpath={..namespace}')"
        if [ "$NAMESPACE" = "" ]; then
            NAMESPACE=default
        fi
    fi
    _BLUEPRINT_NAME="$NAMESPACE.$BLUEPRINT"
    _NAMESPACE_ARG="--namespace $NAMESPACE"
    _KIND="$(kubectl get blueprint "$BLUEPRINT" -n "$NAMESPACE" -o json | \
        jq -r '.actions.backup.kind' | tr '[:upper:]' '[:lower:]')"
    if [ "$_KIND" = "statefulset" ]; then
        _STATEFULSET_ARG="--statefulset $NAMESPACE/$WORKLOAD"
    elif [ "$_KIND" = "deployment" ]; then
        _DEPLOYMENT_ARG="--deployment $NAMESPACE/$WORKLOAD"
    elif [ "$_KIND" = "daemonset" ]; then
        _DAEMONSET_ARG="--daemonset $NAMESPACE/$WORKLOAD"
    elif [ "$_KIND" = "replicaset" ]; then
        _REPLICASET_ARG="--replicaset $NAMESPACE/$WORKLOAD"
    else
        echo "unknown kind: $_KIND" >&2
        exit 1
    fi
    kanctl create actionset \
        --namespace "$KANISTER_NAMESPACE" \
        --blueprint "$_BLUEPRINT_NAME" \
        $_STATEFULSET_ARG \
        $_DEPLOYMENT_ARG \
        $_DAEMONSET_ARG \
        $_REPLICASET_ARG \
        --profile "$PROFILE" \
        --action backup "$@"
}

_restore() {
    PROFILE="${PROFILE:-kanister}"
    if [ "$1" != "" ]; then
        BLUEPRINT="$1"
        shift
    fi
    if [ "$1" != "" ]; then
        WORKLOAD="$1"
        shift
    fi
    if [ "$1" != "" ]; then
        FROM="$1"
        shift
    fi
    if [ "$1" != "" ]; then
        NAMESPACE="$1"
        shift
    fi
    if [ "$BLUEPRINT" = "" ]; then
        echo "blueprint not supplied" >&2
        exit 1
    fi
    if [ "$WORKLOAD" = "" ]; then
        echo "workload not supplied" >&2
        exit 1
    fi
    if [ "$NAMESPACE" = "" ]; then
        NAMESPACE="$(kubectl config view --minify --output 'jsonpath={..namespace}')"
        if [ "$NAMESPACE" = "" ]; then
            NAMESPACE=default
        fi
    fi
    _BLUEPRINT_NAME="$NAMESPACE.$BLUEPRINT"
    _NAMESPACE_ARG="--namespace $NAMESPACE"
    _KIND="$(kubectl get blueprint "$BLUEPRINT" -n "$NAMESPACE" -o json | \
        jq -r '.actions.backup.kind' | tr '[:upper:]' '[:lower:]')"
    if [ "$_KIND" = "statefulset" ]; then
        _STATEFULSET_ARG="--statefulset $NAMESPACE/$WORKLOAD"
    elif [ "$_KIND" = "deployment" ]; then
        _DEPLOYMENT_ARG="--deployment $NAMESPACE/$WORKLOAD"
    elif [ "$_KIND" = "daemonset" ]; then
        _DAEMONSET_ARG="--daemonset $NAMESPACE/$WORKLOAD"
    elif [ "$_KIND" = "replicaset" ]; then
        _REPLICASET_ARG="--replicaset $NAMESPACE/$WORKLOAD"
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
if [ "$_COMMAND" = "kopia" ]; then
    shift
    _kopia "$@"
    exit $?
elif [ "$_COMMAND" = "backup" ]; then
    shift
    _backup "$@"
    exit $?
elif [ "$_COMMAND" = "restore" ]; then
    shift
    _restore "$@"
    exit $?
else
    echo "unknown command" >&2
    exit 1
fi
