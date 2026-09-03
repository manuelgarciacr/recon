#!/usr/bin/env bash

set -o nounset

# Definir la limpieza al salir (EXIT) o recibir señales de interrupción (INT, TERM)
trap 'rm -f "$tmp"' EXIT INT TERM
tmp=$(mktemp)

usage() {
    cat <<EOF
Usage: $0 [options] <folder>

<folder>: Folder with the results. It cannot start with a hyphen.

options:
  --clean-folder         Remove data from previous runs. The folder must exist
  --domain DOMAIN, -d    Domain
  --help, -h             Show command line options
  --modules, -m          Modules to use: 'fierce,dnsrecon,rn_certificate_transparency,rn_hackertarget,rn_brute_hosts'. If none are declared, all will be used.
  --only-active, -a      Run only active scans
  --only-passive, -s     Run only passive scans (silent)
  --reuse-data           Reuse data from previous runs if any. The folder must exist
  --verbose, -v			 Verbose

Examples:
  $0 exampleFolder -d example.com -m fierce,rn_hackertarget --only-passive 
  # Folder exampleFolder, domain example.com, uses only the module rn_hackertarget
  $0 --domain example.com --reuse-data exampleFolder
  # Domain example.com, adds/overwrites new results inside the folder, folder exampleFolder
EOF
}
#  -r, --range RANGE      IP Range

declare -A MODULES=( ["fierce"]=1 ["dnsrecon"]=1 ["rn_certificate_transparency"]=1 \
	["rn_hackertarget"]=1 ["rn_brute_hosts"]=1 )
declare -A MODULES_TYPE=( ["fierce"]=1 ["dnsrecon"]=1 ["rn_certificate_transparency"]=0 \
	["rn_hackertarget"]=0 ["rn_brute_hosts"]=1 ) # 1 active, 0 passive

CLEAN_FOLDER=0;
DOMAIN="";
MODULES_PARM="";
ONLY_ACTIVE=0;
ONLY_PASSIVE=0;
REUSE_DATA=0;
VERBOSE=0;
DOTOOL="xdotool"
ARGS=$(LC_ALL=C getopt \
	--long clean-folder,domain:,help,modules:,only-active,only-passive,reuse-data,verbose \
	-o d:hm:asv \
	-n "$0" \
	-- "$@" \
	2>"$tmp"
)
OPTERROR=$?

main() {
	testEnv # exit 2, 3
	echo "**$ARGS**"
	if [ "$#" -eq 0 ]; then
		usage
		$DOTOOL type "$0 "
    	exit 0
	fi   
	args # exit 0, 1
	recon
}

# error 2: Options error
# error 3: dotool not installed
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

# error 4: Unknown arguments: $@
# error 5: Error processing arguments: '$@'
# error 6: The --only-active and --only-passive options are not compatible with each other
args() {
	eval set -- "$ARGS"
	
	while true; do
		case "$1" in
			--clean-folder)
				CLEAN_FOLDER=1
				;;
		    --domain|-d)
		        DOMAIN="$2"
		        shift
		        ;;
		    --help|-h)
		        usage
		        exit 0
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
			--reuse-data)
				REUSE_DATA=1
				;;
#		    --range|-r)
#		        RANGE="$2"
#		        shift 2
#		        ;;
			--verbose|-v)
				VERBOSE=1
				;;
		    --)
		        shift
		    	if [ "$#" -eq 0 ]; then # FILE argument
			    	echo -e "\a❌ Missing <file> argument"
			    	exit 1
		    	fi
		    	if [ "$#" -eq 1 ]; then # FILE argument exists. OK
					FOLDER="$1"
					validate_folder
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
		error 7
	fi

	if [[ "$CLEAN_FOLDER$REUSE_DATA" -eq "11" ]];then
		error 8
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
	local total=0
	for key in "${!MODULES[@]}"; do
  		total=$(( total + MODULES["$key"] ))
	done
	[[ $total -eq 0 ]] && error 10 # No modules selected
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

    return 0
}

