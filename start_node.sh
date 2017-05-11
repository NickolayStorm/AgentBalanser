#! /bin/bash

COOCIE=1488228228

node_number=$1
ip=$2

CMD="n = Commands.start_link \"node$node_number.json\", :\"server@$ip\""

echo "Server IP address: $ip"

echo $CMD

iex --name "node$node_number@$ip" --cookie $COOCIE -S mix
