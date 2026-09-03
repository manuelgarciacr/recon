#!/usr/bin/env bash

# Definir la limpieza al salir (EXIT) o recibir señales de interrupción (INT, TERM)
trap 'exec 6>&-; exec 7>&-; rm -f "$tmp"' EXIT INT TERM
tmp=$(mktemp)

usage() {
    cat <<EOF
Usage: $0 <folder> [options]

<folder>: Folder with the results. It cannot start with a hyphen.

options:
  --clean-folder         Remove data in the folder. No confirmation
  --domain DOMAIN, -d    Domain
  --help, -h             Show command line options
  --modules, -m          Modules to use: "fierce,dnsrecon,rn_certificate_transparency,rn_hackertarget,rn_brute_hosts"
  --only-active, -a      Run only active scans
  --only-passive, -s     Run only passive scans (silent)
  --overwrite-data       Adds/overwrites the results obtained. No confirmation
  --verbose, -v			 Verbose

Examples:
  $0 exampleFolder -d example.com -m fierce,rn_hackertarget --only-passive 
  # Folder exampleFolder, domain example.com, uses only the module rn_hackertarget
  $0 --domain example.com --overwrite-data exampleFolder
  # Domain example.com, adds/overwrites new results inside the folder, folder exampleFolder
EOF
}
#  -r, --range RANGE      IP Range

CLEAN_FOLDER=0;
DOMAIN="";
MODULES="";
MOD_FIERCE=1
MOD_DNSRECON=1
MOD_RN_CERTIFICATE_TRANSPARENCY=1
MOD_RN_HACKERTARGET=1
MOD_RN_BRUTE_HOSTS=1
ONLY_ACTIVE=0;
ONLY_PASSIVE=0;
OVERWRITE_DATA=0;
VERBOSE=0;
DOTOOL="xdotool"
if [ "$#" -eq 0 ]; then
	usage
	$DOTOOL type "$0 "
    exit 0
else
	FOLDER="$1"
	shift
fi   
ARGS=$(LC_ALL=C getopt \
	--long clean-folder,domain:,help,modules:,only-active,only-passive,overwrite-data,verbose \
	-o d:hm:asv \
	-n "$0" \
	-- "$@" \
	2>&1
)
OPTERROR=$?

main() {
	testEnv # exit 2, 3
	args # exit 0, 1
	recon
}

# error 2: Options error
# error 3: dotool not installed
testEnv() {
	
	validate_folder

	if [ $OPTERROR -ne 0 ]; then
		error 2 $ARG # Options error
	fi

	if [ -n "$WAYLAND_DISPLAY" ]; then 
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

# error 20: The folder name cannot be empty
# error 21: The folder name can only contain letters, numbers, '_' and '-'
# error 22: Folder name should not start with '-'
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
				MODULES="$2"
				shift
				;;
		    --only-active|-a)
				ONLY_ACTIVE=1
				;;
			--only-passive|-s)
				ONLY_PASSIVE=1
				;;
			--overwrite-data)
				OVERWRITE_DATA=1
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
		    	if [[ -z "$@" ]]; then
			        break
		    	fi
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

	if [[ "$CLEAN_FOLDER$OVERWRITE_DATA" -eq "11" ]];then
		error 8
	fi

	if [[ -n $MODULES ]]; then
		MOD_FIERCE=0
		MOD_DNSRECON=0
		MOD_RN_CERTIFICATE_TRANSPARENCY=0
		MOD_RN_HACKERTARGET=0
		MOD_RN_BRUTE_HOSTS=0

		IFS=',' read -ra array <<< "$MODULES"

		for module in "${array[@]}"; do
			case "${module,,}" in
				"fierce")
					MOD_FIERCE=1
					;;
				"dnsrecon")
					MOD_DNSRECON=1
					;;
				"rn_certificate_transparency")
					MOD_RN_CERTIFICATE_TRANSPARENCY=1
					;;
				"rn_hackertarget")
					MOD_RN_HACKERTARGET=1
					;;
				"rn_brute_hosts")
					MOD_RN_BRUTE_HOSTS=1
					;;
				*)
					error 9 "$module"
			esac
		done
	fi
	if [[ $ONLY_ACTIVE -eq 1 ]]; then
		MOD_RN_CERTIFICATE_TRANSPARENCY=0
		MOD_RN_HACKERTARGET=0
	fi
	if [[ $ONLY_PASSIVE -eq 1 ]]; then
		MOD_FIERCE=0
		MOD_DNSRECON=0
		MOD_RN_BRUTE_HOSTS=0
	fi
	(( MOD_FIERCE + MOD_DNSRECON + MOD_RN_CERTIFICATE_TRANSPARENCY + \
		MOD_RN_HACKERTARGET + MOD_RN_BRUTE_HOSTS == 0 )) && error 10
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
	echo -e "\n$(date '+%Y-%m-%d %H:%M:%S')\nPID: $$" | tee -a "$FOLDER/recon.log"


	if [[ -e $FOLDER && $CLEAN_FOLDER -eq 1 ]]; then
		rm -rf "$(realpath "$FOLDER")" >> "$FOLDER/recon.log" 2>"$tmp"
		mkdir -p "$FOLDER" >> "$FOLDER/recon.log" 2>>"$tmp"
	elif [[ -e $FOLDER && $OVERWRITE_DATA -eq 0 ]]; then
		error 11
	elif [[ ! -e $FOLDER ]]; then
		mkdir "$FOLDER" >> "$FOLDER/recon.log" 2>"$tmp"
	fi
	cat "$tmp" | tee -a "$FOLDER/recon.log"

	recon-cli -w $FOLDER -C "db query DELETE FROM domains" -C "db query DELETE FROM hosts" >> "$FOLDER/recon.log" 2>"$tmp"
	[[ -f $FOLDER/recon.csv ]] && rm "$(realpath "$FOLDER")/recon.csv" >> "$FOLDER/recon.log" 2>>"$tmp"
	[[ -f $FOLDER/hosts.csv ]] && rm "$(realpath "$FOLDER")/hosts.csv" >> "$FOLDER/recon.log" 2>>"$tmp"
	[[ -f $FOLDER/fierce-nearby.csv ]] && rm "$(realpath "$FOLDER")/fierce-nearby.csv" >> "$FOLDER/recon.log" 2>>"$tmp"
	cat "$tmp" | tee -a "$FOLDER/recon.log"

	fierce 0 # Param 0 or any: dont search for new data
 	dnsrecon 0
	recon_ng 

	gap "outputs"
	echo
	#sort -t'|' -k1,4 -u $FOLDER/recon.csv > $FOLDER/recon-unique.csv
	#awk -F'|' 'BEGIN{OFS="|"} {temp=$2; $2=$3; $3=temp; print}' $FOLDER/recon.csv | grep -Ev '^[|]' | sort -t'|' -k1,4 -u > $FOLDER/recon-ip.csv
	#sort -t'|' -k2,2 -u $FOLDER/recon-ip.csv > $FOLDER/recon-ip-unique.csv
	
	[[ -f $FOLDER/recon.csv ]] && echo "#...$(wc -l $FOLDER/recon.csv)"
	[[ -f $FOLDER/hosts.csv ]] && echo "#...$(wc -l $FOLDER/hosts.csv)"
	[[ -f $FOLDER/fierce-nearby.csv ]] && echo "#...$(wc -l $FOLDER/fierce-nearby.csv)"
	#echo "#...$(wc -l $FOLDER/recon-unique.csv)"
	#echo "#...$(wc -l $FOLDER/recon-ip.csv)"
	#echo "#...$(wc -l $FOLDER/recon-ip-unique.csv)"
}

