# no need for shebang, the script is intended solely for 'source' use

set +e # necessary for code continuing after curl check failure
set -u # treat unset parameter as error when performing expansion
set -o pipefail #exit code from a pipeline is not normal "last command in the pipeline" but "code of the rightmost command that failed"

function pr
{
  printf '%s\n' "$1" | awk '{ print strftime("%Y-%m-%d %H:%M:%S %Z |"),$0; fflush();}'
}

function cleanup() 
{
  if [ "$1" = "$cmd_expected" ]
    then
	pr "SIGTERM trapped, performing cleanup..."

	bkground_pids=${bkground_pids-""} # checks only for existence (: is omitted) since no need to test for emptiness

	# if the variable contains ever single word other than spaces (it would be a PID)
	if [ -n "$(echo $bkground_pids | cut -d ' ' -f 1)" ]; then

	  pr "Sending SIGTERM to background processes (PIDs) '$bkground_pids' ..."

	  # parameter in 'kill' and 'wait' left without quotes intentionnaly
	  kill $bkground_pids

	  #pr "Waiting for these processes unloading..."
	  #wait $bkground_pids

	fi

	# if $exit_status is empty, the container would be stopped by Ctrl-C (SIGINT=15)
	pr "[entrypoint.sh $@] Container stops with exit status (${exit_status:=143})." # 128+15

	exit $exit_status

    else
	pr "SIGTERM trapped, no cleanup, exiting (143)..."
	exit 143 # 128+15
  fi
}

function wait_forever 
{
          tail -f /dev/null &
	  bkground_pids=$!${bkground_pids:+" $bkground_pids"}
          wait $!
}

trap "cleanup $1" SIGTERM

