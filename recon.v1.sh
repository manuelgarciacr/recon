#!/usr/bin/env bash

# Definir la limpieza al salir (EXIT) o recibir señales de interrupción (INT, TERM)
trap 'exec 6>&-; exec 7>&-' EXIT INT TERM

usage() {
    cat <<EOF
Usage: $0 <folder> [options]

<folder>: Folder with the results. It cannot start with a hyphen.

options:
  --domain DOMAIN, -d    Domain
  --help, -h             Show command line options
  --only-active, -a      Run only active scans
  --only-passive, -s     Run only passive scans (silent)
  --verbose, -v			 Verbose

Examples:
  $0 example -d example.com -r 10.3.3.0/24
  $0 example --domain example.com --range 10.3.3.1-10.3.3.245
EOF
}
#  -r, --range RANGE      IP Range

DOMAIN=""
RANGE=""
ONLY_ACTIVE=0;
ONLY_PASSIVE=0;
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
###	-o d:r:h \
###	--long domain:,range:,help \
ARGS=$(LC_ALL=C getopt \
	--long domain:,help,only-active,only-passive,verbose \
	-o d:hasv \
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
		    --domain|-d)
		        DOMAIN="$2"
		        shift
		        ;;
		    --help|-h)
		        usage
		        exit 0
		        ;;
		    --only-active|-a)
				ONLY_ACTIVE=1
				;;
			--only-passive|-s)
				ONLY_PASSIVE=1
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
}

create_folder() {
    local base="$FOLDER"
    local i=1
    # Intenta crear la carpeta. Si falla (existe), entra al bucle.
    # 2>/dev/null silencia el error de mkdir para no ensuciar la salida.
    while ! mkdir "$FOLDER" 2>/dev/null; do
    	local num="000${i}"
    	FOLDER="${base}_${num: -3}"
        ((i++))
        
        # Seguridad: evitar bucle infinito (opcional)
        if [ $i -gt 999 ]; then
            echo "No se pudo crear una carpeta única." >&2
            return 1
        fi
    done
    if [[ "$base" != "$FOLDER" ]]; then
    	echo
    	echo "New folder: $FOLDER"
    	echo
    fi
}

gap() {
	sleep 2
	echo -e "\n$1 ...\n" | tee -a $FOLDER/recon.log
}

recon() {
	create_folder

	if [ "$VERBOSE" -eq 1 ]; then
	    exec 6> >(stdbuf -oL tee -a "$FOLDER/recon.log")
	    exec 7> >(stdbuf -oL tee -a "$FOLDER/recon.log")
 	else
	    exec 6>> "$FOLDER/recon.log"
	    exec 7> >(stdbuf -oL tee -a "$FOLDER/recon.log")
	fi
		
	echo -e "PID: $$" | tee -a $FOLDER/recon.log
	gap "fierce"
	fierce >&6 2>&7
	gap "dnsrecon"
 	dnsrecon >&6 2>&7
	recon_ng 
	gap "outputs"
	sort -t'|' -k1,4 -u $FOLDER/recon.csv > $FOLDER/recon-unique.csv
	awk -F'|' 'BEGIN{OFS="|"} {temp=$1; $1=$2; $2=temp; print}' $FOLDER/recon.csv | grep -Ev '^[|]' | sort -t'|' -k1,4 -u > $FOLDER/recon-ip.csv
	sort -t'|' -k1,1 -u $FOLDER/recon-ip.csv | grep -E '^[|]' > $FOLDER/recon-ip-unique.csv  ### | grep -E '^[^|]*\|[^|]+'
	
	if [ "$VERBOSE" -eq 1 ]; then 
		cat $FOLDER/recon-ng.csv && echo -e "\n#...$(wc -l $FOLDER/recon-ng.csv)"
		echo
		cat $FOLDER/recon.csv && echo -e "\n#...$(wc -l $FOLDER/recon.csv)"
		echo
		cat $FOLDER/recon-unique.csv && echo -e "\n#...$(wc -l $FOLDER/recon-unique.csv)"
		echo
		cat $FOLDER/recon-ip.csv && echo -e "\n#...$(wc -l $FOLDER/recon-ip.csv)"
		echo
		cat $FOLDER/recon-ip-unique.csv && echo -e "\n#...$(wc -l $FOLDER/recon-ip-unique.csv)"
	else
		echo "#...$(wc -l $FOLDER/fierce.txt)"
		echo "#...$(wc -l $FOLDER/dnsrecon.txt)"
		echo "#...$(wc -l $FOLDER/recon-ng.csv)"
		echo "#...$(wc -l $FOLDER/recon.csv)"
		echo "#...$(wc -l $FOLDER/recon-unique.csv)"
		echo "#...$(wc -l $FOLDER/recon-ip.csv)"
		echo "#...$(wc -l $FOLDER/recon-ip-unique.csv)"
	fi
}

