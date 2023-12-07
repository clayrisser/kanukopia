#!/bin/sh

export TMPDIR="${TMPDIR:-/tmp}"
if [ "$USER" = "" ]; then
    export USER="kopia"
fi
if [ "$HOME" = "" ] || [ "$HOME" = "/" ]; then
    export HOME="$TMPDIR/kopia"
fi
KANISTER_NAMESPACE="${KANISTER_NAMESPACE:-kanister}"

_main() {
    if [ "$_COMMAND" = "kopia" ]; then
        _kopia "$@"
    elif [ "$_COMMAND" = "backup" ]; then
        _backup "$@"
    elif [ "$_COMMAND" = "restore" ]; then
        _restore "$@"
    fi
}

_kopia() {
    if [ "$PROFILE_JSON" = "" ]; then
        echo "profile json not supplied" >&2
        exit 1
    fi
    if [ "$PREFIX" = "" ]; then
        echo "aws prefix not supplied" >&2
        exit 1
    fi
    if [ "$KOPIA_PASSWORD" = "" ]; then
        KOPIA_PASSWORD="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
    fi
    _AWS_BUCKET="$(echo $PROFILE_JSON | jq -r .Location.bucket)"
    _AWS_ENDPOINT="$(echo $PROFILE_JSON | jq -r .Location.endpoint)"
    export KOPIA_CHECK_FOR_UPDATES="false"
    export AWS_ACCESS_KEY_ID="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
    export AWS_SECRET_ACCESS_KEY="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.Secret)"
    export AWS_REGION="$(echo $PROFILE_JSON | jq -r .Location.region)"
    if ! _exec kopia repository connect s3 \
        --bucket="$_AWS_BUCKET" \
        --endpoint="$_AWS_ENDPOINT" \
        --password="$KOPIA_PASSWORD" \
        --prefix="$PREFIX/"; then
        _exec kopia repository create s3 \
            --bucket="$_AWS_BUCKET" \
            --endpoint="$_AWS_ENDPOINT" \
            --password="$KOPIA_PASSWORD" \
            --prefix="$PREFIX/"
    fi
    _exec kopia "$@"
    _exec kopia repository disconnect
    _exec rm -rf "$HOME/.config/kopia"
}

