#!/bin/bash -eu
#shellcheck disable=SC2086,SC2015,SC2164
DEBUG=false

if [[ -z "$USER_NAME" || "${#USER_NAME}" = "0" ]]; then USER_NAME=appveyor; fi
if [[ -z "$USER_HOME" || "${#USER_HOME}" = "0" ]]; then USER_HOME=/home/appveyor; fi
if [[ -z "$DATEMARK" || "${#DATEMARK}" = "0" ]]; then DATEMARK=$(date +%Y%m%d%H%M%S); fi
HOST_NAME=appveyor-vm
MSSQL_SA_PASSWORD=Password12!
MYSQL_ROOT_PASSWORD=Password12!
POSTGRES_ROOT_PASSWORD=Password12!
CURRENT_NODEJS=8
AGENT_DIR=/opt/appveyor/build-agent
WORK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_FILE=$HOME/versions-$DATEMARK.log
LOGGING=true
SCRIPT_PID=$$

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root. Aborting." 1>&2
    exit 1
fi

case  ${PACKER_BUILDER_TYPE} in
    googlecompute )
        BUILD_AGENT_MODE=GCE;;
    hyperv* )
        BUILD_AGENT_MODE=HyperV;;
    azure* )
        BUILD_AGENT_MODE=Azure;;
    * )
        BUILD_AGENT_MODE=GCE;;
esac

# search for scripts we source
LIB_FOLDERS=( "${HOME}/scripts" "${WORK_DIR}" "${HOME}" )
for LIB_FOLDER in "${LIB_FOLDERS[@]}"; do
    if [ -f "${LIB_FOLDER}/common.sh" ]; then
        echo "[DEBUG] installation scripts found in ${LIB_FOLDERS[*]}"
        break
    fi
done

# shellcheck source=./common.sh
. "${LIB_FOLDER}/common.sh" ||
        { echo "[ERROR] Cannot source common.sh script. Aborting." 1>&2; exit 2; }

if [ -f /etc/os-release ]; then
    OS_CODENAME=$(source /etc/os-release && echo $VERSION_CODENAME)
    if [ -f "${LIB_FOLDER}/${OS_CODENAME}.sh" ]; then
        # shellcheck source=./bionic.sh
        . "${LIB_FOLDER}/${OS_CODENAME}.sh" ||
            { echo "[WARNING] Cannot source ${OS_CODENAME}.sh script." 1>&2; }
    fi
else
    echo "[WARNING] /etc/os-release not found - cant find VERSION_CODENAME. Will not install OS specific applications."
fi

function _abort() {
    echo "Aborting." 1>&2
    exit "$1"
}

function _continue() {
    echo "Continue installation..." 1>&2
}

# we have to create pwd.log, otherwise packer will fail on provisioner which downloads it.
touch ${HOME}/pwd-${DATEMARK}.log

init_logging

# execute only required parts of deployment
if [ "$#" -gt 0 ]; then
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            install_buildagent)     install_buildagent "${BUILD_AGENT_MODE}" || _abort $?; ;;
            *)                      echo "[ERROR] Unknown argument '$1'"; ;;
        esac
        shift
    done
    exit 0
fi

configure_path

configure_locale

add_user ||
    _abort $?

chown_logfile || _continue

configure_apt ||
    _abort $?

install_tools ||
    _abort $?

if [ "${BUILD_AGENT_MODE}" == "HyperV" ]; then
    install_KVP_packages ||
        _abort $?
fi

install_appveyoragent "${BUILD_AGENT_MODE}" ||
    _abort $?

if ! ${DEBUG}; then                          ### Disabled for faster debugging

install_p7zip

install_pip ||
    _abort $?


make_git 2.21.0 ||
    _abort $?

install_gitlfs ||
    _abort $?
su -l ${USER_NAME} -c "
        USER_NAME=${USER_NAME}
        $(declare -f configure_gitlfs)
        configure_gitlfs" ||
    _abort $?

su -l ${USER_NAME} -c "
        curl -sflL 'https://raw.githubusercontent.com/appveyor/secure-file/master/install.sh' | bash -e -" ||
    _abort $?

install_cvs ||
    _abort $?
su -l ${USER_NAME} -c "
        USER_NAME=${USER_NAME}
        $(declare -f configure_svn)
        configure_svn" ||
    _abort $?

add_ssh_known_hosts ||
    _continue $?
fi
configure_sshd ||
    _abort $?
configure_uefi ||
    _abort $?
configure_network ||
    _abort $?

cleanup
