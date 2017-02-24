#! /bin/bash

COOCIE=1488228228
CMD='Manager.start'

ip=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | grep -Po '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}' | head -1)
echo "Server IP address: $ip"

echo $CMD 
iex --name "server@$ip" --cookie $COOCIE -S mix

