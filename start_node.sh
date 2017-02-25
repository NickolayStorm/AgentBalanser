#! /bin/bash

COOCIE=1488228228

node_number=$1
ip=$2

CMD="spawn_link fn -> Tasks.start \"node$node_number.json\", :\"server@$ip\" end"

echo "Server IP address: $ip"

echo $CMD
 
iex --name "node$node_number@$ip" --cookie $COOCIE -S mix

