#!/bin/sh

set -e

export TMPDIR="${TMPDIR:-/tmp}"
if [ "$USER" = "" ]; then
    export USER="kanukopia"
fi
if [ "$HOME" = "" ] || [ "$HOME" = "/" ]; then
    export HOME="$TMPDIR/kanukopia"
fi
KANISTER_NAMESPACE="${KANISTER_NAMESPACE:-kanister}"

_kopia() {
    if [ "$PROFILE_JSON" = "" ]; then
        echo "profile json not supplied" >&2
        exit 1
    fi
    if [ "$PREFIX" = "" ]; then
        echo "aws prefix not supplied" >&2
        exit 1
    fi
    if [ "$PASSWORD" = "" ]; then
        PASSWORD="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
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
        --password="$PASSWORD" \
        --prefix="$PREFIX/"; then
        _exec kopia repository create s3 \
            --bucket="$_AWS_BUCKET" \
            --endpoint="$_AWS_ENDPOINT" \
            --password="$PASSWORD" \
            --prefix="$PREFIX/"
    fi
    _exec kopia "$@"
    _exec kopia repository disconnect
    _exec rm -rf "$HOME/.config/kopia"
}

_restic() {
    if [ "$PROFILE_JSON" = "" ]; then
        echo "profile json not supplied" >&2
        exit 1
    fi
    if [ "$PREFIX" = "" ]; then
        echo "aws prefix not supplied" >&2
        exit 1
    fi
    if [ "$PASSWORD" = "" ]; then
        PASSWORD="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
    fi
    _AWS_BUCKET="$(echo $PROFILE_JSON | jq -r .Location.bucket)"
    _AWS_ENDPOINT="$(echo $PROFILE_JSON | jq -r .Location.endpoint)"
    export AWS_ACCESS_KEY_ID="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.ID)"
    export AWS_SECRET_ACCESS_KEY="$(echo $PROFILE_JSON | jq -r .Credential.KeyPair.Secret)"
    export AWS_REGION="$(echo $PROFILE_JSON | jq -r .Location.region)"
    export RESTIC_REPOSITORY="s3:$_AWS_ENDPOINT/$_AWS_BUCKET/$PREFIX"
    export RESTIC_PASSWORD="$PASSWORD"
    if ! _exec restic cat config >/dev/null 2>&1; then
        _exec restic init
    fi
    _exec restic "$@"
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
        -x | --password)
            shift
            _PASSWORD="$1"
            shift
            ;;
        -o | --options)
            shift
            _OPTIONS="$1"
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
        _WORKLOAD="$(kubectl get plugs.integration.rock8s.com kanister-${_BLUEPRINT} -n "$_NAMESPACE" -o jsonpath='{.spec.config.workload}')"
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
    _OPTIONS="$_OPTIONS,password=$_PASSWORD,prefix=$_PREFIX,debug=$_DEBUG"
    if [ "$(echo -n "$_OPTIONS" | head -c1)" = "," ]; then
        _OPTIONS=$(echo $_OPTIONS | cut -c2-)
    fi
    _OPTIONS_ARG="--options $_OPTIONS"
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
            --name "backup-${_NAMESPACE}-${_BLUEPRINT}-$(date +%s)" \
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
        --name "backup-${_NAMESPACE}-${_BLUEPRINT}-$(date +%s)" \
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
        -x | --password)
            shift
            _PASSWORD="$1"
            shift
            ;;
        -s | --snapshot)
            shift
            _SNAPSHOT="$1"
            shift
            ;;
        -t | --snapshot-time)
            shift
            _SNAPSHOT_TIME="$1"
            shift
            ;;
        -o | --options)
            shift
            _OPTIONS="$1"
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
        _WORKLOAD="$(kubectl get plugs.integration.rock8s.com kanister-${_BLUEPRINT} -n "$_NAMESPACE" -o jsonpath='{.spec.config.workload}')"
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
    _OPTIONS="$_OPTIONS,password=$_PASSWORD,prefix=$_PREFIX,snapshot=$_SNAPSHOT,snapshotTime=$_SNAPSHOT_TIME,debug=$_DEBUG"
    if [ "$(echo -n "$_OPTIONS" | head -c1)" = "," ]; then
        _OPTIONS=$(echo $_OPTIONS | cut -c2-)
    fi
    _OPTIONS_ARG="--options $_OPTIONS"
    if [ "$_FROM" = "" ]; then
        _ACTION="restore"
    else
        _FROM_ARG="--from $_FROM"
        _ACTION="restorefrom"
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
            --action "$_ACTION" \
            --name "${_ACTION}-${_NAMESPACE}-${_BLUEPRINT}-$(date +%s)" \
            $_FROM_ARG "$@"
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
        --action "$_ACTION" \
        --name "${_ACTION}-${_NAMESPACE}-${_BLUEPRINT}-$(date +%s)" \
        $_FROM_ARG "$@"
}

