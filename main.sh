#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

check_tunnel() {
    netstat -tn | grep ":$LOCAL_PORT" | grep -q ESTABLISHED
}

kill_remote_ports() {
    ssh -p $REMOTE_PORT2 $REMOTE_USER@$REMOTE_HOST "
        sudo fuser -k $REMOTE_PORT1/tcp;
        sudo fuser -k $REMOTE_PORT2/tcp;
    "
}

create_tunnel() {
    ssh -fN -L $LOCAL_PORT:localhost:$REMOTE_PORT1 $REMOTE_USER@$REMOTE_HOST
}



if check_tunnel; then
    echo "Tunnel is up"
else
    echo "Tunnel is down. Restarting..."
    kill_remote_ports
    create_tunnel
    if check_tunnel; then
        echo "Tunnel successfully created"
    else
        echo "Failed to create tunnel"
    fi
fi
