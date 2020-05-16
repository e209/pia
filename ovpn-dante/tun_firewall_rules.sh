#!/bin/bash

# OpenVPN invokes this script as /usr/sbin/<scriptname> tun0 1500 1570 10.4.10.6 10.4.10.5 init
# and provides number of variables, for example (uncomment for debugging):
#echo "\$script_context:$script_context"
#echo "\$script_type:$script_type"


function permanent_rules
{
  # tun/tap device access
  eval "iptables --table filter --$1 INPUT  --jump ACCEPT --in-interface  $dev --destination $ifconfig_local"
  eval "iptables --table filter --$1 OUTPUT --jump ACCEPT --out-interface $dev --source $ifconfig_local"

  # remote OpenVPN peer access
  eval "iptables --table filter --$1 OUTPUT --jump ACCEPT --destination $trusted_ip/32 --out-interface eth0 --protocol udp --dport $trusted_port"
  eval "iptables --table filter --$1 INPUT  --jump ACCEPT --source      $trusted_ip/32  --in-interface eth0 --protocol udp --sport $trusted_port"
}

function temporary_rules
{
  eval "iptables --table filter --$1 INPUT --jump ACCEPT --protocol udp --in-interface eth0"
  eval "iptables --table filter --$1 OUTPUT --jump ACCEPT --protocol udp --out-interface eth0"
}

if [ "$script_type" = "up" -a "$script_context" = "init" ]; then

  permanent_rules append

  # because more narrow rules is added above
  temporary_rules delete

elif [ "$script_type" = "down" -a "$script_context" = "init" ]; then

  # restore temporary rules ("more narrow" rules will be removed below)
  temporary_rules append

  permanent_rules delete

fi
