#!/bin/bash

# Fetch CPS data via SNMP, to tune Zone Protection Profile Thresholds
# Requires net-snmp package (snmpwalk and snmpget)
#
# Reference Doc:
# https://docs.paloaltonetworks.com/best-practices/dos-and-zone-protection-best-practices/dos-and-zone-protection-best-practices/deploy-dos-and-zone-protection-using-best-practices
# https://docs.paloaltonetworks.com/pan-os/11-1/pan-os-admin/zone-protection-and-dos-protection/zone-defense/take-baseline-cps-measurements-for-setting-flood-thresholds/how-to-measure-cps
# https://knowledgebase.paloaltonetworks.com/KCSArticleDetail?id=kA14u000000oM5SCAU&lang=en_US%E2%80%A9
#
# Note from the doc:
# "To gather CPS data over time to help with setting Zone Protection profile thresholds, if you use an SNMP server, you can 
# use your own management tools to poll SNMP MIBs. However, it is important to understand that the CPS measurements in the MIBs 
# show twice the actual CPS value (for example, if the true CPS measurement is 10,000, the MIBs show 20,000 as the value; 
# this happens because the MIBs count the C2S and S2C session segments separately instead of as a single session). 
# You can still see trends from the MIBs and you can divide the CPS values by two to derive the true values. 
# The SNMP MIB OIDs are: PanZoneActiveTcpCps, PanZoneActiveUdpCps, and PanZoneOtherIpCps. 
# Because the firewall only takes measurements and updates the SNMP server every 10 seconds, poll every 10 seconds."
#

# The script gathers data in csv format and stores it on the outdir, a file for each zone is created.
# The file name is equal to the zone name, at each run, the files are truncated.
walkcmd="/usr/bin/snmpwalk"
getcmd="/usr/bin/snmpget"

usage() {
	echo "Usage: $0 -h HOST -c COMMUNITY -d OUTPUT_DIRECTORY"
	exit 1
}

while getopts ":d:h:c:" flag; do
	case ${flag} in
		d) outdir=${OPTARG}
		;;
		h) host=${OPTARG}
		;;
		c) community=${OPTARG}
		;;
	esac
done

if [ -z "$host" ] || [ -z "$outdir" ] || [ -z "$community" ]; then
	usage
fi

# Add trailing / to output directory
if ! [[ "$outdir" == */ ]]; then
	outdir+="/"
fi

# Create dir if not exists
if [ ! -d "$outdir" ]; then
	mkdir -p $outdir
fi

set_csv_header=true
while true; do
	time=`date +"%Y-%m-%d %H:%M:%S"`
	echo "# --- --- --- $time --- --- --- #"
	# Get the panZoneEntry values (list of zones)
	for f in `$walkcmd -On -v2c -c $community $host 1.3.6.1.4.1.25461.2.1.2.3.10.1.1 | sed -e 's/.1.3.6.1.4.1.25461.2.1.2.3.10.1.1//' | sed -e 's/ = STRING: /=/'`
	do
		# For each zone, extract the zone name and get the TCP/UDP/Other IP CPS values.

		name=`echo $f | sed -e 's/.*=//' | sed -e 's/"//g'`
		oid=`echo $f | sed -e 's/=.*//'`
	
		tcp_cps_oid="1.3.6.1.4.1.25461.2.1.2.3.10.1.2$oid"
		tcp_cps=`$getcmd -On -v2c -c $community $host $tcp_cps_oid | sed -e 's/.*INTEGER: //'`
		#echo $tcp_cps

		udp_cps_oid="1.3.6.1.4.1.25461.2.1.2.3.10.1.3$oid"
		udp_cps=`$getcmd -On -v2c -c $community $host $udp_cps_oid | sed -e 's/.*INTEGER: //'`
		#echo $udp_cps

		oip_cps_oid="1.3.6.1.4.1.25461.2.1.2.3.10.1.4$oid"
		oip_cps=`$getcmd -On -v2c -c $community $host $oip_cps_oid | sed -e 's/.*INTEGER: //'`
		#echo $oip_cps

		# Divide the results by half (see doc.)
		s_tcp_cps=$(( tcp_cps / 2 ))
		s_udp_cps=$(( udp_cps / 2 ))
		s_oip_cps=$(( oip_cps / 2 ))

		echo "Zone $name - TCP_CPS $s_tcp_cps - UDP_CPS $s_udp_cps - OtherIP_CPS $s_oip_cps"

		outfile="$outdir$name.csv"

		# if it's the first run, truncate the file and add a header
		if [ "$set_csv_header" = true ] ; then
			echo "Time;TCP-CPS;UDP-CPS;OtherIP-CPS" > $outfile
		fi
		echo "$time;$s_tcp_cps;$s_udp_cps;$s_oip_cps" >> $outfile 
	done
	
	set_csv_header=false
	# Poll every 10 seconds.
	sleep 10
done
