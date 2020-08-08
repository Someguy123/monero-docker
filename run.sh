#!/usr/bin/env bash
#####
# Monero-in-a-box
# (C) 2019 Someguy123
#####

# directory where the script is located, so we can source files regardless of where PWD is
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/lib/000_helpers.sh" &> /dev/null

[[ -f "${DIR}/.env" ]] && source "${DIR}/.env"

if [[ ! -f "${DIR}/.env" ]]; then
    >&2 msg yellow "\n [!!!] Warning: ${DIR}/.env not found. Copying ${DIR}/env.example to ${DIR}/.env ...\n"
    >&2 cp -v "${DIR}/env.example" "${DIR}/.env"
fi

: ${DATADIR="${DIR}/data"}

: ${WALLET_CONF="${DATADIR}/wallet.conf"}
: ${MONEROD_CONF="${DATADIR}/monerod.conf"}
: ${EXAMPLE_WALLET_CONF="${WALLET_CONF}.example"}
: ${EXAMPLE_MONEROD_CONF="${MONEROD_CONF}.example"}

: ${WALLET_CTR='monero_wallet'}
: ${WALLET_HOST='http://127.0.0.1:18100/json_rpc'}
: ${WALLET_NAME='mnrwallet'}
: ${RPC_CTR='monerod'}
: ${RPC_LOGIN='example:example'}

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
    install_docker)
        install_docker && install_dkcompose
        ;;
    create_wallet)
        create_wallet "${@:2}"
        ;;
    create_account)
        create_account "${@:2}"
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

