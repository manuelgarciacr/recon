#!/usr/bin/env bash

set -o nounset
shopt -s lastpipe

# Definir la limpieza al salir (EXIT) o recibir señales de interrupción (INT, TERM)
trap 'rm -f "$tmp"' EXIT INT TERM
tmp=$(mktemp)

usage() {
    cat <<EOF
Usage: $0 [options] <workspace>

<workspace>: Workspace name for recon-ng and folder with the results. It cannot start with a hyphen.

options:
  --clean-workspace      Remove data from previous runs if any.
  --domain DOMAIN, -d    Domain
  --help, -h             Show command line options
  --log, -l              Log file. By default 'recon.log'
  --modules, -m          Modules to use: 'fierce, dnsrecon, rn_certificate_transparency, rn_hackertarget, rn_brute_hosts'. If none are declared, all will be used.
  --only-active, -a      Run only active scans
  --only-passive, -s     Run only passive scans (silent)
  --reuse_workspace      Reuse data from previous runs if any. The folder and the workspace must exist
  --verbose, -v			 Verbose

Examples:
  $0 -d example.com -m fierce,rn_hackertarget --only-passive myworkspace 
  # FWorkspace myworkspace, domain example.com, uses only the module rn_hackertarget because fierce is considered active
  $0 --domain example.com myworkspace --reuse_workspace
  # Domain example.com, workspace myworkspace, reuse data from previous runs
EOF
}
#  -r, --range RANGE      IP Range

declare -A MODULES=( ["fierce"]=1 ["dnsrecon"]=1 ["rn_certificate_transparency"]=1 \
	["rn_hackertarget"]=1 ["rn_brute_hosts"]=1 )
declare -A MODULES_TYPE=( ["fierce"]=1 ["dnsrecon"]=1 ["rn_certificate_transparency"]=0 \
	["rn_hackertarget"]=0 ["rn_brute_hosts"]=1 ) # 1 active, 0 passive

CLEAN_WORKSPACE=0;
DOMAIN="";
DOTOOL="xdotool"
FOLDER="";
LOG="recon.log";
LOGEXISTS=0
MODULES_PARM="";
ONLY_ACTIVE=0;
ONLY_PASSIVE=0;
RECON_NG=0;
REUSE_WORKSPACE=0;
TEST="";
VERBOSE=0;

ARGS=$(LC_ALL=C getopt \
	--long clean-workspace,domain:,help,log:,modules:,only-active,only-passive,reuse-workspace,verbose \
	-o d:hl:m:asv \
	-n "$0" \
	-- "$@" \
	2>"$tmp"
)
OPTERROR=$?

main() {
	testEnv

	if [[ $# -eq 0 ]]; then
		usage
		$DOTOOL type "$0 "
    	[[ -z $TEST ]] && exit 0 || return 0
	fi   

	args
	environment
	recon
}

testEnv() {
	if [[ $OPTERROR -ne 0 ]]; then
		error 2 "$(cat $tmp | sed '1!s/^/❌ /')" # Options error
	fi

	if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then 
		if ! command -v ydotool &> /dev/null; then
			error 3 "ydotool" # ydotool is not installed
		fi
		DOTOOL="ydotool"
		return 
	fi

	if ! command -v xdotool &> /dev/null; then
	    error 3 "xdotool" # xdotool is not installed
	fi
}

args() {
	eval set -- "$ARGS"
	
	while true; do
		case "$1" in
			--clean-workspace)
				CLEAN_WORKSPACE=1
				;;
		    --domain|-d)
		        DOMAIN="$2"
		        shift
		        ;;
		    --help|-h)
		        usage
		        [[ -z $TEST ]] && exit 0 || return 0
		        ;;
			--log|-l)
				LOG="$2"
				shift
				;;
			--modules|-m)
				MODULES_PARM="$2"
				shift
				;;
		    --only-active|-a)
				ONLY_ACTIVE=1
				;;
			--only-passive|-s)
				ONLY_PASSIVE=1
				;;
			--reuse-workspace)
				REUSE_WORKSPACE=1
				;;
			--test--)
				TEST=1
				;;
			--verbose|-v)
				VERBOSE=1
				;;
		    --)
		        shift
		    	if [ "$#" -eq 0 ]; then # FILE argument
					error 13 # Missing <folder> argument
		    	fi
		    	if [ "$#" -eq 1 ]; then # FILE argument exists. OK
					FOLDER="$1"
					validate_folder # At this point, the --log option has already been read
			        break
		    	fi
				shift
		    	error 4 $@ # Unknown arguments: $@
		        ;;
		    *)
		        error 5 $@ # Error processing arguments: '$@'
		        ;;
		esac
		shift
	done

	if [ "$ONLY_ACTIVE$ONLY_PASSIVE" -eq "11" ]; then
		error 6 # The --only-active and --only-passive options are not compatible with each other
	fi

	if [[ -z "$DOMAIN" ]]; then
		error 7 # The domain name cannot be empty
	fi

	if [[ "$CLEAN_WORKSPACE$REUSE_WORKSPACE" -eq "11" ]];then
		error 8 # The --clean-workspace and --reuse_workspace options are not compatible with each other
	fi

	if [[ -n $MODULES_PARM ]]; then
		for key in "${!MODULES[@]}"; do
  			MODULES["$key"]=0
		done

		IFS=',' read -ra array <<< "$MODULES_PARM"

		for module in "${array[@]}"; do
			[[ -v MODULES["$module"] ]] && MODULES["$module"]=1 || error 9 "$module" # Module '$2' does not exist"
		done
	fi

	if [[ $ONLY_ACTIVE -eq 1 ]]; then
		for key in "${!MODULES[@]}"; do
			if [[ MODULES_TYPE["$key"] -eq 0 ]]; then
  				MODULES["$key"]=0
			fi
		done
	fi

	if [[ $ONLY_PASSIVE -eq 1 ]]; then
		for key in "${!MODULES[@]}"; do
			if [[ MODULES_TYPE["$key"] -eq 1 ]]; then
  				MODULES["$key"]=0
			fi
		done
	fi

	local existModule=0
	for key in "${!MODULES[@]}"; do
		[[ ${MODULES[$key]} -eq 1 ]] && existModule=1
		[[ $key == rn_* ]] && RECON_NG=1  
	done

	[[ $existModule -eq 0 ]] && error 10 # No modules selected
}

