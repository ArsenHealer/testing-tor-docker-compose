#!/bin/bash

BOOTSTRAP_FLAG=/bootstrapped
TOR_DIR=/var/lib/tor/.tor
KEYS_DIR=${TOR_DIR}/keys

TORRC=/etc/tor/torrc
TORRC_BASE=/opt/torrc.base
TORRC_DA=/opt/torrc.da
TORRC_RELAY=/opt/torrc.relay
TORRC_EXIT=/opt/torrc.exit
TORRC_CLIENT=/opt/torrc.client
TORRC_HS=/opt/torrc.hidden
STATUS_AUTHORITIES=/shavol/dir-authorities

if [[ -z "${ROLE}" ]]; then
    echo "No role defined, did you set the ROLE environment variable properly?"
    exit 1
fi

touch $STATUS_AUTHORITIES

function wait_for_all_das {
    echo "Waiting for all directory authorities to register..."

    while true; do
        # Подсчет уникальных строк DirAuthority
        COUNT=$(sort -u ${STATUS_AUTHORITIES} | grep -c "^DirAuthority")

        if [[ $COUNT -ge 3 ]]; then
            echo "All directory authorities registered!"
            break
        fi

        sleep 5  # Ждем 5 секунд перед повторной проверкой
    done
}

function bootstrap {
    echo "IP address is ${IP_ADDR}"

    cp ${TORRC_BASE} ${TORRC}

    case $ROLE in
    da)
        echo "Setting up node as a directory authority"
        echo "Nickname is ${NICK}"
        echo "Nickname ${NICK}" >>${TORRC}
        echo "Address ${IP_ADDR}" >>${TORRC}
        echo "ContactInfo ${NICK} <${NICK} AT localhost>" >>${TORRC}
        cat ${TORRC_DA} >>${TORRC}
        cd ${KEYS_DIR}

        echo $(tr -dc A-Za-z0-9 </dev/urandom | head -c 12) | \
            sudo -u debian-tor tor-gencert --create-identity-key -m 12 -a ${IP_ADDR}:80 --passphrase-fd 0

        cd ${TOR_DIR}
        sudo -u debian-tor tor --list-fingerprint --dirauthority "placeholder 127.0.0.1:80 0000000000000000000000000000000000000000"

        AUTH_CERT_FINGERPRINT=$(grep "fingerprint" ${KEYS_DIR}/authority_certificate | cut -d " " -f 2)
        SERVER_FINGERPRINT=$(cat ${TOR_DIR}/fingerprint | cut -d " " -f 2)

        touch ${TOR_DIR}/{approved-routers,sr-state}
        chown debian-tor:debian-tor ${TOR_DIR}/{approved-routers,sr-state}

        DA_ENTRY="DirAuthority ${NICK} orport=9001 no-v2 v3ident=$AUTH_CERT_FINGERPRINT ${IP_ADDR}:80 $SERVER_FINGERPRINT"

        # Проверяем, есть ли уже такая запись, если нет — добавляем
        if ! grep -qF "$DA_ENTRY" "$STATUS_AUTHORITIES"; then
            echo "$DA_ENTRY" >> "$STATUS_AUTHORITIES"
        fi

        # Ожидание всех DA перед продолжением
        wait_for_all_das
        ;;
    relay)
        echo "Setting up node as a guard/mid relay"
        echo "Nickname is ${NICK}"
        echo "Nickname ${NICK}" >>${TORRC}
        echo "Address ${IP_ADDR}" >>${TORRC}
        echo "ContactInfo ${NICK} <${NICK} AT localhost>" >>${TORRC}
        cat ${TORRC_RELAY} >>${TORRC}
        ;;
    exit)
        echo "Setting up node as an exit relay"
        echo "Nickname is ${NICK}"
        echo "Nickname ${NICK}" >>${TORRC}
        echo "Address ${IP_ADDR}" >>${TORRC}
        echo "ContactInfo ${NICK} <${NICK} AT localhost>" >>${TORRC}
        cat ${TORRC_EXIT} >>${TORRC}
        ;;
    client)
        echo "Setting up node as a client"
        cat ${TORRC_CLIENT} >>${TORRC}
        ;;
    hs)
        echo "Setting up node as a hidden service"
        cat ${TORRC_HS} >>${TORRC}
        if [[ -z "${HS_PORT}" ]]; then HS_PORT="80"; fi
        if [[ -z "${SERVICE_PORT}" ]]; then SERVICE_PORT="80"; fi
        if [[ -z "${SERVICE_IP}" ]]; then SERVICE_IP="127.0.0.1"; fi
        echo "HiddenServicePort ${HS_PORT} ${SERVICE_IP}:${SERVICE_PORT}" >>${TORRC}
        ;;
    *)
        echo "Unknown node type, exiting"
        ;;
    esac

    touch ${BOOTSTRAP_FLAG}
}

if [ ! -f ${BOOTSTRAP_FLAG} ]; then
    bootstrap
fi

# Ждем, пока в файле появятся все три DA (если по какой-то причине пропустили)
wait_for_all_das

# Удаляем дубликаты перед записью в torrc
sort -u ${STATUS_AUTHORITIES} -o ${STATUS_AUTHORITIES}
cat ${STATUS_AUTHORITIES} >>${TORRC}

# Запуск TOR или передача управления другому процессу
if [[ ! -z "$@" ]]; then
    exec "$@"
else
    sudo -u debian-tor tor -f /etc/tor/torrc
fi
