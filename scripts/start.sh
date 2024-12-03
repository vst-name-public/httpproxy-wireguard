#!/bin/bash

echo $@


# Function to stop TinyProxy and WireGuard processes
cleanup() {
    echo "Cleaning up... Stopping processes."
    if [ -n "$TINYPROXY_PID" ]; then
        echo "Stopping TinyProxy with PID $TINYPROXY_PID"
        kill $TINYPROXY_PID
        if [[ $? -ne 0 ]]; then
            echo "Failed to kill TinyProxy"
            exit 1
        fi
    fi
    wireguard_down
    exit 0
}

# Set up a trap to catch 'SIGINT SIGTERM HUP INT QUIT TERM' signales
trap cleanup SIGINT SIGTERM HUP INT QUIT TERM

# Start tinyproxy
TINYPROXY_PID=""
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


    TIMEOUT=10
    ELAPSED_TIME=0
    if [ $? == 0 ]; then
        while ! pgrep tinyproxy > /dev/null; do
            if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
                echo "TinyProxy startup timed out after $TIMEOUT seconds"
                exit 1
            fi
            
            echo "Waiting for tinyproxy to start..."
            sleep 1
            ELAPSED_TIME=$((ELAPSED_TIME + WAIT_TIME))
        done
        
        TINYPROXY_PID=$(pgrep tinyproxy)
        echo "TinyProxy started with PID $TINYPROXY_PID"
    else
        echo "TinyProxy startup failed"
        exit 1
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
    exit 1
fi

unset FAILED

wireguard_down(){
    for tunnel in ${WG_CONFS[@]}; do
        echo "Stopping wg $tunnel"
        wg-quick down "${tunnel}" >> /proc/self/fd/1 2>> /proc/self/fd/2 || { echo "Failed to kill Wireguard at tunnel '$tunnel'"; exit 1; }
    done
}

wireguard_up(){
    for tunnel in ${WG_CONFS[@]}; do
        echo "**** Activating tunnel ${tunnel} ****"
        if wg-quick up "${tunnel}" >> /proc/self/fd/1 2>> /proc/self/fd/2; then
            # Capture the PID of the actual WireGuard process (not wg-quick)
            WIREGUARD_PID=$(pgrep -o -f "wg")
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
    fi
}

check_processes() {
    if ! ps -p $TINYPROXY_PID > /dev/null; then
        echo "TinyProxy process is not running, restarting..."
        tinyproxy_up
    fi

    # echo "DEBUG - WIREGUARD_PID is '$WIREGUARD_PID'"
    # if ! ps -p $WIREGUARD_PID > /dev/null; then
    #     echo "WireGuard process is not running, restarting..."
    #     wireguard_down
    #     wireguard_up
    # fi
}

tinyproxy_up
wireguard_up

while true; do
    check_processes
    sleep 5
done
