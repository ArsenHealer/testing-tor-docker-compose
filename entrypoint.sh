if [[ -z "$*" ]]; then
    # Если команда не передана, запускаем Tor
    sudo -u debian-tor tor -f /etc/tor/torrc
else
    # Если команда передана, выполняем её
    exec "$@"
fi