_backup() {
    while test $# -gt 0; do
        case "$1" in
        -h | --help)
            _backup_help
            exit
            ;;
        -p | --profile)
            shift
            _PROFILE="$1"
            shift
            ;;
        -w | --workload)
            shift
            _WORKLOAD="$1"
            shift
            ;;
        -n | --namespace)
            shift
            _NAMESPACE="$1"
            shift
            ;;
        -x | --kopia-password)
            shift
            _KOPIA_PASSWORD="$1"
            shift
            ;;
        --prefix)
            shift
            _PREFIX="$1"
            shift
            ;;
        *)
            break
            ;;
        esac
    done
    if [ "$_PROFILE" = "" ]; then
        _PROFILE=kanister
    fi
    if [ "$1" != "" ]; then
        _BLUEPRINT="$1"
        shift
    fi
    if [ "$_NAMESPACE" = "" ]; then
        _NAMESPACE="$(kubectl config view --minify --output 'jsonpath={..namespace}')"
        if [ "$_NAMESPACE" = "" ]; then
            _NAMESPACE=default
        fi
    fi
    if [ "$_BLUEPRINT" = "" ]; then
        echo "blueprint not supplied" >&2
        exit 1
    fi
    if [ "$_WORKLOAD" = "" ]; then
        _WORKLOAD="$(kubectl get plugs.integration.rock8s.com kanister-${_BLUEPRINT} -n b-openldap -o jsonpath='{.spec.config.workload}')"
    fi
    if [ "$_WORKLOAD" = "" ]; then
        echo "workload not supplied" >&2
        exit 1
    fi
    _KANISTER_BLUEPRINT="$_NAMESPACE.$_BLUEPRINT"
    _KIND="$(kubectl get blueprints.cr.kanister.io "$_BLUEPRINT" -n "$_NAMESPACE" -o jsonpath='{.actions.backup.kind}')"
    _KIND="$(echo "$_KIND" | tr '[:upper:]' '[:lower:]')"
    if [ "$_KIND" = "" ]; then
        echo "failed to get kind" >&2
        exit 1
    fi
    if [ "$_KIND" = "statefulset" ]; then
        _STATEFULSET_ARG="--statefulset $_NAMESPACE/$_WORKLOAD"
    elif [ "$_KIND" = "deployment" ]; then
        _DEPLOYMENT_ARG="--deployment $_NAMESPACE/$_WORKLOAD"
    elif [ "$_KIND" = "daemonset" ]; then
        _DAEMONSET_ARG="--daemonset $_NAMESPACE/$_WORKLOAD"
    elif [ "$_KIND" = "replicaset" ]; then
        _REPLICASET_ARG="--replicaset $_NAMESPACE/$_WORKLOAD"
    else
        echo "unknown kind: $_KIND" >&2
        exit 1
    fi
    _OPTIONS=""
    if [ "$_KOPIA_PASSWORD" != "" ]; then
        _OPTIONS="$_OPTIONS,kopiaPassword=$_KOPIA_PASSWORD"
    fi
    if [ "$_PREFIX" != "" ]; then
        _OPTIONS="$_OPTIONS,prefix=$_PREFIX"
    fi
    if [ "$_OPTIONS" != "" ]; then
        if [ "$(echo -n "$_OPTIONS" | head -c1)" = "," ]; then
            _OPTIONS=$(echo $_OPTIONS | cut -c2-)
        fi
        _OPTIONS_ARG="--options $_OPTIONS"
    fi
    if [ "$_DRY" = "1" ]; then
        _DRY_RUN_ARG="--dry-run"
        echo kanctl create actionset \
            --namespace "$KANISTER_NAMESPACE" \
            --blueprint "$_KANISTER_BLUEPRINT" \
            $_STATEFULSET_ARG \
            $_DEPLOYMENT_ARG \
            $_DAEMONSET_ARG \
            $_REPLICASET_ARG \
            $_OPTIONS_ARG \
            --profile "$_PROFILE" \
            --action backup "$@"
    fi
    kanctl create actionset \
        --namespace "$KANISTER_NAMESPACE" \
        --blueprint "$_KANISTER_BLUEPRINT" \
        $_DRY_RUN_ARG \
        $_STATEFULSET_ARG \
        $_DEPLOYMENT_ARG \
        $_DAEMONSET_ARG \
        $_REPLICASET_ARG \
        $_OPTIONS_ARG \
        --profile "$_PROFILE" \
        --action backup "$@"
}

