# If a Docker CMD is specify, run it. Else, boot TOR!
if [[ ! -z "$@" ]]; then
    exec $@
else
    sudo -u debian-tor tor -f /etc/tor/torrc
fi