fierce() { # Active
	local searchData=${1:-1}
	local file="$FOLDER/fierce.txt"

	[[ $MOD_FIERCE -eq 0 ]] && return
	
	gap "fierce"

	if [[ $searchData -eq 1 ]]; then
		command fierce --domain $DOMAIN > "$file" 2>"$tmp"
	fi
	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist"
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

	echo -e "\n#...$(wc -l <<< "$lines") $file"
	cat "$tmp" | tee -a "$FOLDER/recon.log"
}

dnsrecon() { # Active
	local searchData=${1:-1}
	local file="$FOLDER/dnsrecon.txt"

	[[ $MOD_DNSRECON -eq 0 ]] && return
	if [ "$VERBOSE" -eq 1 ]; then 
		local v="-v" 
	fi
	
	gap "dnsrecon"

	if [[ $searchData -eq 1 ]]; then
		command dnsrecon -c $FOLDER/dnsrecon.txt -d $DOMAIN $v 2>"$tmp"
	fi
	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist"
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

	echo -e "\n#...$(wc -l <<< "$lines") $file"
	cat "$tmp" | tee -a "$FOLDER/recon.log"
}

recon_ng() {
	recon_ng_run "hosts" "certificate_transparency" 0 # Param 0 or any: dont search for new data
	recon_ng_run "hosts" "hackertarget" 0
	recon_ng_run "hosts" "brute_hosts"
}

recon_ng_run() {
	local table="$1"
	local module="$2"
	local searchData=${3:-1}
	local file="$(realpath $FOLDER)/rn_${module}.csv"

	local name="MOD_RN_${module^^}"
	local val="${!name}"
	[[ $val -eq 0 ]] && return

	gap "recon_ng_${module}"
	if [[ $searchData -eq 1 ]]; then
		recon-cli -w $FOLDER -C "options set TIMEOUT 30" -C "marketplace install recon/domains-hosts/${module}" -m recon/domains-hosts/${module} -o SOURCE=$DOMAIN -x >> "$FOLDER/recon.log" 2>"$tmp"
		recon-cli -w $FOLDER -C "marketplace install recon/hosts-hosts/resolve" -m recon/hosts-hosts/resolve -x >> "$FOLDER/recon.log" 2>"$tmp"
		recon_ng_report "$table" "$module" "$file"
	fi
	if ! [[ -f $file ]]; then
		echo -e "\n#...$file: does not exist"
		return
	fi

	recon_ng_populate_hosts "$file"

	#local cnt=$(recon-cli -w $FOLDER -C "db query SELECT COUNT(*) FROM hosts WHERE module='certificate_transparency'" 2>/dev/null | grep "^  | " | grep -oP '\d+')
	#echo -e "\n#...${cnt} recon-ng certificate_transparency"
	echo -e "\n#...$(wc -l $file)"
	cat "$tmp" | tee -a "$FOLDER/recon.log"
}

recon_ng_report() {
	local table="$1"
	local module="$2"
	local file="$3"

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
			MSG="The --clean-folder and --overwrite-data options are not compatible with each other"
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

main

exit 0
