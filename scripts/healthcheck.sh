#!/bin/bash

ENDPOINTS=("1.1.1.1" "8.8.8.8" "1.0.0.1" "8.8.4.4")
INTERFACES=$(wg show interfaces)

for INTERFACE in $INTERFACES; do

    # Get a random endpoint from the ENDPOINTS array
    RANDOM_ENDPOINT=${ENDPOINTS[$RANDOM % ${#ENDPOINTS[@]}]}

    # Ping the random endpoint using the specified interface
    ping -4 -c 1 -I "$INTERFACE" "$RANDOM_ENDPOINT" > /dev/null 2>&1
    
    # Check if the ping was successful
    if [ $? -ne 0 ]; then
        echo "Ping to $RANDOM_ENDPOINT from $INTERFACE failed"
        exit 1
    else
        echo "Ping to $RANDOM_ENDPOINT from $INTERFACE was successful"
    fi
done

exit 0