_find_restic_snapshot() {
    _CURRENT_TIMESTAMP="$1"
    if [ "$_CURRENT_TIMESTAMP" = "" ]; then
        _CURRENT_TIMESTAMP=$(date +"%s")
    else
        if echo "$_CURRENT_TIMESTAMP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
            _CURRENT_TIMESTAMP=$(date -d"$_CURRENT_TIMESTAMP 00:00:00 UTC" +"%s")
        elif echo "$_CURRENT_TIMESTAMP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
            _CURRENT_TIMESTAMP=$(date -d"$_CURRENT_TIMESTAMP UTC" +"%s")
        elif echo "$_CURRENT_TIMESTAMP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} UTC[+-][0-9]{1,2}$'; then
            _CURRENT_TIMESTAMP=$(date -d"$_CURRENT_TIMESTAMP" +"%s")
        elif echo "$_CURRENT_TIMESTAMP" | grep -qE '^[0-9]+$'; then
            _CURRENT_TIMESTAMP="$_CURRENT_TIMESTAMP"
        else
            echo "'$_CURRENT_TIMESTAMP' is an invalid timestamp format" >&2
            exit 1
        fi
    fi
    echo "finding latest snapshot prior to $(date -u -d @$_CURRENT_TIMESTAMP +"%Y-%m-%d %H:%M:%S %Z")" >&2
    _SNAPSHOT="$(_restic snapshots --json | _filter_restic_snapshot "$_CURRENT_TIMESTAMP")"
    if [ "$_SNAPSHOT" = "" ]; then
        echo "no snapshot found prior to $(date -u -d @$_CURRENT_TIMESTAMP +"%Y-%m-%d %H:%M:%S %Z")" >&2
        exit 1
    fi
    echo "$_SNAPSHOT"
}

_filter_restic_snapshot() {
    _CURRENT_TIMESTAMP="$1"
    if [ "$_CURRENT_TIMESTAMP" = "" ]; then
        echo "current timestamp not supplied" >&2
        exit 1
    fi
    jq -r '[.[] | {id: .id, time: .time}] | sort_by(.time) | reverse | .[].id' | while IFS= read -r _ID; do
        _TIME=$(_restic snapshots $_ID --json | jq -r '.[0].time')
        _TIMESTAMP=$(date -d "$_TIME" +"%s")
        if [ "$_TIMESTAMP" -le "$_CURRENT_TIMESTAMP" ]; then
            echo "$_ID"
            return
        fi
    done
}

