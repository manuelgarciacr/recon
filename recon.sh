#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

set -o nounset
shopt -s lastpipe

# Definir la limpieza al salir (EXIT) o recibir señales de interrupción (INT, TERM)
trap 'rm -f "$tmp"' EXIT INT TERM
tmp=$(mktemp)

usage() {
    cat <<EOF
Usage: $0 [options] <workspace>

<workspace>: Workspace name for recon-ng and folder with the results. It cannot 
    start with a hyphen.
If no domain and no IPs are provided, scans the current network.

options:
  --active-recon-mode, -a   Run active host discovery modules
  --clean-workspace         Remove data from previous runs if any.
  --domain DOMAIN, -d       Domain. If defined, perimeter domain searches are
                                performed.
  --help, -h                Show command line options.
  --log, -l                 Log file. By default 'recon.log'.
  --modules, -m             Modules to use: 'dnsdumpster, theharvester, 
                                fierce, dnsrecon, rn_certificate_transparency, 
                                rn_hackertarget, rn_brute_hosts'. If none is 
                                declared, all modules can be used.
  --noisy-scan-mode, -n     Runs active port scans in noisy mode. (see --stealth-scan-mode)
  --range, -r               IP range as comma separated values, CIDR or first-
                                last ip. If IPs are found or defined,
                                port scanners will proceed.
  --reuse_workspace         Reuse data from previous runs if any. The folder
                                and the workspace must exist.
  --stealth-scan-mode, -s   Runs active port scans in stealth mode. (see --noisy-scan-mode)
  --verbose, -v             Verbose.

Examples:
  $0 -d example.com -m fierce,rn_hackertarget myworkspace 
  # Workspace myworkspace, domain example.com, uses only the module 
      rn_hackertarget because fierce is considered active and needs 
      the --active flag
  $0 --domain example.com myworkspace --reuse_workspace
  # Domain example.com, workspace myworkspace, reuse data from previous runs
EOF
}

declare -A MODULES=( ["dnsdumpster"]=1 ["theharvester"]=1 ["fierce"]=1 ["dnsrecon"]=1 ["rn_certificate_transparency"]=1 \
	["rn_hackertarget"]=1 ["rn_brute_hosts"]=1 )
declare -A MODULES_TYPE=( ["dnsdumpster"]=0 ["theharvester"]=0 ["fierce"]=1 ["dnsrecon"]=1 ["rn_certificate_transparency"]=0 \
	["rn_hackertarget"]=0 ["rn_brute_hosts"]=1 ) # 1 active, 0 passive

ACTIVE_RECON_MODE=0;
CLEAN_WORKSPACE=0;
DOMAIN="";
DOTOOL="xdotool"
FOLDER="";
LOG="recon.log";
LOGEXISTS=0
MODULES_PARM="";
NOISY_SCAN_MODE=0;
RECON_NG=0;
REUSE_WORKSPACE=0;
STEALTH_SCAN_MODE=0;
TEST="";
VERBOSE=0;

ARGS=$(LC_ALL=C getopt \
	--long active-recon-mode,clean-workspace,domain:,help,log:,modules:,noisy-scan-mode,range,reuse-workspace,stealth-scan-mode,verbose \
	-o ad:hl:m:nr:sv \
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

	if [[ -n $DOMAIN ]]; then
		recon
	else
		internalRecon
	fi
	portsScan
	servicesScan
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
		    --active-recon-mode|-a)
				ACTIVE_RECON_MODE=1
				;;
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
			--noisy-scan-mode)
				NOISY_SCAN_MODE=1
				;;
			--reuse-workspace)
				REUSE_WORKSPACE=1
				;;
			--stealth-scan-mode)
				STEALTH_SCAN_MODE=1
				;;
			--verbose|-v)
				VERBOSE=1
				;;
		    --)
		        shift
		    	if [ "$#" -eq 0 ]; then
					error 13 # Missing <workspace> argument
		    	fi
		    	if [ "$#" -eq 1 ]; then # workspace argument exists. OK
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

	# if [ "$ACTIVE_RECON_MODE$ONLY_PASSIVE" -eq "11" ]; then
	# 	error 6 # The --active-recon-mode and --only-passive options are not compatible with each other
	# fi

	# if [[ -z "$DOMAIN" ]]; then
	# 	error 7 # The domain name cannot be empty
	# fi

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

	if [[ $ACTIVE_RECON_MODE -eq 0 ]]; then
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

	if [ "$STEALTH_SCAN_MODE$NOISY_SCAN_MODE" -eq "11" ]; then
		error 14 # The --stealth-scan-mode and --noisy-scan-mode options are not compatible with each other
	fi
}

