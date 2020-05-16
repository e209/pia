#!/bin/bash

source lib_main.sh
source lib_checks.sh

cmd_expected="start-3proxy"

tproxy_pidfile="/var/run/3proxy.pid"
tproxy_init_conf_file="/addconf/3proxy/3proxy.cfg"
tproxy_persist_conf_file="/etc/3proxy/3proxy.cfg"

# set -x for debug
set +x

function switchoff
{
	pr "Switching off. Container keeps running to prevent autorestart (remember restart policy)".

	# disable networking by wiping out all rules (default policy is DROP)
	iptables --flush

        wait_forever 
}


if [ "$1" = "$cmd_expected" ]; then

	pr "[entrypoint.sh $@] Container started, initializing..."


	if [ -z "$LOGIN" ] || [ -z "$PASSWORD" ]; then
	  pr 'ERROR: 3proxy not initialized because LOGIN and PASSWORD variables is not defined '
	  switchoff
	fi


	if [ -f "$tproxy_init_conf_file" ]; then
	  cp "$tproxy_init_conf_file" "$tproxy_persist_conf_file"
	else
	  pr "ERROR: 3proxy not initialized because template configuration file $tproxy_init_conf_file is not found"
	  switchoff
	fi

	eth0_network=$(ip -o -4 address show | awk '/eth0/ {print $4}')
	eth0_ip=$(echo $eth0_network | cut -d/ -f1)
        pia_ovpn_container_ip=$(nslookup $OVPN_CONTAINER_NAME | awk '$1~/Address:/ && $2!~/53$/ {print $2}')

	# Initial firewall settings (dynamic rules will be later added and removed by external scripts)

	# wipe out firewall existing rules
	iptables --flush

	# setting full blocking policies
	iptables --table filter --policy INPUT DROP
	iptables --table filter --policy FORWARD DROP
	iptables --table filter --policy OUTPUT DROP


	# allow localhost
	iptables --table filter --append INPUT --jump ACCEPT --in-interface lo
	iptables --table filter --append OUTPUT --jump ACCEPT --out-interface lo

	# unrestricted access only for specific ports
	iptables --table filter --append INPUT  --jump ACCEPT --in-interface eth0  --protocol tcp --dport 1080
	iptables --table filter --append OUTPUT --jump ACCEPT --out-interface eth0 --protocol tcp --sport 1080
	iptables --table filter --append INPUT  --jump ACCEPT --in-interface eth0  --protocol tcp --dport 3128
	iptables --table filter --append OUTPUT --jump ACCEPT --out-interface eth0 --protocol tcp --sport 3128

	# for docker bridge network access (interconnecting ajacent containers, e.g. in the same compose project)
	iptables --table filter --append INPUT  --jump ACCEPT --source $eth0_network --in-interface  eth0
	iptables --table filter --append OUTPUT --jump ACCEPT --destination $eth0_network --out-interface eth0



	# setting up proxy configuration

	if test ! -f "$tproxy_persist_conf_file"; then
	  pr "ERR: 3proxy conf file '$tproxy_persist_conf_file' doesn't exist"
	  switchoff
	fi

	sed -i "s/\$LOGIN/$LOGIN/g" "$tproxy_persist_conf_file"
	sed -i "s/\$PASSWORD/$PASSWORD/g" "$tproxy_persist_conf_file"
   
	sed -i "s/\$PARENT_PROXY_IP/$pia_ovpn_container_ip/g" "$tproxy_persist_conf_file"
	sed -i "s/\$THIS_HOST_IP/$eth0_ip/g" "$tproxy_persist_conf_file"
	sed -i "s/\$LOCAL_NETWORK_IP/$LOCAL_NETWORK_IP/g" "$tproxy_persist_conf_file"
	sed -i "s/\$LOCAL_NETWORK_MASK/$LOCAL_NETWORK_MASK/g" "$tproxy_persist_conf_file"

	sed -i "s:\$PIDFILE:$tproxy_pidfile:g" "$tproxy_persist_conf_file"


	# starting up 3proxy daemon
        /usr/bin/3proxy "$tproxy_persist_conf_file" 

	if test $? -eq 0 -a -f $tproxy_pidfile; then
          pr "3proxy daemon started succesfully"
	else
	  pr "ERR: 3proxy daemon not started successfully (exit status=$?)"
	  switchoff
	fi


	bkground_pids=$(cat "$tproxy_pidfile")${bkground_pids:+" $bkground_pids"}

	# this block is only for 'direct' (without second upstream proxy) access, e.g. all traffic except for local will be routed to VPN container
	# do not forget also add special NAT masquerading rule to local network internet gateway firewall on router (on 'internal' iface)!
	# this rule must rewrite src IP (from remote internet host) to one from $LOCAL_NETWORK_IP/$LOCAL_NETWORK_MASK (e.g. 192.168.0.0/24)
	# otherwise all answers to proxy client will be routed into VPN because these rules
#	default_gw=$(ip route show | awk '/default/ {print $3}')
#	ip route add $LOCAL_NETWORK_IP/$LOCAL_NETWORK_MASK via $default_gw dev eth0
#	ip route change default via $pia_ovpn_ip dev eth0


	wait_forever


elif [ "$@" = "" ]; then

	# no arguments given to entrypoint script,  only wait in foreground (to keep detached container running)
	wait_forever

else
	#other argument(s) given, only passing to shell (debugging)
	exec "$@"
	exit
fi

