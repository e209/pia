#!/bin/bash
# bash required for specific syntax

source lib_main.sh
source lib_checks.sh

cmd_expected="start-ovpn-dante"

openvpn_pid_file=/var/run/openvpn.pid
dante_pid_file=/var/run/sockd.pid
dante_init_conf_file=/addconf/dante/sockd.conf
dante_persist_conf_file=/etc/conf.d/sockd.conf

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


	cd /etc/openvpn

	# presuming none of *.ovpn exists (using no persistent volume), get configuration from provider
	# straightforward 'if [ ! -f *.ovpn ]' doesn't work: glob expands to list of filenames, and second filename after -f raises syntax error

	if test -z "$(find . -maxdepth 1 -name '*.ovpn' -print -quit)"; then
	  wget -q 'https://www.privateinternetaccess.com/openvpn/openvpn-strong.zip'
	  unzip -qo 'openvpn-strong.zip' -d '/etc/openvpn/'
	  rm -f 'openvpn-strong.zip'
	fi

	if test -z "${REGION-""}"; then
	  pr "ERROR: No REGION parameter set."
 	  switchoff
	fi

	if test ! -f "${REGION}.ovpn"; then
	  pr "ERROR: No ${REGION}.ovpn file found."
	  switchoff
	fi 

	# stripping out persist-tun directive (otherwise ovpn client will hang on USR1 restart signal, failing to connect)
	grep -v '^persist-tun' "${REGION}.ovpn" > ovpn.conf

	if [ -n "${LOGIN-""}" -a -n "${PASSWORD-""}" ]; then
	  echo "$LOGIN" > auth.conf
	  echo "$PASSWORD" >> auth.conf
	  chmod 600 auth.conf
	else
	  pr "ERROR: OpenVPN credentials not set."
	  switchoff
	fi

	# Initial firewall settings (dynamic rules will be later added and removed by external scripts)

	# wipe out existing firewall rules
	iptables --flush

	# setting full blocking policies
	iptables --table filter --policy INPUT DROP
	iptables --table filter --policy FORWARD DROP
	iptables --table filter --policy OUTPUT DROP


	# allow localhost
	iptables --table filter --append INPUT --jump ACCEPT --in-interface lo
	iptables --table filter --append OUTPUT --jump ACCEPT --out-interface lo

	# allow any UDP for DNS and peer VPN connection (temporary rules, will be replaced by more narrow in '--up' OpenVPN script) 
	iptables --table filter --append INPUT  --protocol udp --in-interface  eth0 --jump ACCEPT
	iptables --table filter --append OUTPUT --protocol udp --out-interface eth0 --jump ACCEPT

	openvpn --daemon --writepid "$openvpn_pid_file" --config /etc/openvpn/ovpn.conf  --auth-user-pass auth.conf \
		--verb 1 \
		--up-restart \
		--script-security 2 \
		--up /usr/local/bin/tun_firewall_rules.sh \
		--down-pre \
		--down /usr/local/bin/tun_firewall_rules.sh 

	if test $? -eq 0; then
	  timeout 2 sh -c "until test -f $openvpn_pid_file; do sleep 0.1; done"
	  if test $? -ne 0; then err="waiting for pidfile timeout"; fi
	else
	  err="exit status=$?"
	fi

	if test -z "${err-""}" ; then
          pr "OpenVPN daemon started succesfully"
	else
	  pr "ERR: OpenVPN daemon not started successfully ($err)"
	  switchoff
	fi

	bkground_pids=$(cat "$openvpn_pid_file")${bkground_pids:+" $bkground_pids"}


	pr "Waiting for tun0 up..."

	# waiting until tun0 is up (this is also connectivity test - container restarts if timeout expires)
	left_seconds=${WAIT_FOR_TUN:=60}

	until ifconfig tun0 2>/dev/null | grep -q "HWaddr 00-00-00-"
	do
	   sleep 1;let left_seconds=$left_seconds-1 
	   if [ $left_seconds -eq 0 ]; then 
		exit_status=2 
	        pr "After $WAIT_FOR_TUN sec timeout 'tun0' iface didn't got up, no connectivity. Container will be restarted. Exiting ($exit_status)."
		kill 1 # remember restart policy 
	   fi 
	done

	# first checking if we're in the right location

	countrycheck init
	if test $? -eq 0; then
	   pr "Enabling access to the VPN from outside..."
	else
	   switchoff
	fi

	bridge_network=$(ip -o address show | awk '/eth0/ {print $4}')
	default_gw=$(ip route show | awk '/default/ {print $3}')

	# local network access
	iptables --table filter --append INPUT  --jump ACCEPT --source $LOCAL_NETWORK_IP/$LOCAL_NETWORK_MASK --in-interface  eth0
	iptables --table filter --append OUTPUT --jump ACCEPT --destination $LOCAL_NETWORK_IP/$LOCAL_NETWORK_MASK --out-interface eth0

	# METHOD #1: these rules (INPUT/OUTPUT chain) needed only for connect from external proxy through second proxy in this container
	# for docker bridge network (interconnecting ajacent containers, e.g. in the same compose project) access
	iptables --table filter --append INPUT  --jump ACCEPT --source $bridge_network --in-interface  eth0
	iptables --table filter --append OUTPUT --jump ACCEPT --destination $bridge_network --out-interface eth0

	# METHOD #2: these rules (FORWARD chain) needed only for direct access from external proxy by redirecting all traffic  into this container
	# for access to tun interface from adjacent containers (in the same docker bridge network)
	#iptables --table filter --append FORWARD --source $bridge_network      --in-interface eth0 --out-interface tun0 --jump ACCEPT
	#iptables --table filter --append FORWARD --destination $bridge_network --in-interface tun0 --out-interface eth0 --jump ACCEPT
	#iptables --table nat --append POSTROUTING -o tun0  -j MASQUERADE # for translating source IP from the bridge to the tun interface network

	# configuring Dante socks proxy

	if [ -f "$dante_init_conf_file" ]; then
	  cp "$dante_init_conf_file" "$dante_persist_conf_file"
	else
	  pr "ERROR: Dante not initialized because template configuration file '$dante_init_conf_file' is not found"
	  switchoff
	fi

	# setting up proxy configuration

	if test ! -f "$dante_persist_conf_file"; then
	  pr "ERR: Dante proxy (sockd) conf file '$dante_persist_conf_file' doesn't exist"
	  switchoff
	fi

	sed -i "s/\$LOCAL_NETWORK_IP/$LOCAL_NETWORK_IP/g" "$dante_persist_conf_file"
	sed -i "s/\$LOCAL_NETWORK_MASK/$LOCAL_NETWORK_MASK/g" "$dante_persist_conf_file"
	sed -i "s:\$bridge_network:$bridge_network:g" "$dante_persist_conf_file" # because $bridge_network contains slash


	# for answering from proxy (in this container) to local network hosts, otherwise the packets will be routed into tun
	ip route add $LOCAL_NETWORK_IP/$LOCAL_NETWORK_MASK via $default_gw dev eth0


	# starting up Dante proxy
        /usr/sbin/sockd -D -p "$dante_pid_file" -f "$dante_persist_conf_file"

	# these tricks are needed because for some reason just after 'sockd' execution the pidfile is not ready (not exist)
	if test $? -eq 0 ; then
	  timeout 2 sh -c "until test -f "$dante_pid_file"; do sleep 0.1; done"
	  if test $? -ne 0; then err="pidfile appearance timeout"; fi
	else
	  err="exit status=$?"
	fi

	if test -z "${err-""}"; then
          pr "Dante sockd daemon started succesfully"
	else
	  pr "ERR: Dante proxy (sockd) daemon not started successfully ($err)"
	  switchoff
	fi

	bkground_pids=$(cat "$dante_pid_file")${bkground_pids+ $bkground_pids}


	# all done! wait enough for completing tasks in background (preventing its output after "Checking connectivity..." line, see below)

	pr "Waiting another 3s while all background inits completed..."
	sleep 3 

	pr "All inits done. Checking connectivity every ${COUNTRYCHECK_INTERVAL:=120} seconds ..."

	continuous_check

elif [ "$@" = "" ]; then

	# no arguments given to entrypoint script,  only wait in foreground (to keep detached container running)
	wait_forever

else
	#other argument(s) given, only passing to shell (debugging)
	exec "$@"
	exit
fi

