#!/bin/bash
#Version 0.6.8
log="/tmp/vrops-cluster-repair.log"
trap "(echo -ne '\n==========| Exiting per user signal at ' ; date | tr -d '\n' ; echo ' |==========') | tee -a $log; exit" SIGINT SIGKILL SIGTERM
rundate="`date +%F_%I.%M.%S_%p_%Z`"
echo -e "\n==========| Starting repair script at $rundate |==========\n" >> $log
detected_nodes="`grep -oP '"ip_address":"[^"]+"' $STORAGE/db/casa/webapp/hsqldb/casa.db.script | cut -d '"' -f4 | tr '\n' ' '`"
if [ "$detected_nodes" = "" ]; then detected_nodes="localhost" ; fi 2>&1 | tee -a $log

#########
# You may enter a space-separated list of FQDNs or IPs for each node in the 
# cluster. Do this in place of $detected_nodes between the quotes below.
# Use the following order for your nodes where applicable: 
# Master, Master Replica, Data, Remote Collector
node_list="$detected_nodes"
#########

read -p "
#####
This script will reset your vROps cluster to a known good state. 
It is not supported by VMware, and you should take a snapshot before running
it. Please note that SSH must be enabled on _ALL_ nodes for this to work, which
is not the default. Press enter to continue or CTRL+C to exit. 
#####
\$ "

read -p "
#####
Please verify that this is a complete list of all your nodes:

[ $node_list ]

If not, you may enter a space-separated list of IPs/FQDNs at the prompt, or edit
this script to ensure that all cluster members are added properly. Please use 
the order: Master, Master Replica, Data, Remote Collector.

You may also leave the prompt blank and press enter if the above list is
correct, or press CTRL+C to exit.
#####
\$ "

if [ "$override" != "" ]; then
	node_list=$override
	read -p "
#####
The node list is now changed to the following:

[ $node_list ]

Press enter to continue or CTRL+C to exit
#####
\$ "
fi

stop_order="`echo "$node_list" | tr ' ' '\n' | tac | tr '\n' ' '`"

echo -e "\nChecking SSH connectivity to nodes..." 2>&1 | tee -a $log
	disconnect () { echo -e "Unable to connect to $1 on port 22, please ensure ssh is enabled on this host.\nWill now exit." 2>&1 | tee -a $log; exit 1; }
	for h in $node_list; do 
		timeout -k 3 2 echo "Port 22 is open on $h" 3> /dev/tcp/$h/22 || disconnect $h; 
	done 2>&1 | tee -a $log

if [ ! -e "$HOME/.ssh/id_rsa.pub" ]; then 
	echo "
##### 
No SSH key found. We will generate one now. Please accept all defaults.
#####
" 2>&1 | tee -a $log
		ssh-keygen -q || exit 1
fi 2>&1 | tee -a $log

echo "
#####
We will now push the SSH host-key out to the nodes. This will require logging
in to each of the nodes one time each.
#####
" 2>&1 | tee -a $log
for h in $node_list; do 
	ssh-copy-id -o StrictHostKeyChecking=no root@$h || exit 1
done 2>&1 | tee -a $log

echo -e "\n==========| Getting date/time of each node |==========" 2>&1 | tee -a $log
for h in $node_list; do
	echo "Date/time on $h is `ssh -q root@$h date`" &
done 2>&1 | tee -a $log
wait
read -p "
#####
If any of the node clocks are more than 2 seconds out of sync, it can cause 
issues with the cluster services. Please ensure that they are obtaining a good 
timestamp either from the host (via Tools) or from NTP as per the documentation.
Press enter to continue.
#####
\$ "

echo -e "\n==========| Getting latency between nodes |==========" 2>&1 | tee -a $log
for h in $node_list; do
	echo "Average round trip latency to $h is `ping -c 10 -i 0.2 -W 5 $h | grep rtt | cut -f5 -d '/'` miliseconds" &
done  2>&1 | tee -a $log
wait
read -p "
#####
Core nodes (Master, Master Replica, Data) should not have a latency higher than
1 milisecond. Remote collectors should not have a latency higher than 100
miliseconds. It's recommended that core nodes be kept on the same physical LAN.
Press enter to continue.
#####
\$ "

read -p "
#####
Would you like to clear out alarms and alerts from database? This can improve
performance. Ongoing issues will have new alerts generated. It will fail if
the cluster is not online.
(Optional. Default: NO)
#####
(yes/NO) \$ " yn

if [[ "$yn" =~ y|yes|1 ]]; then 
		echo "This will produce errors on remote collectors, please ignore them."
	for h in $node_list; do 
		echo -e "\nBacking up alerts and alarms database on $h..."
			ssh -q root@$h "sudo -u postgres /opt/vmware/vpostgres/current/bin/pg_dumpall | gzip -9 > \$STORAGE/db/vcops/vpostgres/pg_dumpall-$rundate.gz"
		echo -e "\nTruncating alerts and alarms on $h..."
			ssh -q root@$h "sudo -u postgres /opt/vmware/vpostgres/current/bin/psql vcopsdb -c 'truncate alarm cascade;'"
			ssh -q root@$h "sudo -u postgres /opt/vmware/vpostgres/current/bin/psql vcopsdb -c 'truncate alert cascade;'"
	done
fi 2>&1 | tee -a $log

read -p "
#####
Would you like to disable IPv6? This is recommended if you do not use IPv6.
(Optional. Default: NO)
#####
(yes/NO) \$ " ipv6

read -p "
#####
Would you like to clear out the activity cache? This should only be necessary
if running this script without does not restore all functionality as desired.
(Optional. Default: NO) 
#####
(yes/NO) \$ " activities

read -p "
#####
Would you like to archive installed PAK files? They are left behind by
upgrades, patches, and add-ons. They can interfere with future upgrades and
cluster expansions. This is safe and recommended, with the caveat that the 
cluster status page will no longer show any management packs as installed,
even though they are. The Solutions page will still show them properly.
(Optional. Default: YES)
#####
(YES/no) \$ " pak

read -p "
#####
We will now perform the cluster repair. You may see some messages about services
not stopping properly. This is safe to ignore. Press enter to continue or
CTRL-C to exit.
#####
\$ "

for h in $stop_order; do
	echo -e "\n==========| Performing actions on $h |=========="
	echo "Taking node offline..."
		ssh -q root@$h "\$VMWARE_PYTHON_BIN \$VCOPS_BASE/../vmware-vcopssuite/utilities/sliceConfiguration/bin/vcopsConfigureRoles.py --action bringSliceOffline --offlineReason \"repairing\""
	echo "Stopping services..."
		ssh -q root@$h "service vmware-vcops-web stop"
		ssh -q root@$h "service vmware-vcops stop"
		ssh -q root@$h "service vmware-vcops-watchdog stop"
		ssh -q root@$h "service vmware-casa stop"
	echo "Altering cluster state..."
		ssh -q root@$h "perl -pi_$rundate.bak -e 's/sliceonline = .+/sliceonline = false/g;s/failuredetected = .+/failuredetected = false/g;s/offlinereason = .+/offlinereason = /g' \$VCOPS_BASE/../vmware-vcopssuite/utilities/sliceConfiguration/data/roleState.properties"
		ssh -q root@$h "perl -pi_$rundate.bak -e 's/\"onlineState\":\"[^\"]+\"/\"onlineState\":\"OFFLINE\"/g;s/\"ha_transition_state\":\"[^\"]+\"/\"ha_transition_state\":\"NONE\"/g;s/\"initialization_state\":\"[^\"]+\"/\"initialization_state\":\"NONE\"/g;s/\"online_state\":\"[^\"]+\"/\"online_state\":\"OFFLINE\"/g;s/\"online_state_reason\":\"[^\"]+\"/\"online_state_reason\":\"\"/g' \$STORAGE/db/casa/webapp/hsqldb/casa.db.script"
	echo "Backing up and removing old upgrade state file..."
		ssh -q root@$h "zip -2mq vcops_upgrade_state-$rundate.zip \$STORAGE/log/var/log/vmware/vcops/vcops_upgrade_state.json"
	echo "Backing up and truncating migration blobs that break upgrades..."
		ssh -q root@$h "find \$STORAGE_DB_VCOPS/blob/migrationUpgrade/ -type f -size +31M -exec zip -2q \$STORAGE/db/xdb-migrationupgrade-{}-$rundate.zip {} \; -exec truncate -cs 0 {} \;"
	if [[ ! "$pak" =~ n|no ]]; then
	echo "Backing up and removing old upgrade pak files..."
		ssh -q root@$h "find \$STORAGE/db/casa/pak/dist_pak_files/ \( -type f -o -type l \) -exec zip -0myq \$STORAGE/db/casa/pak/dist_pak_files_backup_$rundate.zip {} \;"
	fi
	if [[ "$activities" =~ y|yes ]]; then
		echo "Backing up and removing activities..."
			ssh -q root@$h "zip -r2mq \$STORAGE/db/vcops/activity-backup-$rundate.zip \$STORAGE/db/vcops/activity/*" 
	fi
	if [[ "$ipv6" =~ y|yes ]]; then
		echo "Disabling IPv6..."
			ssh -q root@$h "echo -e 'alias net-pf-10 off\nalias ipv6 off' >> /etc/modprobe.conf.local ; echo -e 'net.ipv6.conf.all.disable_ipv6 = 1\nnet.ipv6.conf.default.disable_ipv6 = 1\nnet.ipv6.conf.lo.disable_ipv6 = 1' >>/etc/sysctl.conf ; sysctl -p > /dev/null"
	fi		
done 2>&1 | tee -a $log
echo

read -p "
#####
From here, it is recommended that you reboot each node, then bring the cluster 
online from the Admin UI. This will ensure that some additional cached data is 
cleared, and free up file/port locks. However, if you run in to errors, it may
be necessary to start the nodes individually. This will result in a false 
'Offline' state to be reported as the cluster status, but vROps should
otherwise function normally. If you would like to do this now, please type
'yes' at the prompt, or simply press enter to exit.
#####
(yes/NO) \$ " yn

if [[ "$yn" =~ y|yes|1 ]]; then
	echo -e "\nBringing cluster back online. You may see some messages about services refusing\nto start due to the cluster state being offline. This can be safely ignored.\n"
	for h in $node_list; do
		echo -e "\n==========| Restarting services on $h |=========="
			ssh -q root@$h "service vmware-casa start"
			ssh -q root@$h "service vmware-vcops-watchdog start"
			#ssh -q root@$h "service vmware-vcops start"
			ssh -q root@$h "service vmware-vcops-web start"
	done
	for h in $node_list; do
		echo -e "\n==========| Bringing node $h online |=========="
		ssh -q root@$h "\$VMWARE_PYTHON_BIN \$VCOPS_BASE/../vmware-vcopssuite/utilities/sliceConfiguration/bin/vcopsConfigureRoles.py --action bringSliceOnline"
done
fi 2>&1 | tee -a $log

echo -e "\n==========| Done at `date` |==========\n" 2>&1 | tee -a $log
