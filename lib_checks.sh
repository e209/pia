# no need for shebang, the script is intended solely for 'source' use
 
# bash required for specific syntax

# initializing
if test -n "${COUNTRY_EXPECTED=""}"; then

   if test -z "${IP_INFO_URLS-""}"; then
      pr "ERROR: Destination country check is enabled (\$COUNTRY_EXPECTED has value) but \$IP_INFO_URLS is empty or not set."
      switchoff
   fi

   if test -z "${IP_INFO_TARGET_PARAMS-""}"; then
      pr "ERROR: Destination country check is enabled (\$COUNTRY_EXPECTED has value) but \$IP_INFO_TARGET_PARAMS is empty or not set."
      switchoff
   fi

   # load parameters into array
   declare -a req=(${IP_INFO_URLS-""})
   declare -a par=(${IP_INFO_TARGET_PARAMS-""})

   if [ ! ${#req[@]} -eq ${#par[@]} ]; then
      pr "ERROR: Inconsistent number of elements in arrays \$IP_INFO_URLS and \$IP_INFO_TARGET_PARAMS."
      pr ">>> \$IP_INFO_URLS:$IP_INFO_URLS"
      pr ">>> \$IP_INFO_TARGET_PARAMS:$IP_INFO_TARGET_PARAMS"
      switchoff
   fi

fi

function countrycheck
{
# accepts 1 argument:
# "init" means checking all known addresses
# "once" means checking using one randomly selected address
# "triple" means running "once" 3 times; all 3 must fail to report error code
# uses req[], par[], $COUNTRY_EXPECTED global variables and parameters

   if test -z "${COUNTRY_EXPECTED=""}"; then
      #no check
      return 0
   fi

  case $1 in
      init ) # 
	   pr "Finding out the country at the other end of the tunnel..."
	   for i in "${!req[@]}"; do # loop by index (look at ! symbol)

	      cmd="set -o pipefail; curl -sSf ${req[$i]} | jq -r .${par[$i]} 2>/dev/null"
	      cc=$(bash -c "$cmd")

	      # advanced selfcheck (if for an url we get no response then remove it from list)
	      if [[ "$?" != "0" || "$cc" = "null" ]]; then
	         pr "WARNING: From ${req[$i]} got NULL: Probe failed; removing ${req[$i]} and ${par[$i]} from array"
		 unset -v 'req[$i]'
		 unset -v 'par[$i]'
	      else
		 if [ "$cc" = "$COUNTRY_EXPECTED" ]; then
	            pr "From ${req[$i]} got $cc: OK (as expected)"
	            let right=${right:-0}+1
	  	 else
	            pr "From ${req[$i]} got $cc: WRONG! (expected $COUNTRY_EXPECTED)"
                    let wrong=${wrong:-0}+1
	  	 fi
	      fi

	   done

	   pr "Right responces was ${right:=0}, wrong - ${wrong:=0}"

	   if test $right -le $wrong; then
	      pr "Too many incorrect responces, wrong country on the other side of the tunnel suspected, possible VPN malfunctioning."
	      return 2
	   else
	      pr "Test passed."
              return 0
	   fi
          ;;

      once ) # 
	#get random index
	i=$(( $RANDOM % ${#req[@]} )) # remainder of dividing by the number of elements in the array

	cmd="set -o pipefail; curl -sSf ${req[$i]} | jq -r .${par[$i]} 2>/dev/null"
	cc=$(bash -c "$cmd")

	exst=$?
	if [ ! $exst -eq 0 ]; then
	   pr "ERROR: Destination country check (curl command) failed with exit status $exst, probably no connectivity. Command was:"
	   pr ">>> $cmd"
	   return 1	
  	fi

	if [ ! "$cc" = "$COUNTRY_EXPECTED" ]; then
	   pr "ERROR: Destination country check (curl command) got wrong value '$cc' ($COUNTRY_EXPECTED) expected. Probably VPN malfunctioning."
	   return 2
	fi
        ;;

      triple ) # 
	 countrycheck once 
	 if [ ! $? -eq 0 ]; then
	         countrycheck once 
	         if [ ! $? -eq 0 ]; then

		    # and again
		    countrycheck once
		    if [ ! $? -eq 0 ]; then
		      pr "Wrong country on the other side of the tunnel detected, possibly VPN malfunctioning."
	              return 3
		    fi
	         fi
	  fi
        ;;


      * ) #internal error
          pr "ERR: Unexpected parameter '$1' of countrycheck function."
	  # may be no iptables rules yet on the moment
	  xternal_access.sh disable "$LOCAL_NETWORK_IP" "$LOCAL_NETWORK_MASK"
          switchoff
          ;;

   esac
}

function continuous_check
{
	failed_attempts=0
	CC_MAX_FAILED_ATTEMPTS=${CC_MAX_FAILED_ATTEMPTS:-3}
	
	while true; do

	   # long-time sleep in foreground prevents from trapping signals; but wait for background does the job
	   sleep ${COUNTRYCHECK_INTERVAL} &
	   wait ${!}

	   countrycheck	once

	   case $? in
	      1 ) (( failed_attempts=$failed_attempts + 1 ))
	         if [ "$failed_attempts" -gt "$CC_MAX_FAILED_ATTEMPTS" ]; then

	            exit_status=4
	            pr "Max of $CC_MAX_FAILED_ATTEMPTS unsuccesful checks attempted. Possibly no connectivity, container will be restarted. Exiting ($exit_status)."
	            kill 1 # remember restart policy

	         fi
	         ;;
	      2 ) # checking again
	         countrycheck once 
	         if [ ! $? -eq 0 ]; then

		    # and again
		    countrycheck once
		    if [ ! $? -eq 0 ]; then

		      exit_status=3
		      pr "Wrong country on the other side of the tunnel detected, possibly VPN malfunctioning."

	              xternal_access.sh disable "$LOCAL_NETWORK_IP" "$LOCAL_NETWORK_MASK"
	              switchoff
		    fi
	         fi
	         ;;
	      0 ) # test was succesful, clearing attempts counter
	         failed_attempts=0
	         ;;
	      * ) #internal error
	         pr "ERROR: Unexpected return code $? of countrycheck function."

	         xternal_access.sh disable "$LOCAL_NETWORK_IP" "$LOCAL_NETWORK_MASK"
	         switchoff
	         ;;
	   esac

	done

}