fierce() {
	if [ "$ONLY_PASSIVE" -eq "1" ]; then return; fi
	
	command fierce --domain $DOMAIN > $FOLDER/fierce.txt
	grep -i found $FOLDER/fierce.txt|cut -d " " -f 2,3|sed 's/. (/|/; s/)/|||fierce/' >> $FOLDER/recon.csv
	
	if [ "$VERBOSE" -eq 1 ]; then 
		cat $FOLDER/fierce.txt && echo -e "\n#...$(wc -l $FOLDER/fierce.txt)"
	fi
}

dnsrecon() {
	if [ "$ONLY_PASSIVE" -eq "1" ]; then return; fi
	
	command dnsrecon -c $FOLDER/dnsrecon.txt -d $DOMAIN
	cat $FOLDER/dnsrecon.txt | cut -d "," -f 2,3,4,5,6 | grep -E '^SOA,|^NS,|^MX,|^A,|^AAAA,' | cut -d "," -f 2,3 --output-delimiter "|" | sed 's/$/|||dnsrecon/' | sort -u >> $FOLDER/recon.csv
	cat $FOLDER/dnsrecon.txt | cut -d "," -f 2,3,4,5,6 | grep -E '^SRV,' | awk -F',' -v OFS='|' '{print $4, $3, $5, $2, "dnsrecon"}' | sort -u >> $FOLDER/recon.csv
	
	echo
	if [ "$VERBOSE" -eq 1 ]; then 
		cat $FOLDER/dnsrecon.txt && echo -e "\n#...$(wc -l $FOLDER/dnsrecon.txt)"
	fi
}

recon_ng() {
	gap "recon_ng_certificate_transparency"
	recon_ng_certificate_transparency >&6 2>&7
	gap "recon_ng_hackertarget"
	recon_ng_hackertarget >&6 2>&7
	gap "recon_ng_brute_hosts"
	recon_ng_brute_hosts >&6 2>&7
	gap "recon_ng_reporting_csv"
	recon_ng_reporting_csv  >&6 2>&7
}

recon_ng_certificate_transparency() {
	if [ "$ONLY_ACTIVE" -eq "1" ]; then return; fi

	recon-cli -w $FOLDER -C "options set TIMEOUT 30" -C "marketplace install recon/domains-hosts/certificate_transparency" -m recon/domains-hosts/certificate_transparency -o SOURCE=$DOMAIN -x
}

recon_ng_hackertarget() {
	if [ "$ONLY_ACTIVE" -eq "1" ]; then return; fi
	
	recon-cli -w $FOLDER -C "marketplace install recon/domains-hosts/hackertarget" -m recon/domains-hosts/hackertarget -o SOURCE=$DOMAIN -x
}

recon_ng_brute_hosts() {
	if [ "$ONLY_PASSIVE" -eq "1" ]; then return; fi
	
	recon-cli -w $FOLDER -C "marketplace install recon/domains-hosts/brute_hosts" -m recon/domains-hosts/brute_hosts -o SOURCE=$DOMAIN -x
}

recon_ng_reporting_csv() {
	recon-cli -w $FOLDER -C "marketplace install reporting/csv" -m reporting/csv -o FILENAME=$(realpath $FOLDER)/recon-ng.csv -o TABLE=hosts -x
	cat $FOLDER/recon-ng.csv | sed 's/^"//; s/".$//; s/","/|/g; s/\(.*\)|/\1|recon-ng /; s/|||//' >> $FOLDER/recon.csv
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

while getopts ":d:r:h" opt; do
    case "$opt" in
        d)
            DOMAIN="$OPTARG"
            ;;
        r)
            RANGE="$OPTARG"
            ;;
        h)
            usage
            ;;
        :)
            echo "Error: la opción -$OPTARG requiere un argumento."
            usage
            ;;
        \?)
            echo "Error: opción desconocida: -$OPTARG"
            usage
            ;;
    esac
done

shift $((OPTIND - 1))

# Validación
if [[ -z "$DOMAIN" ]]; then
    echo "Error: falta -d domain.com"
    usage
fi

if [[ -z "$RANGE" ]]; then
    echo "Error: falta -r RANGE"
    usage
fi

echo "Dominio : $DOMAIN"
echo "Rango   : $RANGE"

# --------------------------------------------------
# Procesamiento según el rango recibido
# --------------------------------------------------

if [[ "$RANGE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then

    echo "Tipo de rango: CIDR"

    # Proceso para CIDR
    proceso_cidr() {
        echo "Ejecutando proceso CIDR sobre $RANGE"
        # Aquí tu comando
    }

    proceso_cidr

elif [[ "$RANGE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

    echo "Tipo de rango: inicio-fin"

    # Proceso para rango
    proceso_range() {
        echo "Ejecutando proceso sobre $RANGE"
        # Aquí tu comando
    }

    proceso_range

else

    echo "Error: formato de rango no reconocido: $RANGE"
    echo "Ejemplos válidos:"
    echo "  10.3.3.0/24"
    echo "  10.3.3.1-10.3.3.245"
    exit 1

fi
