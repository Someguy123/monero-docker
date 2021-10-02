#!/usr/bin/env bash
#####
# Monero-in-a-box
# (C) 2019 Someguy123
#####

# directory where the script is located, so we can source files regardless of where PWD is
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/lib/000_helpers.sh" &> /dev/null
source "${DIR}/lib/010_helpers.sh" &> /dev/null

[[ -f "${DIR}/.env" ]] && source "${DIR}/.env"

if [[ ! -f "${DIR}/.env" ]]; then
    >&2 msg yellow "\n [!!!] Warning: ${DIR}/.env not found. Copying ${DIR}/env.example to ${DIR}/.env ...\n"
    >&2 cp -v "${DIR}/env.example" "${DIR}/.env"
fi

: ${VERBOSE=0}
: ${DATADIR="${DIR}/data"}
: ${DK_IMG="someguy123/monero"}
: ${DK_NAME="monero"}
: ${WALLET_CONF="${DATADIR}/wallet.conf"}
: ${MONEROD_CONF="${DATADIR}/monerod.conf"}
: ${EXAMPLE_WALLET_CONF="${WALLET_CONF}.example"}
: ${EXAMPLE_MONEROD_CONF="${MONEROD_CONF}.example"}

: ${WALLET_CTR='monero_wallet'}
: ${WALLET_HOST='http://127.0.0.1:18100/json_rpc'}
: ${WALLET_NAME='mnrwallet'}
: ${RPC_CTR='monerod'}
: ${RPC_LOGIN='example:example'}
: ${RPC_HOST='http://127.0.0.1:18081/json_rpc'}

: ${REMOTE_RPC="http://node.moneroworld.com:18089/json_rpc"}
#: ${MONERO_VERSION="v0.17.2.3"}
: ${MONERO_VERSION="latest"}

if [[ ! -f "$MONEROD_CONF" ]]; then
    if [[ -f "$EXAMPLE_MONEROD_CONF" ]]; then
        msg yellow "monerod.conf not found. copying example file."
        cp -vi "$EXAMPLE_MONEROD_CONF" "$MONEROD_CONF"
        msg green " > Successfully installed example monerod.conf"
    else
        msg yellow "WARNING: You don't seem to have a config file and the example config couldn't be found..."
        msg yellow "Please make sure $MONEROD_CONF exists"
    fi
fi
if [[ ! -f "$WALLET_CONF" ]]; then
    if [[ -f "$EXAMPLE_WALLET_CONF" ]]; then
        msg yellow "wallet.conf not found. copying example file."
        cp -vi "$EXAMPLE_WALLET_CONF" "$WALLET_CONF"
        msg green " > Successfully installed example wallet.conf"
    else
        msg yellow "WARNING: You don't seem to have a config file and the example config couldn't be found..."
        msg yellow "Please make sure $WALLET_CONF exists"
    fi
fi

# Usage: ./run.sh install_docker
# Downloads and installs the latest version of Docker using the Get Docker site
install_docker() {
    if [ -x "$(command -v docker)" ]; then
        return 0
    fi

    sudo apt update -y
    # curl/git used by docker
    sudo apt install -qy curl git xz-utils liblz4-tool jq
    curl https://get.docker.com | sh

    if [ "$EUID" -ne 0 ]; then
        echo "Adding user $(whoami) to docker group"
        sudo usermod -aG docker $(whoami)
        echo "IMPORTANT: Please re-login (or close and re-connect SSH) for docker to function correctly"
    fi
}

install_dkcompose() {
    if ! [ -x "$(command -v docker-compose)" ]; then
        sudo curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
}