# create_folder() {
#     local base="$FOLDER"
#     local i=0
#     while [[ -e "$FOLDER" ]]; do
# 		((i++))
#         if [ $i -gt 999 ]; then
# 	    	FOLDER="${base}_${i}"
# 		else
#     		local num="000${i}"
#     		FOLDER="${base}_${num: -3}"
#         fi
#     done
#     if [[ "$base" != "$FOLDER" ]]; then
# 		confirm "The folder exists, do you want to use the '$FOLDER' folder?" && \
# 			mkdir "$FOLDER" || exit
# 	else
# 		mkdir "$FOLDER"
# 	fi
# }

gap() {
	sleep 2
	echo -e "\n$1 ..." | tee -a "$FOLDER/recon.log"
}

recon() {
	echo -e "\n$(date '+%Y-%m-%d %H:%M:%S')\nPID: $$\n" | tee -a "$FOLDER/recon.log"

	if [[ -e $FOLDER && $CLEAN_FOLDER -eq 1 ]]; then
		rm -rf "$(realpath "$FOLDER")" >> "$FOLDER/recon.log" 2>"$tmp"
		mkdir -p "$FOLDER" >> "$FOLDER/recon.log" 2>>"$tmp"
		mkdir -p "$FOLDER/DATA" >> "$FOLDER/recon.log" 2>>"$tmp"
	elif [[ -e $FOLDER && $REUSE_DATA -eq 0 ]]; then
		error 11 # The folder '$FOLDER' already exists
	elif [[ ! -e $FOLDER || ! -e "$FOLDER/DATA" ]]; then
		mkdir -p "$FOLDER" >> "$FOLDER/recon.log" 2>"$tmp"
		mkdir -p "$FOLDER/DATA" >> "$FOLDER/recon.log" 2>>"$tmp"
	fi
	cat "$tmp" | tee -a "$FOLDER/recon.log"

	recon-cli -w $FOLDER -C "db query DELETE FROM domains" -C "db query DELETE FROM hosts" >> "$FOLDER/recon.log" 2>"$tmp"
	[[ -f $FOLDER/recon.csv ]] && rm "$(realpath "$FOLDER")/recon.csv" >> "$FOLDER/recon.log" 2>>"$tmp"
	[[ -f $FOLDER/hosts.csv ]] && rm "$(realpath "$FOLDER")/hosts.csv" >> "$FOLDER/recon.log" 2>>"$tmp"
	[[ -f $FOLDER/fierce-nearby.csv ]] && rm "$(realpath "$FOLDER")/fierce-nearby.csv" >> "$FOLDER/recon.log" 2>>"$tmp"
	cat "$tmp" | tee -a "$FOLDER/recon.log"

	fierce
 	dnsrecon
	recon_ng 

	gap "outputs"

	echo
	
	[[ -f $FOLDER/recon.csv ]] && echo "#...$(wc -l $FOLDER/recon.csv)" 2>&1 | tee -a "$FOLDER/recon.log"
	[[ -f $FOLDER/hosts.csv ]] && echo "#...$(wc -l $FOLDER/hosts.csv)" 2>&1 | tee -a "$FOLDER/recon.log"
	[[ -f $FOLDER/fierce-nearby.csv ]] && echo "#...$(wc -l $FOLDER/fierce-nearby.csv)" 2>&1 | tee -a "$FOLDER/recon.log"
}

fierce() { # Active
	local file="$FOLDER/DATA/fierce.txt"

	[[ ${MODULES["fierce"]} -eq 0 ]] && return
	
	gap "fierce"

	if [[ ! -f $file || $REUSE_DATA -eq 0 ]]; then
		command fierce --domain $DOMAIN > "$file" 2>"$tmp"
		local date=""
	else
		local date=$(red $(stat -c '%w' "$file" | cut -c1-16))
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | tee -a "$FOLDER/recon.log"
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

	echo -e "\n#...$(wc -l <<< "$lines") $file $date" 2>&1 | tee -a "$FOLDER/recon.log"
	cat "$tmp" | tee -a "$FOLDER/recon.log"
}