validate_folder() {
	
    if [ -z "$FOLDER" ]; then
        error 20 # The workspace cannot be empty
    fi

    if [[ ! "$FOLDER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error 21 # The workspace can only contain letters, numbers, '_' and '-'
    fi

    if [[ "$FOLDER" =~ ^[-.] ]]; then
        error 22 # The workspace should not start with '-'
    fi

	if [[ -z "$LOG" || "$LOG" == "." || "$LOG" == ".." || "$LOG" == */* ]]; then
    	error 23 "$LOG" # Invalid log file name
	fi

	LOG="$FOLDER/$LOG"
}

environment() {
	local log=$(echo -e "\n$(date '+%Y-%m-%d %H:%M:%S')\nPID: $$\n")
	> "$tmp"

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
	#_noerror && ! [[ -f "$LOG" ]] && log+=$(> "$LOG" 2>"$tmp")
	_noerror && [[ -f $FOLDER/recon.csv ]] && log+=$(rm "$FOLDER/recon.csv" 2>"$tmp")
	_noerror && [[ -f $FOLDER/hosts-ips.csv ]] && log+=$(rm "$FOLDER/hosts-ips.csv" 2>"$tmp")
	_noerror && [[ -f $FOLDER/hosts.csv ]] && log+=$(rm "$FOLDER/hosts.csv" 2>"$tmp")
	_noerror && [[ -f $FOLDER/ips.csv ]] && log+=$(rm "$FOLDER/ips.csv" 2>"$tmp")
	_noerror && [[ -f $FOLDER/ips-ports.csv ]] && log+=$(rm "$FOLDER/ips-ports.csv" 2>"$tmp")
	_noerror && [[ -f $FOLDER/services.csv ]] && log+=$(rm "$FOLDER/services.csv" 2>"$tmp")
	_noerror && [[ -f $FOLDER/fierce-nearby.csv ]] && log+=$(rm "$FOLDER/fierce-nearby.csv" 2>"$tmp")

	echo "$log"
	! _noerror && error 24 "$(cat $tmp)" # Can not actualize the environment

	LOGEXISTS=1

	echo "$log" | toLog -q
}

recon() {

	dnsdumpster
	#theharvester
	fierce
 	dnsrecon
	recon_ng 

	gap "outputs"

	echo

	[[ -f $FOLDER/recon.csv ]] && echo "#...$(wc -l $FOLDER/recon.csv)" 2>&1 | toLog
	[[ -f $FOLDER/hosts-ips.csv ]] && echo "#...$(wc -l $FOLDER/hosts-ips.csv)" 2>&1 | toLog
	[[ -f $FOLDER/hosts.csv ]] && echo "#...$(cat "$FOLDER/hosts.csv" | tr ',' '\n' | grep -c '') $FOLDER/hosts.csv" 2>&1 | toLog
	[[ -f $FOLDER/ips.csv ]] && echo "#...$(cat "$FOLDER/ips.csv" | tr ',' '\n' | grep -c '') $FOLDER/ips.csv" 2>&1 | toLog
	[[ -f $FOLDER/fierce-nearby.csv ]] && echo "#...$(wc -l $FOLDER/fierce-nearby.csv)" 2>&1 | toLog
}

dnsdumpster() { # Passive
	local file="$FOLDER/DATA/dnsdumpster.json"
	local key=$(sqlite3 ~/.recon-ng/keys.db "SELECT value FROM keys WHERE name='dnsdumpster_api'")
	local cmd=(curl -H "X-API-Key: $key" "https://api.dnsdumpster.com/domain/$DOMAIN")

	[[ ${MODULES["dnsdumpster"]} -eq 0 ]] && return
	
	gap "dnsdumpster"

	> "$tmp"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		command "${cmd[@]}" > "$file" 2>"$tmp"
		#{
  		#	"error": "Invalid domain"
		#}
		local date=""
	else
		local date=$(stat -c '%w' "$file" | cut -c1-16)
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	local lines=$(parseJSON.sh --parseDNSDumpster --no-header --no-quotes "$file")
	local output=$(echo "$lines" | grep -Ev '^txt\|' |
		awk -F'|' -v OFS='|' '{
			if ($7 == "https") 		 $7 = "443"
    		else if ($7 == "http")   $7 = "80"
    		else if ($7 == "ftp")    $7 = "21"
    		else if ($7 == "ssh")    $7 = "22"
    		else if ($7 == "telnet") $7 = "23"
			print tolower($1), $2, $3, $7, $11, "dnsdumpster"
			}')
	local output2=$(echo "$lines" | grep -E '^txt\|' |
		awk -F'|' -v OFS='|' '{print tolower($1), $2, $3, $7, $12, "dnsdumpster"}')

	[[ -n $output && -n $output2 ]] && output+=$'\n'"$output2" || output+="$output2"

	echo "$output" >> $FOLDER/recon.csv

	# echo "$output" | awk -F'|' -v OFS='|' '{print $3, $2, $4, $6}' | 
	# 	grep -v "^||" >> $FOLDER/hosts-ips.csv

	depure_output

	# TODO: Count the number of effective records
	date=$(red $(echo "$date"))
	echo -e "\n#...$(wc -l <<< "$lines") $file $date" 2>&1 | toLog
	cat "$tmp" | toLog
}

theharvester() { # Passive
	local file="$FOLDER/DATA/theharvester.json"
	local key=$(sqlite3 ~/.recon-ng/keys.db "SELECT value FROM keys WHERE name='dnsdumpster_api'")

	[[ ${MODULES["theharvester"]} -eq 0 ]] && return
	
	gap "theharvester"

	> "$tmp"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		command theHarvester -d $DOMAIN -b crtsh,securityTrails,virustotal,dnsdumpster,duckduckgo,yahoo,brave -l 1000 -f "$file" 2>"$tmp"
		local output=$?
		#{
  		#	"error": "Invalid domain"
		#}
		local date=""
	else
		local date=$(stat -c '%w' "$file" | cut -c1-16)
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	local lines=$(cat "$file" | jq '.')

	depure_output

	# TODO: Count the number of effective records
	date=$(red $(echo "$date"))
	echo -e "\n#...$(wc -l <<< "$lines") $file $date" 2>&1 | toLog
	cat "$tmp" | toLog
}

fierce() { # Active
	local file="$FOLDER/DATA/fierce.txt"

	[[ ${MODULES["fierce"]} -eq 0 ]] && return
	
	gap "fierce"

	> "$tmp"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		command fierce --domain $DOMAIN > "$file" 2>"$tmp"
		local date=""
	else
		local date=$(stat -c '%w' "$file" | cut -c1-16)
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	local lines=$(grep -E "^SOA:|^Found:" "$file")

	echo "$lines" | sed -E \
		-e 's/^Found: ([^ ]+) \(([^)]+)\)/|\1|\2/' \
		-e 's/^SOA: ([^ ]+) \(([^)]+)\)/soa|\1|\2/' |
		sed -e 's/\.$//' | sed -e 's/$/|||fierce/' | sed 's/\.|/|/g' >> $FOLDER/recon.csv

	# echo "$lines" | sed -E \
	# 	-e 's/^Found: ([^ ]+) \(([^)]+)\)/\2|\1/' \
	# 	-e 's/^SOA: ([^ ]+) \(([^)]+)\)/\2|\1/' |
	# 	sed -e 's/\.$//' | sed -e 's/$/||fierce/' >> $FOLDER/hosts-ips.csv
	
	grep -E "^[[:space:]]*\{?'[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+':" "$file" |
		sed -E -e "s/^[[:space:]]*\{?'([^']+)': '([^']+)'.*/\1|\2/" |
		sed 's/\.$//' > $FOLDER/fierce-nearby.csv

	depure_output

	date=$(red $(echo "$date"))
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

	> "$tmp"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		command dnsrecon -c $file -d $DOMAIN $v 2>"$tmp"
		local date=""
	else
		local date=$(stat -c '%w' "$file" | cut -c1-16)
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	local lines=$(grep -Ev "^Domain," "$file" | 
		cut -d "," -f 2,3,4,5,6,7 --output-delimiter='|')

	local output=$(
		echo "$lines" | grep -Ev '^SRV\||^TXT\|' | 
			#sed 's/$/dnsrecon/';
			awk -F'|' -v OFS='|' '{print tolower($1), $2, $3, $4, $5, "dnsrecon"}';
		echo "$lines" | grep -E '^SRV\|' |
			awk -F'|' -v OFS='|' '{print tolower($1), $4, $3, $5, $2, "dnsrecon"}';
		echo "$lines" | grep -E '^TXT\|' |
			awk -F'|' -v OFS='|' '{print tolower($1), $4, $3, $5, $6, "dnsrecon"}' | 
			sed "s/|'/|/" | sed "s/'|/|/")
	echo "$output" >> $FOLDER/recon.csv

	# echo "$output" | awk -F'|' -v OFS='|' '{print $3, $2, $4, $6}' | 
	# 	grep -v "^||" >> $FOLDER/hosts-ips.csv

	depure_output

	date=$(red $(echo "$date"))
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

	> "$tmp"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		local date=""
		recon-cli -w $FOLDER -C "options set TIMEOUT 30" -C "marketplace install recon/domains-hosts/${module}" -m recon/domains-hosts/${module} -o SOURCE=$DOMAIN -x 2>"$tmp" | toLog -q
		recon-cli -w $FOLDER -C "marketplace install recon/hosts-hosts/resolve" -m recon/hosts-hosts/resolve -x 2>"$tmp" | toLog -q
		recon_ng_report "$table" "$module" "$file"
	else
		local date=$(stat -c '%w' "$file" | cut -c1-16)
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	recon_ng_populate_hosts "$file"

	#local cnt=$(recon-cli -w $FOLDER -C "db query SELECT COUNT(*) FROM hosts WHERE module='certificate_transparency'" 2>/dev/null | grep "^  | " | grep -oP '\d+')
	#echo -e "\n#...${cnt} recon-ng certificate_transparency"
	date=$(red $(echo "$date"))
	echo -e "\n#...$(wc -l $file) $date" 2>&1 | toLog
	cat "$tmp" | toLog
}

recon_ng_report() {
	local table="$1"
	local module="$2"
	local file=$(realpath "$3")
	local output=""
	> "$tmp"

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
	
	cat "$file" | awk -F'|' -v OFS='|' '{print "", $1, $2, "", "", $8}' >>"$FOLDER/recon.csv" 2>"$tmp"
	#cat "$file" | awk -F'|' -v OFS='|' '{print $2, $1, "", $8}' >>"$FOLDER/hosts-ips.csv" 2>"$tmp"

	depure_output

	cat "$tmp" | toLog
}

depure_output()  {
	local type host ip port misc origen
	local newRecon newHostIp newIp newHost
	local sorted

	while IFS='|' read -r type host ip port misc origen; do
		local key="$type|$host|$ip|$port|$misc"
		if [[ -n "$host|$ip|$port|$misc" && "${newRecon:-}" != *"$key"* ]]; then
			newRecon+="$type|$host|$ip|$port|$misc|$origen"$'\n'
		fi
	done < $FOLDER/recon.csv

	newRecon="${newRecon%$'\n'}"
	sorted=$(echo "${newRecon:-}" | sort -t'|' -k1,5 -u)
	echo "$sorted" > $FOLDER/recon.csv

	while IFS='|' read -r type host ip port misc origen; do
		local key="$host|$ip|$port|"
		if [[ -n "$port" && "${newHostIp:-}" != *"$key"* ]]; then
			newHostIp+="$host|$ip|$port|$origen"$'\n'
		fi
		[[ -n "$host"  && "${newHost:-}" != *"$host"*  ]] && newHost+="$host"$'\n'
		[[ -n "$ip"  && "${newIp:-}" != *"$ip"* ]] && newIp+="$ip"$'\n'
	done < $FOLDER/recon.csv
	
	newHost="${newHost%$'\n'}"
	sorted=$(echo "${newHost:-}" | sort -k1,1 -u | tr '\n' ',' | sed 's/,$//')
	echo "$sorted" > $FOLDER/hosts.csv

	newIp="${newIp%$'\n'}"
	sorted=$(echo "${newIp:-}" | sort -k1,1 -u | tr '\n' ',' | sed 's/,$//')
	echo "$sorted" > $FOLDER/ips.csv

	while IFS='|' read -r type host ip port misc origen; do
		if [[ -z "$port" ]]; then
			local key="$host|$ip|"
			if [[ "${newHostIp:-}" != *"$key"* ]]; then
				newHostIp+="$host|$ip||$origen"$'\n'
			fi
		fi
	done < $FOLDER/recon.csv

	newHostIp="${newHostIp%$'\n'}"   
	sorted=$(echo "${newHostIp:-}" | sort -t'|' -k1,3 -u)
	echo "$sorted" > $FOLDER/hosts-ips.csv
}

internalRecon() {
	local file="$FOLDER/DATA/internalRecon.csv"

	gap "internalRecon"

	> "$tmp"

	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		command ip neigh show > "$file" 2>"$tmp"
		if [[ $STEALTH_SCAN_MODE -eq 1 ||  $NOISY_SCAN_MODE -eq 1 ]]; then
			command sudo arp-scan -i 200 -r 1 -R -q -x -A 0102030405060708 --localnet >> "$file" 2>"$tmp"
		fi
		local date=""
	else
		local date=$(stat -c '%w' "$file" | cut -c1-16)
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	cat "$file" | awk '{print $1}' | sort -k1,1 -u | tr '\n' ',' | sed 's/,$//' >> $FOLDER/ips.csv

	date=$(red $(echo "$date"))
	echo -e "\n#...$(wc -l < "$file") $file $date" 2>&1 | toLog
	cat "$tmp" | toLog
}

portsScan() {
	local file="$FOLDER/DATA/portsScan.csv"

	gap "portsScan"

	> "$tmp"
	
	local hosts=$(cat "$FOLDER/ips.csv")

	[[ -z $hosts ]] && error 25 # ips.csv' is empty
	
	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		command sudo masscan 10.0.2.2,10.0.2.3 \
  			-p1-1024 \
  			--rate 50 \
  			--source-port 53 \
  			--randomize-hosts \
  			--retries 1 \
  			--open \
  			-oL "$file"
			--banners 
			 2>"$tmp"
		#TODO: --adapter-ip spofed IP if local network
		#TODO: $STEALTH_SCAN_MODE and $NOISY_SCAN_MODE
		local date=""
	else
		local date=$(stat -c '%w' "$file" | cut -c1-16)
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	local lines=$(cat "$file" | grep "^open")
	echo "$lines" | awk '{print $4 ":" $3}' | sort -k1,1 -u | tr '\n' ',' | sed 's/,$//' >> $FOLDER/ips-ports.csv

	date=$(red $(echo "$date"))
	echo -e "\n#...$(echo "$lines" | wc -l) $file $date" 2>&1 | toLog
	cat "$tmp" | toLog
}

servicesScan() {
	local file="$FOLDER/DATA/servicesScan.csv"

	gap "servicesScan"

	> "$tmp"
	
	local hosts=$(cat "$FOLDER/ips-ports.csv")

	[[ -z $hosts ]] && error 26 # ips-ports.csv' is empty
	
	if [[ ! -f $file || $REUSE_WORKSPACE -eq 0 ]]; then
		local socket=""
	
		while IFS= read -r socket; do
    		local ip="${socket%%:*}"
			local port="${socket##*:}"
			command sudo nmap -sV -Pn \
  				--source-port 53 \
  				-f \
  				--data-length 64 \
  				--scan-delay 2s \
  				--max-rate 5 \
  				-T0 \
				--append-output \
  				-p"$port" "$ip" \
  				-oX "$file" 2>"$tmp"
			#local cnt=$(echo "$output" | xmllint --xpath 'count(//host)' -)
		done < <(echo "$hosts" | tr ',' '\n')   
	
		#TODO: --adapter-ip spofed IP if local network
		#TODO: $STEALTH_SCAN_MODE and $NOISY_SCAN_MODE
		local date=""
	else
		local date=$(stat -c '%w' "$file" | cut -c1-16)
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | toLog
		return
	fi

	local xmlArray=()
	local xml=""
	local line=""

	while IFS= read -r line; do
		local eol=$(echo "$line" | grep -E "<?xml version=")
		if [[ -n $eol && -n $xml ]]; then
			xmlArray+=("$xml")
			xml=""
		fi
		xml+="$line"
	done < "$file"

	[[ -n $xml ]] && xmlArray+=("$xml")

	local lines=""

	for xml in "${xmlArray[@]}"; do
		local cntIps=$(echo "$xml" | xmllint --xpath 'count(//host)' -)
		local i
		for i in $(seq 1 $cntIps); do
			local ip=$(echo "$xml" | xmllint --xpath "string(//host[$i]/address/@addr)" -)
			local cntPorts=$(echo "$xml" | xmllint --xpath "count(//host[$i]/ports/port)" -)
			local j
			for j in $(seq 1 $cntPorts); do
				local port=$(echo "$xml" | xmllint --xpath "string(//host[$i]/ports/port[$j]/@portid)" -)
				#/port[state/@state="open"]/@portid
				local status=$(echo "$xml" | xmllint --xpath "string(//host[$i]/ports/port[$j]/state/@state)" -)
				local service=$(echo "$xml" | xmllint --xpath "string(//host[$i]/ports/port[$j]/service/@name)" -)
				local product=$(echo "$xml" | xmllint --xpath "string(//host[$i]/ports/port[$j]/service/@product)" -)
				local version=$(echo "$xml" | xmllint --xpath "string(//host[$i]/ports/port[$j]/service/@version)" -)
				lines+="$ip|$port|$status|$service|$product|$version"$'\n'
			done
		done
	done

	lines="${lines%$'\n'}"
	echo "$lines" >> $FOLDER/services.csv

	date=$(red $(echo "$date"))
	echo -e "\n#...$(echo "$lines" | wc -l) $file $date" 2>&1 | toLog
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
		#"1")
		#	MSG="Folder name starts with hyphen: '$2'"
		#	;;
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
		# "6")
		# 	MSG="The --active-recon-mode and --only-passive options are not compatible with each other"
		# 	;;
		# "7")
		# 	MSG="The domain name cannot be empty"
		# 	;;
		"8")
			MSG="The --clean-workspace and --reuse-workspace options are not compatible with each other"
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
			MSG="Missing <workspace> argument"
			;;
		"14")
			MSG="The --stealth-scan-mode and --noisy-scan-mode options are not compatible with each other"
			;;
		"20")
			MSG="The workspace cannot be empty"
			;;
		"21")
			MSG="The workspace can only contain letters, numbers, '_' and '-': '$FOLDER'"
			;;
		"22")
			MSG="The workspace should not start with '-': '$FOLDER'"
			;;
		"23")
			MSG="Invalid log file name: '$2'"
			;;
		"24")
			MSG="Can not actualize the environment: '$2'"
			;;
		"25")
			MSG="'$FOLDER/ips.csv' is empty"
			;;
		"26")
			MSG="'$FOLDER/ips-ports.csv' is empty"
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
	echo >> "$LOG"
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