validate_folder() {
	
    if [ -z "$FOLDER" ]; then
        error 20 # The folder name cannot be empty
    fi

    if [[ ! "$FOLDER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error 21 # The folder name can only contain letters, numbers, '_' and '-'
    fi

    if [[ "$FOLDER" =~ ^[-.] ]]; then
        error 22 # Folder name should not start with '-'
    fi

	if [[ -z "$LOG" || "$LOG" == "." || "$LOG" == ".." || "$LOG" == */* ]]; then
    	error 23 "$LOG" # Invalid log file name
	fi

	LOG="$FOLDER/$LOG"
}

environment() {
	local log=$(echo -e "\n$(date '+%Y-%m-%d %H:%M:%S')\nPID: $$\n")
	touch "$tmp"

	_workspace() {
		[[ -d ~/.recon-ng/workspaces/$FOLDER ]]
	}
	_folder() {
		[[ -d $FOLDER ]]
	}
	_recon_ng() {
		[[ $RECON_NG -eq 1 ]]
	}

	if [[ $CLEAN_WORKSPACE -eq 1 ]]; then
		#_folder && log+=$(rm -rf "$(realpath "$FOLDER")" 2>"$tmp")
		_folder && log+=$(rm -rf "$FOLDER" 2>"$tmp")
	elif _folder && [[ $REUSE_WORKSPACE -eq 0 ]]; then
		echo "$log"
		error 11 # The folder '$FOLDER' already exists
	elif _workspace && _recon_ng && [[ $REUSE_WORKSPACE -eq 0 ]]; then
		echo "$log"
		error 12 # The workspace '$FOLDER' already exists
	fi

	#_noerror && _workspace && _recon_ng && log+=$(rm -f ~/.recon-ng/workspaces/$FOLDER/data.db 2>"$tmp")
	_noerror && _workspace && _recon_ng && log+=$(sqlite3 ~/.recon-ng/workspaces/$FOLDER/data.db \
		"DELETE FROM hosts; DELETE FROM hosts;" 2>"$tmp")
	_noerror && log+=$(mkdir -p "$FOLDER/DATA" 2>"$tmp")
	#_noerror && ! [[ -f "$LOG" ]] && log+=$(touch "$LOG" 2>"$tmp")
	_noerror && [[ -f $FOLDER/recon.csv ]] && log+=$(rm "$FOLDER/recon.csv" 2>"$tmp")
	_noerror && [[ -f $FOLDER/hosts.csv ]] && log+=$(rm "$FOLDER/hosts.csv" 2>"$tmp")
	_noerror && [[ -f $FOLDER/fierce-nearby.csv ]] && log+=$(rm "$FOLDER/fierce-nearby.csv" 2>"$tmp")

	echo "$log"
	! _noerror && error 24 "$(cat $tmp)" # Can not actualize the environment

	LOGEXISTS=1

	echo "$log" | toLog -q
}

recon() {

	fierce
 	dnsrecon
	recon_ng 

	gap "outputs"

	echo
	
	[[ -f $FOLDER/recon.csv ]] && echo "#...$(wc -l $FOLDER/recon.csv)" 2>&1 | toLog
	[[ -f $FOLDER/hosts.csv ]] && echo "#...$(wc -l $FOLDER/hosts.csv)" 2>&1 | toLog
	[[ -f $FOLDER/fierce-nearby.csv ]] && echo "#...$(wc -l $FOLDER/fierce-nearby.csv)" 2>&1 | toLog
}

fierce() { # Active
	local file="$FOLDER/DATA/fierce.txt"

	[[ ${MODULES["fierce"]} -eq 0 ]] && return
	
	gap "fierce"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		command fierce --domain $DOMAIN > "$file" 2>"$tmp"
		local date=""
	else
		local date=$(red $(stat -c '%w' "$file" | cut -c1-16))
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	local lines=$(grep -E "^SOA:|^Found:" "$file")

	echo "$lines" | sed -E \
		-e 's/^Found: ([^ ]+) \(([^)]+)\)/\2|\1/' \
		-e 's/^SOA: ([^ ]+) \(([^)]+)\)/\2|\1/' |
		sed -e 's/\.$//' | sed -e 's/$/||fierce/' >> $FOLDER/hosts.csv
	
	grep -E "^[[:space:]]*\{?'[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+':" "$file" |
		sed -E -e "s/^[[:space:]]*\{?'([^']+)': '([^']+)'.*/\1|\2/" |
		sed 's/\.$//' > $FOLDER/fierce-nearby.csv

	local sorted=$(sort -t'|' -k1,3 -u $FOLDER/hosts.csv)
	echo "$sorted" > $FOLDER/hosts.csv

	echo -e "\n#...$(wc -l <<< "$lines") $file $date" 2>&1 | toLog
	cat "$tmp" | toLog
}

dnsrecon() { # Active
	local file="$FOLDER/DATA/dnsrecon.txt"
	local v=""

	[[ ${MODULES["dnsrecon"]} -eq 0 ]] && return

	if [ "$VERBOSE" -eq 1 ]; then 
		v="-v" 
	fi
	
	gap "dnsrecon"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		command dnsrecon -c $file -d $DOMAIN $v 2>"$tmp"
		local date=""
	else
		local date=$(red $(stat -c '%w' "$file" | cut -c1-16))
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	local lines=$(grep -Ev "^Domain," "$file" | 
		cut -d "," -f 2,3,4,5,6,7 --output-delimiter='|')

	local output=$(echo "$lines" | grep -Ev '^SRV\||^TXT\|' | 
			sed 's/$/dnsrecon/';
		echo "$lines" | grep -E '^SRV\|' |
			awk -F'|' -v OFS='|' '{print $1, $4, $3, $5, $2, "dnsrecon"}';
		echo "$lines" | grep -E '^TXT\|' |
			awk -F'|' -v OFS='|' '{print $1, $4, $3, $5, $6, "dnsrecon"}' | 
			sed "s/|'/|/" | sed "s/'|/|/")
	echo "$output" >> $FOLDER/recon.csv
	
	echo "$output" | awk -F'|' -v OFS='|' '{print $3, $2, $4, $6}' | 
		grep -v "^||" >> $FOLDER/hosts.csv

	local sorted=$(sort -t'|' -k1,5 -u $FOLDER/recon.csv)
	echo "$sorted" > $FOLDER/recon.csv

	local sorted=$(sort -t'|' -k1,3 -u $FOLDER/hosts.csv)
	echo "$sorted" > $FOLDER/hosts.csv

	echo -e "\n#...$(wc -l <<< "$lines") $file $date" 2>&1 | toLog
	cat "$tmp" | toLog
}

recon_ng() {
	recon_ng_run "hosts" "certificate_transparency"
	recon_ng_run "hosts" "hackertarget"
	recon_ng_run "hosts" "brute_hosts"
}

recon_ng_run() {
	local table="$1"
	local module="$2"
	local file="$FOLDER/DATA/rn_${module}.csv"

	[[ ${MODULES["rn_$module"]} -eq 0 ]] && return

	gap "recon_ng_${module}"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		local date=""
		recon-cli -w $FOLDER -C "options set TIMEOUT 30" -C "marketplace install recon/domains-hosts/${module}" -m recon/domains-hosts/${module} -o SOURCE=$DOMAIN -x 2>"$tmp" | toLog -q
		recon-cli -w $FOLDER -C "marketplace install recon/hosts-hosts/resolve" -m recon/hosts-hosts/resolve -x 2>"$tmp" | toLog -q
		recon_ng_report "$table" "$module" "$file"
	else
		local date=$(red $(stat -c '%w' "$file" | cut -c1-16))
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	recon_ng_populate_hosts "$file"

	#local cnt=$(recon-cli -w $FOLDER -C "db query SELECT COUNT(*) FROM hosts WHERE module='certificate_transparency'" 2>/dev/null | grep "^  | " | grep -oP '\d+')
	#echo -e "\n#...${cnt} recon-ng certificate_transparency"
	echo -e "\n#...$(wc -l $file) $date" 2>&1 | toLog
	cat "$tmp" | toLog
}

recon_ng_report() {
	local table="$1"
	local module="$2"
	local file=$(realpath "$3")
	local output=""
	touch "$tmp"

	recon-cli -w $FOLDER -C "marketplace install reporting/csv" -m reporting/csv \
		-o FILENAME="$file" \
		-o TABLE=${table} -x 2>"$tmp" | toLog -q

	_noerror && output=$(cat "$file" | grep "${module}\".$" | 
		sed 's/^"//; s/".$//; s/","/|/g; s/\(.*\)|/\1|recon-ng /')
	_noerror && echo "$output" > "$file" 2>"$tmp"

	cat "$tmp" | toLog
}

recon_ng_populate_hosts() {
	local file="$1"
	
	cat "$file" | awk -F'|' -v OFS='|' '{print $2, $1, "", $8}' >>"$FOLDER/hosts.csv" 2>"$tmp"

	local sorted=$(sort -t'|' -k1,3 -u $FOLDER/hosts.csv)
	echo "$sorted" > $FOLDER/hosts.csv

	cat "$tmp" | toLog
}

gap() {
	sleep 2
	echo -e "\n$1 ..." | toLog
}

confirm() {
    local prompt="${1:-Are you sure?}"
	read -p "$prompt" -n 1 -r response
    case "${response,,}" in
        y) return 0 ;;
        *) return 1 ;;
    esac
}

# $1: Error number
# $2..: Error parameters
error() {
	local CODE=1 # Environment error
	if [[ $1 -ge 50 ]]; then	
		CODE=2
	fi

	case "$1" in
		"1")
			MSG="Folder name starts with hyphen: '$2'"
			;;
		"3")
			MSG="$2 is not installed"
			;;
		"4")
			shift
			MSG="Unknown arguments: '$@'"
			;;
		"5")
			shift
			MSG="Error processing arguments: '$@'"
			;;
		"6")
			MSG="The --only-active and --only-passive options are not compatible with each other"
			;;
		"7")
			MSG="The domain name cannot be empty"
			;;
		"8")
			MSG="The --clean-workspace and --reuse_workspace options are not compatible with each other"
			;;
		"9")
			MSG="Module '$2' does not exist"
			;;
		"10")
			MSG="No modules selected"
			;;
		"11")
			MSG="The folder '$FOLDER' already exists"
			;;
		"12")
			MSG="The workspace '$FOLDER' already exists"
			;;
		"13")
			MSG="Missing <folder> argument"
			;;
		"20")
			MSG="The folder name cannot be empty"
			;;
		"21")
			MSG="The folder name can only contain letters, numbers, '_' and '-': '$FOLDER'"
			;;
		"22")
			MSG="Folder name should not start with '-': '$FOLDER'"
			;;
		"23")
			MSG="Invalid log file name: '$2'"
			;;
		"24")
			MSG="Can not actualize the environment: '$2'"
			;;
		*)
			MSG="$2"
	esac

    echo -e "\a❌ $MSG"

	[[ $LOGEXISTS -eq 1 ]] && echo -e "\a❌ $MSG" >> "$LOG"

	[[ -n $TEST ]] && return $CODE

	exit $CODE
}

_noerror() {
	[[ -z "$(cat $tmp)" ]]
}

toLog() {
	# This pipe only works if it is the last
	local logTxt=$(echo "$LOG" | sed 's/\.log$/\.txt\.log/')
	echo >> "LOG"
    while IFS= read -r linea; do
        [[ "${1:-}" == "-q" ]] && echo "$linea" >> "$LOG" || echo "$linea" | tee -a "$LOG"
		echo "$linea" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' >> "$logTxt"
    done
}

red() {
	echo -e "\e[1;31m$@\e[0m"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
