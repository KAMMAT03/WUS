#!/bin/bash

NGINX_PORT=$1
SERVER_ADDRESS=$2
BACKEND_PORT1=$3
BACKEND_PORT2=$4
BACKEND_PORT3=$5

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y nginx

cd ~/

cat > loadbalancer2.conf << EOL
upstream backend {
    server $SERVER_ADDRESS:$BACKEND_PORT1;
    server $SERVER_ADDRESS:$BACKEND_PORT2;
    server $SERVER_ADDRESS:$BACKEND_PORT3;
}

server {
    listen      $NGINX_PORT;

    location /petclinic/api {
        proxy_pass http://backend;
    }
}
EOL

sudo mv loadbalancer2.conf /etc/nginx/conf.d/loadbalancer2.conf

sudo nginx -s reload
