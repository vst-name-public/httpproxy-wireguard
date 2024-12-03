#!/bin/bash

echo "****  Starting up ****"
echo "The PID of this script is: $$"
# set -x
PS4='[${BASH_SOURCE[0]}:${LINENO}] '

# Function to stop TinyProxy and WireGuard processes
_cleanup() {
    echo "Cleaning up... Stopping processes."

    if [ -n "$1" ]; then
        echo "Container failure..."
        kill -SIGTERM 1
        kill $$
        exit $1
    fi

    if [ -n "$TINYPROXY_PID" ]; then
        echo "Stopping TinyProxy with PID $TINYPROXY_PID"
        kill $TINYPROXY_PID
    fi

    if [ -n "$DNSMASQ_PID" ]; then
        echo "Stopping TinyProxy with PID $DNSMASQ_PID"
        kill $DNSMASQ_PID
    fi
    
    wireguard_down


    exit 0
}
signal_handler() {
    echo "Caught signal: $1"
    _cleanup
}
trap 'signal_handler SIGTERM' SIGTERM
trap 'signal_handler SIGKILL' SIGKILL
trap 'signal_handler SIGINT' SIGINT
trap 'signal_handler SIGHUP' SIGHUP
trap 'signal_handler SIGQUIT' SIGQUIT