dnsrecon() { # Active
	local file="$FOLDER/DATA/dnsrecon.txt"

	[[ ${MODULES["dnsrecon"]} -eq 0 ]] && return

	if [ "$VERBOSE" -eq 1 ]; then 
		local v="-v" 
	fi
	
	gap "dnsrecon"

	if [[ ! -f $file || $REUSE_DATA -eq 0 ]]; then
		command dnsrecon -c $file -d $DOMAIN $v 2>"$tmp"
		local date=""
	else
		local date=$(red $(stat -c '%w' "$file" | cut -c1-16))
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | tee -a "$FOLDER/recon.log"
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

	echo -e "\n#...$(wc -l <<< "$lines") $file $date" 2>&1 | tee -a "$FOLDER/recon.log"
	cat "$tmp" | tee -a "$FOLDER/recon.log"
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

	if [[ ! -f $file || $REUSE_DATA -eq 0 ]]; then
		recon-cli -w $FOLDER -C "options set TIMEOUT 30" -C "marketplace install recon/domains-hosts/${module}" -m recon/domains-hosts/${module} -o SOURCE=$DOMAIN -x >> "$FOLDER/recon.log" 2>"$tmp"
		recon-cli -w $FOLDER -C "marketplace install recon/hosts-hosts/resolve" -m recon/hosts-hosts/resolve -x >> "$FOLDER/recon.log" 2>"$tmp"
		recon_ng_report "$table" "$module" "$file"
		local date=""
	else
		local date=$(red $(stat -c '%w' "$file" | cut -c1-16))
	fi

	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist" 2>&1 | tee -a "$FOLDER/recon.log"
		return
	fi

	recon_ng_populate_hosts "$file"

	#local cnt=$(recon-cli -w $FOLDER -C "db query SELECT COUNT(*) FROM hosts WHERE module='certificate_transparency'" 2>/dev/null | grep "^  | " | grep -oP '\d+')
	#echo -e "\n#...${cnt} recon-ng certificate_transparency"
	echo -e "\n#...$(wc -l $file) $date" 2>&1 | tee -a "$FOLDER/recon.log"
	cat "$tmp" | tee -a "$FOLDER/recon.log"
}

recon_ng_report() {
	local table="$1"
	local module="$2"
	local file=$(realpath "$3")   

	recon-cli -w $FOLDER -C "marketplace install reporting/csv" -m reporting/csv \
		-o FILENAME="$file" \
		-o TABLE=${table} -x >> "$FOLDER/recon.log" 2>"$tmp"

	local output=$(cat "$file" | grep "${module}\".$" | 
		sed 's/^"//; s/".$//; s/","/|/g; s/\(.*\)|/\1|recon-ng /')
	echo "$output" > "$file" 2>"$tmp"

	cat "$tmp" | tee -a "$FOLDER/recon.log"
}

recon_ng_populate_hosts() {
	local file="$1"
	
	cat "$file" | awk -F'|' -v OFS='|' '{print $2, $1, "", $8}' >>"$FOLDER/hosts.csv" 2>"$tmp"

	local sorted=$(sort -t'|' -k1,3 -u $FOLDER/hosts.csv)
	echo "$sorted" > $FOLDER/hosts.csv

	cat "$tmp" | tee -a "$FOLDER/recon.log"
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
			MSG="The --clean-folder and --reuse-data options are not compatible with each other"
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
		"20")
			MSG="The folder name cannot be empty"
			;;
		"21")
			MSG="The folder name can only contain letters, numbers, '_' and '-': '$FOLDER'"
			;;
		"22")
			MSG="Folder name should not start with '-': '$FOLDER'"
			;;
		*)
			MSG="$2"
	esac

    echo -e "\a❌ $MSG"
	exit $CODE
}

red() {
	echo -e "\e[1;31m$@\e[0m"
}

main "$@"

exit 0