_find_kopia_snapshot() {
    _CURRENT_TIMESTAMP="$1"
    if [ "$_CURRENT_TIMESTAMP" = "" ]; then
        _CURRENT_TIMESTAMP=$(date +"%s")
    else
        if echo "$_CURRENT_TIMESTAMP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
            _CURRENT_TIMESTAMP=$(date -d"$_CURRENT_TIMESTAMP 00:00:00 UTC" +"%s")
        elif echo "$_CURRENT_TIMESTAMP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
            _CURRENT_TIMESTAMP=$(date -d"$_CURRENT_TIMESTAMP UTC" +"%s")
        elif echo "$_CURRENT_TIMESTAMP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} UTC[+-][0-9]{1,2}$'; then
            _CURRENT_TIMESTAMP=$(date -d"$_CURRENT_TIMESTAMP" +"%s")
        elif echo "$_CURRENT_TIMESTAMP" | grep -qE '^[0-9]+$'; then
            _CURRENT_TIMESTAMP="$_CURRENT_TIMESTAMP"
        else
            echo "'$_CURRENT_TIMESTAMP' is an invalid timestamp format" >&2
            exit 1
        fi
    fi
    echo "finding latest snapshot prior to $(date -u -d @$_CURRENT_TIMESTAMP +"%Y-%m-%d %H:%M:%S %Z")" >&2
    _SNAPSHOT="$(_kopia snapshot list --all --json | _filter_kopia_snapshot "$_CURRENT_TIMESTAMP")"
    if [ "$_SNAPSHOT" = "" ]; then
        echo "no snapshot found prior to $(date -u -d @$_CURRENT_TIMESTAMP +"%Y-%m-%d %H:%M:%S %Z")" >&2
        exit 1
    fi
    echo "$_SNAPSHOT"
}

_filter_kopia_snapshot() {
    _CURRENT_TIMESTAMP="$1"
    if [ "$_CURRENT_TIMESTAMP" = "" ]; then
        echo "current timestamp not supplied" >&2
        exit 1
    fi
    jq -c 'sort_by(.startTime) | reverse | .[]' | while IFS= read -r _OBJECT; do
        _ID=$(echo "$_OBJECT" | jq -r '.id')
        _START_TIME=$(echo "$_OBJECT" | jq -r '.startTime')
        _TIMESTAMP=$(date -d "$_START_TIME" +"%s")
        if [ "$_TIMESTAMP" -le "$_CURRENT_TIMESTAMP" ]; then
            echo "$_ID"
            return
        fi
    done
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
    -x, --password       password
    -o, --options        options
    --prefix             prefix

<BLUEPRINT>: blueprint name"
}

_restore_help() {
    echo "Usage: kanukopia [OPTIONS] restore [ARGUMENTS] <BLUEPRINT>

[ARGUMENTS]:
    -h, --help           show help
    -p, --profile        profile name
    -w, --workload       workload name
    -n, --namespace      namespace name
    -x, --password       password
    -s, --snapshot       snapshot
    -t, --snapshot-time  snapshot time
    -o, --options        options
    -f, --from           actionset name to restore from
    --prefix             prefix

<BLUEPRINT>: blueprint name"
}

_help() {
    echo "Usage: kanukopia [OPTIONS] <COMMAND> [ARGUMENTS]

[OPTIONS]:
    -h, --help    show help
    -d, --dry     dry run
    -d, --debug   debug mode

<COMMAND>:
    b, backup            run backup action
    r, restore           run restore action
    kopia                run kopia command
    restic               run restic command
    find-kopia-snapshot  find kopia snapshot
    find-restic-snapshot find restic snapshot"
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

if [ "$KANUKOPIA_DEBUG" = "1" ]; then
    export _DEBUG="1"
fi
if [ "$_DEBUG" = "1" ]; then
    set -x
fi

case "$1" in
    kopia)
        shift
        _kopia "$@"
        ;;
    restic)
        shift
        _restic "$@"
        ;;
    b | backup)
        shift
        _backup "$@"
        ;;
    r | restore)
        shift
        _restore "$@"
        ;;
    find-kopia-snapshot)
        shift
        _find_kopia_snapshot "$@"
        ;;
    find-restic-snapshot)
        shift
        _find_restic_snapshot "$@"
        ;;
    *)
        _help
        exit
        ;;
esac