build() {
    local mver="$MONERO_VERSION"
    (( $# > 1 )) && mver="$1" && shift
    DK_ARGS=("--build-arg" "MONERO_VERSION=${mver}")
    (( $# > 0 )) && DK_ARGS+=("$@")
    DK_ARGS+=("-t" "$DK_NAME" ".")
    msg bold yellow "\n > Building Monero version '${mver}' as docker image '${DK_NAME}'"
    msg bold yellow " > Build arguments: ${DK_ARGS[*]} \n"

    docker build "${DK_ARGS[@]}"
    _ret=$?
    msg bold green "\n +++ Finished +++ \n"
    exit $_ret
}

dkinstall() {
    local mver="$MONERO_VERSION"
    (( $# > 1 )) && mver="$1" && shift
    msg bold yellow "\n >>> Downloading docker image: ${DK_IMG}:${mver} \n"
    docker pull "${DK_IMG}:${mver}"
    msg bold yellow "\n >>> Tagging docker image '${DK_IMG}:${mver}' as '${DK_NAME}' \n"
    docker tag "${DK_IMG}:${mver}" "$DK_NAME"
    msg bold green "\n +++ Finished +++ \n"
}


setup() {
    install_docker && install_dkcompose

    msg bold green "-----------------------------------"
    msg bold green "Easy Setup Tool for Monero-in-a-box"
    msg bold green "    By Someguy123"
    msg bold green "-----------------------------------"
    msg
    msg yellow "First, we need a username and password to use, for logging into monerod and monero-wallet-rpc via API"
    msg yellow "They should be combined together, split by a colon (:) - please avoid special characters and spaces."
    msg yellow "Example: ${BOLD}john:MySecUREp4ssw0rd"
    msg
    read -p "${GREEN} What user/password should we use? (format like user:password) >${RESET} " usrpass
    msg
    msg green "You entered the user/pass '${usrpass}'"
    msg
    msg yellow "Next we need a password to use for encrypting your Monero wallet. We recommend avoiding special characters"
    msg yellow "and spaces, as they can cause problems."
    msg yellow "NOTE: The password will be stored in plain-text in your '.env' file, for automatic decryption"
    msg
    read -p "${GREEN} What wallet password should we use? >${RESET} " walpass
    msg
    msg green "You entered the wallet password '${walpass}'"
    export RPC_LOGIN="$usrpass"
    export WALLET_PASS="$walpass"

    echo "RPC_LOGIN=${usrpass}" >> "${DIR}/.env"
    echo "WALLET_PASS=${walpass}" >> "${DIR}/.env"

    msg
    msg "========================================="
    msg
    if yesno "${GREEN}Do you want to start monerod + monero-wallet-rpc now? (Y/n) >${RESET} " defyes; then
        msg bold green " -> (Re-)Starting monerod + monero-wallet-rpc now..."
        cd "$DIR"
        docker-compose down &> /dev/null
        docker-compose up -d
        tries=0
        while ! container_running "$WALLET_CTR"; do
            if (($tries>2)); then
                msgts bold red "Re-tried container check $tries times, but $WALLET_CTR is still down..."
                msgts bold red "Please check the logs with 'docker logs $WALLET_CTR'"
                return 1
            fi
            msgts yellow "Waiting for container '$WALLET_CTR' to start up..."
            sleep 10
            tries=$((tries+1))
        done
        msgts green "Container '$WALLET_CTR' appears to be up. Waiting 10 more seconds to ensure it's ready for requests"
        sleep 10
        msgts green "Attempting to create wallet '${WALLET_NAME}' with password specified earlier."
        create_wallet "$walpass"
        msg
        msg "========================================="
        msgts green "\n (+) Finished. You should now be able to use the wallet 'mnrwallet' via the host $WALLET_HOST with login details $usrpass \n"
        msg "=========================================\n"

    else
        msg
        msg red "Looks like you said no. Exiting setup now."
        msg yellow "To start monerod + monero-wallet-rpc, type 'docker-compose up -d'"
        msg
        return 1
    fi
}


container_running() {
    (($#<1)) && msg red "Usage: container_running [name]" && return 1

    cntcount=$(docker ps -f 'status=running' -f name=$1 | wc -l)
    if [[ $cntcount -eq 2 ]]; then
        return 0
    else
        return -1
    fi
}

create_wallet() {
    local walname="${WALLET_NAME}" walpass=""

    if (($#<1)); then
        msg red "Error: create_wallet needs at least one argument"
        msg yellow "Usage: create_wallet [password] (wallet_name)"
        msg yellow "Default wallet name: $walname"
        return 1
    fi

    (($#>=1)) && walpass="$1"
    (($#>=2)) && walname="$2"

    msg green " -> Creating wallet '$walname' via wallet RPC '$WALLET_HOST' using login details '${RPC_LOGIN}' "
    curl -u "$RPC_LOGIN" --digest -X POST "$WALLET_HOST" -d \
        '{"jsonrpc":"2.0","id":"0","method":"create_wallet","params": {"filename":"'$walname'","password":"'$walpass'","language":"English"}}' \
        -H 'Content-Type: application/json'
}

create_account() {

    if (($#<1)); then
        msg red "Error: create_account needs a label for the account"
        msg yellow "Usage: create_account [label]"
        return 1
    fi

    local label="$1"

    msg green " -> Opening wallet ${WALLET_NAME} via wallet RPC '$WALLET_HOST' using login details '${RPC_LOGIN}' "
    curl -u "$RPC_LOGIN" --digest -X POST "$WALLET_HOST" -d \
        '{"jsonrpc":"2.0","id":"0","method":"open_wallet","params": {"filename":"'${WALLET_NAME}'","password":"'${WALLET_PASS}'","language":"English"}}' \
        -H 'Content-Type: application/json'

    msg green " -> Creating account with label ${label}"

    curl -u "$RPC_LOGIN" --digest -X POST "$WALLET_HOST" -d \
        '{"jsonrpc":"2.0","id":"0","method":"create_account","params": {"label":"'${label}'"}}' \
        -H 'Content-Type: application/json'
    msg
    msg green " (+) Done\n"

}

: ${QUERY_AUTH=1}

_mnquery-help() {
    msg yellow "\nUsage: $0 query (-v) (host=${RPC_HOST}) [method] (params=[])\n"
    msg green "Call a JSON RPC method against either your local Monero RPC daemon / wallet, or a remote daemon / wallet\n"
    msg bold green "Examples:\n"
    msg green "    $0 query get_block_count       # Get the current block count of the local RPC daemon\n"
    msg green "    $0 query -v get_block_count    # (Verbose mode) Get the current block count of the local RPC daemon\n"
    msg green "    $0 query https://xmr.privex.io/json_rpc get_block_count    # Get the current block count of the remote RPC 'https://xmr.privex.io'\n"
    msg green "    $0 query http://127.0.0.1:18100 get_transfers '{\"in\":true,\"account_index\":1}'  # Query the local monero wallet daemon for a list of transfers\n"
    msg
}

mnquery() {
    local mnhost mnmeth mnparams
    local CURL_ARGS
    if (( $# < 1 )); then
        _mnquery-help; return 1
    fi
    CURL_ARGS=()
    if [[ "$1" == "-v" ]]; then
        CURL_ARGS+=("-v"); VERBOSE=1; shift
    else
        CURL_ARGS+=("-sS")
    fi
    if (( $# < 1 )); then
        _mnquery-help; return 1
    fi

    (( QUERY_AUTH )) && CURL_ARGS+=("-u" "$RPC_LOGIN" "--digest")
    mnparams="[]"
    if grep -qE "^https?:" <<< "$1"; then
        mnhost="$1" mnmeth="$2"
    else
        mnhost="$RPC_HOST" mnmeth="$1"
    fi
    (( $# > 2 )) && mnparams="$3"
    
    res="$(curl "${CURL_ARGS[@]}" -X POST "$mnhost" -H 'Content-Type: application/json' -d '{"jsonrpc": "2.0", "method": "'$mnmeth'", "params": '$mnparams', "id": 1 }')"
    _ret=$?
    if (( _ret )); then
        >&2 msg bold red "\n [!!!] Non-zero return code from curl: $_ret - aborting."
        >&2 msg yellow "STDOUT Response from curl:${RESET}\n\n${res}\n\n"
        return $_ret
    fi
    if (( VERBOSE )); then
        printf "%s\n" "$res"
    else
        jq '.' <<< "$res"
    fi
}

q-block-count() {
    local res
    (( $# > 0 )) && res=$(mnquery "$1" get_block_count) || res=$(mnquery get_block_count)
    jq -r '.result.count' <<< "$res"
}

q-version() {
    local res
    (( $# > 0 )) && res=$(mnquery "$1" get_version) || res=$(mnquery get_version)
    jq -r '.result.version' <<< "$res"
}

mnr-status() {
    local lcl_block lcl_ver rem_block rem_ver blocks_behind

    msg yellow "Local RPC URL:${RESET} ${RPC_HOST}"
    msg yellow "Remote RPC URL:${RESET} ${REMOTE_RPC}"

    msg "$_LN"

    msg yellow "\n [...] Loading block count + version from local rpc: ${RPC_HOST}\n"
    lcl_block=$(q-block-count) lcl_ver=$(q-version)
    msg yellow "\n [...] Loading block count + version from remote rpc: ${REMOTE_RPC}\n"
    rem_block=$(q-block-count "$REMOTE_RPC") rem_ver=$(q-version "$REMOTE_RPC")
    lcl_block=$(( lcl_block )) rem_block=$(( rem_block ))

    msg "$_LN"
    msg green "Local RPC head block:    ${RESET}$lcl_block"
    msg green "Local RPC version:       ${RESET}$lcl_ver"
    msg "$_LN"
    msg green "Remote RPC head block:   ${RESET}$rem_block"
    msg green "Remote RPC version:      ${RESET}$rem_ver"
    msg "$_LN"
    msg green "Blocks behind:           ${RESET}$(( rem_block - lcl_block ))"
    msg "$_LN"

}

_LN="\n==============================================================================\n"

: ${MONITOR_INTERVAL=10}

MONITOR_INTERVAL=$((MONITOR_INTERVAL))

mnr-monitor() {
    local props head_block block_time seconds_behind time_behind
    local blocks_synced=0 started_at="$(rfc_datetime)" starting_block=0
    local time_since_start mins_since_start bps=0 bpm=0
    local remote_props remote_head_block blocks_behind mins_remaining
    #error_control 0
    msg
    msg bold green "--- Monero-in-a-box Sync Monitor --- \n"
    msg bold green "Monitoring your local steemd instance\n"
    msg bold green "Block data will update every 10 seconds, showing the block number that your node is synced up to"
    msg bold green "the date/time that block was produced, and how far behind in days/hours/minutes that block is.\n"
    msg bold green "After the first check, we'll also output how many blocks have been synced so far, as well as"
    msg bold green "the estimated blocks per second (BPS) that your node is syncing by.\n"
    #msg bold yellow "NOTE: This will not work with a replaying node. Only with a node which is synchronising.\n"
    
    msg "$_LN"

    msg blue "To estimate how many blocks behind your Monero node is, and to give you an ETA, we compare your node's"
    msg blue "current block number against a remote monero RPC node. You can change the remote RPC used, simply by"
    msg blue "setting REMOTE_RPC in your .env - like so: 'REMOTE_RPC=http://monero-rpc.example.org:18081/json_rpc'\n"
    msg yellow "Local RPC URL:${RESET} ${RPC_HOST}"
    msg yellow "Remote RPC URL:${RESET} ${REMOTE_RPC}"

    msg "$_LN"

    while true; do
        #error_control 1
        props=$(mnquery get_block_count)
        ret=$?
        if (( ret != 0 )); then
            msg bold red "Error while obtaining Local RPC global props. Will try again soon..."
            msg "$_LN"
            sleep "$MONITOR_INTERVAL"
            continue
        fi
        head_block=$(echo "$props" | jq -r '.result.count')
        #block_time=$(echo "$props" | jq -r '.result.time')
        if [ -z "$head_block" ] || [[ "$head_block" == "null" ]] ; then
            msg bold red "Local RPC head block / block time was empty. Will try again soon..."
            msg "$_LN"
            sleep "$MONITOR_INTERVAL"
            continue
        fi

        current_timestamp=$(rfc_datetime)
        #error_control 2
        #seconds_behind=$(compare_dates "$current_timestamp" "$block_time")
        #if (( ret != 0 )); then
        #    msg bold red "Local RPC timestamp was invalid (err: compare_dates). Will try again soon..."
        #    msg "$_LN"; sleep "$MONITOR_INTERVAL"; continue
        #fi
        #time_behind="$(human_seconds "${seconds_behind}")"
        #if (( ret != 0 )); then
        #    msg bold red "Local RPC timestamp was invalid (err: human_seconds). Will try again soon..."
        #    msg "$_LN"; sleep "$MONITOR_INTERVAL"; continue
        #fi
        #error_control 0

        msg green "Current block:               ${RESET}${head_block}"
        #msg green "Block time:                ${block_time}"
        #msg green "Time behind head block:    ${time_behind}"
        msg

        (( starting_block == 0 )) && starting_block="$head_block"

        blocks_synced=$((head_block - starting_block))

        if (( blocks_synced > 0 )); then
            msg green "New blocks since start:      ${RESET}$blocks_synced"
            time_since_start=$(compare_dates "$(rfc_datetime)" "$started_at")
            bps=$((blocks_synced/time_since_start))
            mins_since_start=$((time_since_start / 60))
            msg green "Blocks per second:           ${RESET}$bps"

            #error_control 1
            remote_props=$(mnquery "$REMOTE_RPC" get_block_count)
            ret=$?
            if (( ret == 0 )); then
                remote_head_block=$(echo "$remote_props" | jq -r '.result.count')
                if [ -z "$remote_head_block" ] || [[ "$remote_head_block" == "null" ]]; then
                    msg bold red "Remote RPC head block / block time was empty. Will try again soon..."
                    msg "$_LN"
                    sleep "$MONITOR_INTERVAL"
                    continue
                fi
                msg green "Latest network block:        ${RESET}$remote_head_block ${BLUE}(from RPC $REMOTE_RPC)"

                blocks_behind=$(( remote_head_block - head_block ))
                mins_remaining=$(( (blocks_behind / bps) / 60 ))
                msg green "Blocks behind:               ${RESET}$blocks_behind"
                msg green "ETA til Synced:              ${RESET}$mins_remaining ${GREEN}minutes"
                if (( mins_since_start > 0 )); then
                    bpm=$(( blocks_synced / (time_since_start / 60) ))
                    msg green "Blocks per minute:           ${RESET}$bpm"
                fi
            else
                msg bold red "Error while obtaining Remote RPC global props. Will try again soon..."
                msg "$_LN"
                sleep "$MONITOR_INTERVAL"
                continue
            fi
            
            #msg
        fi
        msg "$_LN"
        sleep "$MONITOR_INTERVAL"
    done
}


_help() {
    msg green "Monero in a Box"
    msg green "By Someguy123"
    msg blue "Github: https://github.com/someguy123/monero-docker"
    msg "---------------------"
    msg
    msg green "Commands:"
    msg yellow "\t - setup - Install docker if needed, guided .env creation, start monero, and initial wallet creation"
    msg yellow "\t - create_wallet [password] [name] - Create a monero wallet with the given password and file name "
    msg yellow "\t - start - Start monero and wallet RPC - alias for 'docker-compose up -d'"
    msg yellow "\t - stop - Stop monero and wallet RPC - alias for 'docker-compose down'"
    msg yellow "\t - build (ver=${MONERO_VERSION}) (docker_build_args) - Build the monero docker image. Can specify a version if you want to build a specific version image of Monero (e.g. 'v0.17.2.3'), as well as extra build args e.g. '--build-arg MONERO_CONFIG_FILE=/monero/custom.conf'"
    msg yellow "\t - install (ver=${MONERO_VERSION}) - Install a binary Monero image from docker hub (default image: someguy123/monero)"
    msg yellow "\t - monitor - Monitor your Monero RPC daemon's sync progress, compares against a remote RPC ( $REMOTE_RPC ) to give you an ETA until fully synced"
    msg yellow "\t - status - Show the current block number + version of your Monero daemon, plus the current block / version of REMOTE_RPC ( $REMOTE_RPC )"
    msg yellow "\t - query (-v) (host=${RPC_HOST}) [method] (params=[]) - Call a JSON RPC method against either your local Monero RPC daemon / wallet, or a remote daemon / wallet"
    msg yellow "\t - restart - Restart monero and wallet RPC - alias for 'docker-compose restart'"
    msg
}

cd "$DIR"

(($#<1)) && _help && exit

case $1 in
    setup)
        setup
        ;;
    start)
        docker-compose up -d
        ;;
    stop)
        docker-compose down
        ;;
    restart)
        docker-compose restart
        ;;
    build)
        build "${@:2}"
        exit $?
        ;;
    install|download)
        dkinstall "${@:2}"
        exit $?
        ;;
    install_docker)
        install_docker && install_dkcompose
        ;;
    create_wallet)
        create_wallet "${@:2}"
        ;;
    create_account)
        create_account "${@:2}"
        ;;
    query)
        mnquery "${@:2}"
        ;;
    status)
        mnr-status
        ;;
    monitor)
        mnr-monitor
        ;;
    help)
        _help
        ;;
    *)
        msg red "Invalid command '$1'."
        msg
        _help
        ;;
esac

