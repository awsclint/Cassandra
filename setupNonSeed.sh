#!/bin/bash
#################################################################
# Install cfn and xfs packages
#################################################################
yum update -y aws-cfn-bootstrap
yum -y install xfsprogs
#################################################################
# Set sleep time to stagger service start
#################################################################
instanceid=$(curl -s curl http://169.254.169.254/latest/meta-data/instance-id/)
index=$(curl -s curl http://169.254.169.254/latest/meta-data/ami-launch-index)
zone=$(curl -s curl http://169.254.169.254/latest/meta-data/placement/availability-zone|cut -d'-' -f3)
zonevalue=${zone:1}
if [[ $zonevalue == "a" ]]; then 
	increment=1; 
elif [[ $zonevalue == "b" ]]; then 
	increment=2; 
elif [[ $zonevalue == "c" ]]; then 
	increment=3; 
elif [[ $zonevalue == "d" ]]; then 
	increment=4; 
elif [[ $zonevalue == "e" ]]; then 
	increment=5; 
fi;
sleepvalue=$(expr $(expr $increment + $index + $index) * 60)
sleep $sleepvalue
#################################################################
# Set limits
#################################################################
echo "cassandra - memlock unlimited\ncassandra - nofile 100000\ncassandra - nproc 32768\ncassandra - as unlimited" >> /etc/security/limits.d/cassandra.conf
echo "* - nproc 32768" >> /etc/security/limits.d/90-nproc.conf 
echo "vm.max_map_count = 131072" >> /etc/sysctl.conf 
sysctl -p
#################################################################
# Configuration to manage node replacements and record node changes in dynamodb
#################################################################
commitlogvolume=$(cat /tmp/describec2instance.data|grep -A 5 "/dev/xvdbb"|grep VolumeId|cut -d':' -f2|cut -d'"' -f2)
datavolume=$(cat /tmp/describec2instance.data|grep -A 5 "/dev/xvdba"|grep VolumeId|cut -d':' -f2|cut -d'"' -f2)
az=$(curl -s curl http://169.254.169.254/latest/meta-data/placement/availability-zone)
python -c "import boto; from boto.dynamodb2.table import Table; table = Table('cassandraasgreplace'); table.put_item(data = { 'instanceid' : '$instanceid', 'privateIP' : '$(cat /tmp/privateipcurrent.data)', 'datavolumeinfo' : '$datavolume', 'commitlogvolumeinfo' : '$commitlogvolume', 'availabilityzone' : '$az', 'status' : 'current', 'role' : 'NonSeed' });"
terminateinstancecount=$(cat /tmp/asgactivity.data|grep -c "\"Terminating EC2 instance:")
cat /tmp/asgactivity.data|grep "\"Launching a new EC2 instance:\|\"Terminating EC2 instance:"|sed -n -e "/$instanceid/,/Terminating/p"|awk 'BEGIN { term=1 } /Terminating/ { term=0  } /Launching/ { if (term == 1) print $0}' > /tmp/asgpart1 
cat /tmp/asgactivity.data|grep "\"Launching a new EC2 instance:\|\"Terminating EC2 instance:"|sed -n -e "/$instanceid/,/Terminating/p" > /tmp/asgfindnext 
onlylaunchcount=$(cat /tmp/asgpart1|wc -l) 
nextpart=$(cat /tmp/asgfindnext|tail -1|cut -d':' -f3|cut -d' ' -f2|cut -d'"' -f1)
cat /tmp/asgactivity.data|grep "\"Launching a new EC2 instance:\|\"Terminating EC2 instance:"|sed -n -e "/$nextpart/,/Launching/p"|awk 'BEGIN { term=1 } /Launching/ { term=0  } /Terminating/ { if (term == 1) print $0}' > /tmp/asgpart2
launchindex=$(grep -n "" /tmp/asgpart1| sort -r -n| cut -d':' -f2-|grep -n $instanceid|cut -d':' -f1) 
terminatecount=$(cat /tmp/asgpart2|wc -l)
if [[ $terminateinstancecount -gt 0 && $onlylaunchcount -le $terminatecount ]]; then 
	oldinstanceindex=$(($terminatecount - $launchindex + 1)) 
	oldinstanceid=$(cat /tmp/asgpart2|awk "NR==$oldinstanceindex{ print; }"|cut -d':' -f3|cut -d'"' -f1|cut -d' ' -f2)
if [[ $oldinstanceid != "" ]]; then 
	echo "$((($launchindex+$launchindex) * 60))" > /tmp/sleeptime; 
	dollar='$'; 
	python -c "import boto; from boto.dynamodb2.table import Table; table = Table('cassandraasgreplace'); privateip = table.get_item(instanceid = '$oldinstanceid'); privateip['status'] = 'Terminated'; privateip['replacementnode'] = '$instanceid'; privateip.save(); f = open('/tmp/privateip.data', 'w'); f.write('JVM_OPTS=\"$dollar'+'JVM_OPTS -Dcassandra.replace_address='+privateip['privateIP']+'\"'); f.close();"; 
fi 
else 
	launchindex=$(cat /tmp/asgactivity.data|grep "\"Launching a new EC2 instance:"|grep -n $instanceid|cut -d':' -f1)
	echo "$(($launchindex * 60))" > /tmp/sleeptime; 
fi
#################################################################
# Setup Filesystem, directories and permissions
#################################################################
for mntpnt in `cat /proc/mounts|grep xvd[b-z]|awk '{print $1}'`; do umount $mntpnt; done
mkfs -t xfs /dev/xvdba
mkfs -t xfs /dev/xvdbb
mkdir -p /data
mkdir -p /commitlog
mount -t xfs -o noatime /dev/xvdba /data
mount -t xfs -o noatime /dev/xvdbb /commitlog
chmod 777 /etc/fstab
echo "/dev/xvdba /data xfs noatime 0 0" | tee -a /etc/fstab
echo "/dev/xvdbb /commitlog xfs noatime 0 0" | tee -a /etc/fstab
mkdir -p /data/saved_caches
adduser cassandra
chown -R cassandra:cassandra /data
chown -R cassandra:cassandra /commitlog