# Start CoreDNS
dnsmasq_up(){

    sed -i '/^nameserver/d' /etc/resolv.conf > /dev/null
    echo "nameserver 127.0.0.1" > /etc/resolv.conf 2>/dev/null
    local inter_dns=()
    for wgconf in "${WG_CONFS[@]}"; do
        dns_list=$(grep -oP '(?<=DNS\s=\s)[^\r\n]+' "$wgconf" | tr ',' '\n')        
        for dns in $dns_list; do
            if nslookup example.com $dns &>/dev/null; then
                echo "**** DNS $dns is working. Adding to dnsmasq.conf. ****"
                inter_dns+=("${dns}")
            else
                echo "**** DNS $dns failed. Skipping. ****"
            fi
        done
    done

    local final_dns
    if [ ${#inter_dns[@]} -gt 2 ]; then
        for dns in "${inter_dns[@]}"; do
            final_dns+=("${dns}")
        done
    else
        if [ ${#inter_dns[@]} -eq 1 ]; then
            echo "Only single valid dns server found, adding defaults"
            final_dns+=("${dns}")
        fi

        if [ ${#inter_dns[@]} -eq 0 ]; then
            echo "No valid DNS servers found. Adding default."
        fi

        inter_dns=("8.8.8.8" "1.1.1.1" "8.8.8.8" "1.0.0.1")
        for dns in "${inter_dns[@]}"; do
            final_dns+=("${dns}")
        done
    fi

    echo "DNS List"
    printf "%s\n" "${final_dns[@]}"
    for dns in $final_dns; do
        echo "server=$dns" >> /etc/dnsmasq.conf
    done


    echo cache-size=1000 >> /etc/dnsmasq.conf

    if /usr/sbin/dnsmasq &>/dev/null; then
        echo "Dnsmasq started successfully"
        DNSMASQ_PID=$(pgrep dnsmasq)
    else
        echo "Failed to start Dnsmasq"
        _cleanup "1"
    fi
}


# Start tinyproxy
TINYPROXY_PID=""
DNSMASQ_PID=""
tinyproxy_up(){
    echo "Starting tinyproxy"
    TINYPROXY_CONF=$(ls /tinyproxy/*.conf 2>/dev/null)

    if [ -z "$TINYPROXY_CONF" ]; then
        echo "No TinyProxy config found, using default."
        tinyproxy -c /app/tinyproxy.conf
    elif [ $(echo "$TINYPROXY_CONF" | wc -l) -eq 1 ]; then
        echo "Using TinyProxy config $TINYPROXY_CONF"
        tinyproxy -c "$TINYPROXY_CONF"
    else
        echo "ERROR: Multiple TinyProxy config files found, only a single config file is allowed."
        exit
    fi

    local TIMEOUT=10
    local ELAPSED_TIME=0
    if [ $? == 0 ]; then
        while ! pgrep tinyproxy > /dev/null; do
            if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
                echo "TinyProxy startup timed out after $TIMEOUT seconds"
                _cleanup "1"
            fi
            
            echo "Waiting for tinyproxy to start..."
            sleep 1
            ELAPSED_TIME=$((ELAPSED_TIME + 1))
        done
        
        TINYPROXY_PID=$(pgrep tinyproxy)
        echo "TinyProxy started with PID $TINYPROXY_PID"
    else
        echo "TinyProxy startup failed"
        _cleanup "1"
    fi
}


unset WG_CONFS
rm -rf /app/activeconfs
WG_CONFS=()

# Enumerate interfaces
for wgconf in $(ls /config/wg_confs/*.conf); do
    if grep -q "\[Interface\]" "${wgconf}"; then
        echo "**** Found WG conf ${wgconf}, adding to list ****"
        WG_CONFS+=("${wgconf}")
    else
        echo "**** Found WG conf ${wgconf}, but it doesn't seem to be valid, skipping. ****"
    fi
done

if [[ -z "${WG_CONFS}" ]]; then
    echo "**** No valid tunnel config found. Please create a valid config and restart the container ****"
    if ip route show default > /dev/null; then
        ip route del default
    fi
    _cleanup "1"
fi

unset FAILED

wireguard_down(){
    if [ -n "$1" ]; then
        wg-quick down "$1" >> /proc/self/fd/1 2>> /proc/self/fd/2 || {
            echo "Failed to bring down WireGuard at tunnel '$(basename "$1" .conf)'" >&2
        }
        echo "Brought down WireGuard at tunnel '$(basename "$1" .conf)'"
        return
    fi
    for tunnel in ${WG_CONFS[@]}; do
        echo "Stopping wg $tunnel"
        wg-quick down "${tunnel}" >> /proc/self/fd/1 2>> /proc/self/fd/2 || { echo "Failed to kill Wireguard at tunnel '$tunnel'"; _cleanup "1"; }
    done
}

wireguard_up(){
    if [ -n "$1" ]; then
        wg-quick up "$1" >> /proc/self/fd/1 2>> /proc/self/fd/2 || {
            echo "Failed to bring up Wireguard at tunnel '$(basename "$1" .conf)'" >&2
            _cleanup "1"
        }
        return
    fi
    
    for tunnel in ${WG_CONFS[@]}; do
        echo "**** Activating tunnel ${tunnel} ****"
        if wg-quick up "${tunnel}" >> /proc/self/fd/1 2>> /proc/self/fd/2; then
            echo "**** Tunnel $(basename $tunnel .conf) is active ****"
        else
            FAILED="${tunnel}"
            break
        fi
    done

    if [[ -z "${FAILED}" ]]; then
        declare -p WG_CONFS > /app/activeconfs
        echo "**** All tunnels are now active ****"
    else
        echo "**** Tunnel ${FAILED} failed, will stop all others! ****"
        for tunnel in ${WG_CONFS[@]}; do
            if [[ "${tunnel}" = "${FAILED}" ]]; then
                break
            else
                echo "**** Disabling tunnel ${tunnel} ****"
                wg-quick down "${tunnel}" >> /proc/self/fd/1 2>> /proc/self/fd/2 || :
            fi
        done
        ip route del default
        echo "**** All tunnels are now down. Please fix the tunnel config ${FAILED} and restart the container ****"
        _cleanup "1"
    fi

    while [ -z "$(wg show)" ]; do
        local TIMEOUT=10
        local ELAPSED_TIME=0
        if [ "$ELAPSED_TIME" -lt "$TIMEOUT" ]; then
            echo "Waiting for WireGuard to start..."
        else
            echo "Wireguard failed to activate"
            _cleanup "1"
        fi
        sleep 1
    done
}
FAIL_COUNTER=0
check_processes() {
    if ! ps -p $TINYPROXY_PID > /dev/null; then
        echo "TinyProxy process is not running, restarting..."
        FAIL_COUNTER=$((FAIL_COUNTER + 1))
        tinyproxy_up
    fi

    if ! ps -p $DNSMASQ_PID > /dev/null; then
        echo "Dnsmasq process is not running, restarting..."
        FAIL_COUNTER=$((FAIL_COUNTER + 1))
        dnsmasq_up
    fi

    for tunnel in ${WG_CONFS[@]}; do
        local INTERFACE=$(basename $tunnel .conf)
        local WIREGUARD_STATUS=$(wg show $INTERFACE)
        if [ -z "$WIREGUARD_STATUS" ] || ! wg show "$INTERFACE" > /dev/null 2>&1; then
            echo "WireGuard process is not running, restarting..."
            FAIL_COUNTER=$((FAIL_COUNTER + 1))
            wireguard_down "$tunnel"
            sleep 10
            wireguard_up "$tunnel"
        fi
    done
    if [ $FAIL_COUNTER -eq 10 ]; then
        echo "Reached max failure limit - 10"
        _cleanup "1"
    fi
}

wireguard_up
dnsmasq_up
tinyproxy_up
while true; do
    check_processes
    sleep 10
done