_restore() {
    while test $# -gt 0; do
        case "$1" in
        -h | --help)
            _restore_help
            exit
            ;;
        -p | --profile)
            shift
            _PROFILE="$1"
            shift
            ;;
        -w | --workload)
            shift
            _WORKLOAD="$1"
            shift
            ;;
        -n | --namespace)
            shift
            _NAMESPACE="$1"
            shift
            ;;
        -f | --from)
            shift
            _FROM="$1"
            shift
            ;;
        -x | --kopia-password)
            shift
            _KOPIA_PASSWORD="$1"
            shift
            ;;
        --prefix)
            shift
            _PREFIX="$1"
            shift
            ;;
        *)
            break
            ;;
        esac
    done
    if [ "$_PROFILE" = "" ]; then
        _PROFILE=kanister
    fi
    if [ "$1" != "" ]; then
        _BLUEPRINT="$1"
        shift
    fi
    if [ "$_NAMESPACE" = "" ]; then
        _NAMESPACE="$(kubectl config view --minify --output 'jsonpath={..namespace}')"
        if [ "$_NAMESPACE" = "" ]; then
            _NAMESPACE=default
        fi
    fi
    if [ "$_BLUEPRINT" = "" ]; then
        echo "blueprint not supplied" >&2
        exit 1
    fi
    if [ "$_WORKLOAD" = "" ]; then
        _WORKLOAD="$(kubectl get plugs.integration.rock8s.com kanister-${_BLUEPRINT} -n b-openldap -o jsonpath='{.spec.config.workload}')"
    fi
    if [ "$_WORKLOAD" = "" ]; then
        echo "workload not supplied" >&2
        exit 1
    fi
    _KANISTER_BLUEPRINT="$_NAMESPACE.$_BLUEPRINT"
    if [ "$_FROM" != "" ]; then
        _FROM_ARG="--from $_FROM"
    fi
    _KIND="$(kubectl get blueprints.cr.kanister.io "$_BLUEPRINT" -n "$_NAMESPACE" -o jsonpath='{.actions.backup.kind}')"
    _KIND="$(echo "$_KIND" | tr '[:upper:]' '[:lower:]')"
    if [ "$_KIND" = "" ]; then
        echo "failed to get kind" >&2
        exit 1
    fi
    if [ "$_KIND" = "statefulset" ]; then
        _STATEFULSET_ARG="--statefulset $_NAMESPACE/$_WORKLOAD"
    elif [ "$_KIND" = "deployment" ]; then
        _DEPLOYMENT_ARG="--deployment $_NAMESPACE/$_WORKLOAD"
    elif [ "$_KIND" = "daemonset" ]; then
        _DAEMONSET_ARG="--daemonset $_NAMESPACE/$_WORKLOAD"
    elif [ "$_KIND" = "replicaset" ]; then
        _REPLICASET_ARG="--replicaset $_NAMESPACE/$_WORKLOAD"
    else
        echo "unknown kind: $_KIND" >&2
        exit 1
    fi
    _OPTIONS=""
    if [ "$_KOPIA_PASSWORD" != "" ]; then
        _OPTIONS="$_OPTIONS,kopiaPassword=$_KOPIA_PASSWORD"
    fi
    if [ "$_PREFIX" != "" ]; then
        _OPTIONS="$_OPTIONS,prefix=$_PREFIX"
    fi
    if [ "$_OPTIONS" != "" ]; then
        if [ "$(echo -n "$_OPTIONS" | head -c1)" = "," ]; then
            _OPTIONS=$(echo $_OPTIONS | cut -c2-)
        fi
        _OPTIONS_ARG="--options $_OPTIONS"
    fi
    if [ "$_DRY" = "1" ]; then
        _DRY_RUN_ARG="--dry-run"
        kanctl create actionset \
            --namespace "$KANISTER_NAMESPACE" \
            --blueprint "$_KANISTER_BLUEPRINT" \
            $_STATEFULSET_ARG \
            $_DEPLOYMENT_ARG \
            $_DAEMONSET_ARG \
            $_REPLICASET_ARG \
            $_OPTIONS_ARG \
            --profile "$_PROFILE" \
            --action restore \
            --from "$_FROM" "$@"
    fi
    kanctl create actionset \
        --namespace "$KANISTER_NAMESPACE" \
        --blueprint "$_KANISTER_BLUEPRINT" \
        $_DRY_RUN_ARG \
        $_STATEFULSET_ARG \
        $_DEPLOYMENT_ARG \
        $_DAEMONSET_ARG \
        $_REPLICASET_ARG \
        --profile "$_PROFILE" \
        --action restore \
        --from "$_FROM" "$@"
}

_exec() {
    if [ "$_DRY" = "1" ]; then
        echo "$@"
    else
        "$@"
    fi
}

_backup_help() {
    echo "Usage: kanukopia [OPTIONS] backup [ARGUMENTS] <BLUEPRINT>

[ARGUMENTS]:
    -h, --help           show help
    -p, --profile        profile name
    -w, --workload       workload name
    -n, --namespace      namespace name
    -x, --kopia-password kopia password
    --prefix             kopia prefix

<BLUEPRINT>: blueprint name"
}

_restore_help() {
    echo "Usage: kanukopia [OPTIONS] restore [ARGUMENTS] <BLUEPRINT>

[ARGUMENTS]:
    -h, --help           show help
    -p, --profile        profile name
    -w, --workload       workload name
    -n, --namespace      namespace name
    -x, --kopia-password kopia password
    -f, --from           actionset name to restore from
    --prefix             kopia prefix

<BLUEPRINT>: blueprint name"
}

_help() {
    echo "Usage: kanukopia [OPTIONS] <COMMAND> [ARGUMENTS]

[OPTIONS]:
    -h, --help    show help
    -d, --dry     dry run
    -d, --debug   debug mode

<COMMAND>:
    k, kopia      run kopia command
    b, backup     run backup action
    r, restore    run restore action"
}

while test $# -gt 0; do
    case "$1" in
    -h | --help)
        _help
        exit
        ;;
    -d | --dry)
        shift
        export _DRY="1"
        ;;
    -d | --debug)
        shift
        export _DEBUG="1"
        ;;
    *)
        break
        ;;
    esac
done

case "$1" in
    k | kopia)
        shift
        export _COMMAND=kopia
        ;;
    b | backup)
        shift
        export _COMMAND=backup
        ;;
    r | restore)
        shift
        export _COMMAND=restore
        ;;
    *)
        _help
        exit
        ;;
esac

_main "$@"
