#!/bin/bash

REMOTE_USER = ""
REMOTE_HOST = ""
REMOTE_PORT = 
LOCAL_PORT = 


kill_remote_ports() {
    ssh $REMOTE_USER@$REMOTE_HOST '
        pids=$(lsof -i :$REMOTE_PORT -t);
        for pid in $pids;
            do echo "Killing process $pid..."
            kill $pid;
        done;
        exit;
    '
}

create_tunnel() {
    ssh -fN -R $LOCAL_PORT:localhost:$REMOTE_PORT $REMOTE_USER@$REMOTE_HOST
    echo "redirect on $LOCAL_PORT is up!"
}



kill_remote_ports
create_tunnel

#    crontab -e
#    */5 * * * * /path/to/script/auto-ssh-script.sh

