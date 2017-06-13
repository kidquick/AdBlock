#!/bin/sh

# Variables
jffs=/jffs
adblockScript=/jffs/dns/adblock.sh
whitelist=/jffs/dns/whitelist
blacklist=/jffs/dns/blacklist
hostsUrl=http://www.mvps.org/winhelp2002/hosts.txt
hostsTmp=/tmp/hosts.tmp
hostsJffs=/jffs/dns/hosts
dnsmasqUrl=http://pgl.yoyo.org/adservers/serverlist.php?hostformat=dnsmasq&showintro=0&mimetype=plaintext
dnsmasqTmp=/tmp/dnsmasq.tmp
dnsmasqJffs=/jffs/dns/dnsmasq.conf
nvram=/tmp/dnsmasq-options.tmp
crontab=/tmp/crontab
pixelserv=/jffs/dns/pixelserv

# Debugging
#echo "alias mem='cat /proc/meminfo'" >> /tmp/root/.profile
#echo "alias ll='ls -lash --color=auto'" >> /tmp/root/.profile
#echo "alias ls='ls --color=auto'" >> /tmp/root/.profile
#echo "alias tlog='tail -f /var/log/messages'" >> /tmp/root/.profile
#echo "alias clog='cat /var/log/messages | grep local0.notice'" >> /tmp/root/.profile

# Logger
logger_ads()
{
  logger -s -p local0.notice -t adblock $1
}

# Create a symlink to a file in RAM
softlink_func()
{
  ln -s $1 $2
  if [ "`echo $?`" -eq 0 ]; then
    logger_ads "Created symlink $3 from JFFS to RAM"
  else
    logger_ads "FAILED to create symlink $3 from JFFS to RAM"
    exit 1
  fi
}

# Disk full error message
insufficient_space()
{
  logger_ads "Insufficient free space on JFFS. Required $1 KB."
}

logger_ads "### BEGIN: AdBlock ###"

nvram set aviad_changed_nvram=0

# check for script parameters
if [[ -z "$1" ]]; then
  logger_ads "Sleeping for 30 secs to give time for router to boot"
  sleep 30
elif [ $1 = "-f" ]; then
  logger_ds "Forcing blocklists refresh"
  rm $hostsJffs $dnsmasqJffs
else
  echo "Use -f to force a refresh"
  exit 0
fi

logger_ads "Waiting for internet connection"
while ! ping google.com -c 1 > /dev/null ; do
  logger_ads "Sleeping for 5 seconds..."
  sleep 5
done

logger_ads "Setup pixelserv host (IP x.x.x.254)"
pixelHost="`ifconfig br0 | grep inet | awk '{ print $3 }' | awk -F ":" '{ print $2 }' | cut -d . -f 1,2,3`.254"
/sbin/ifconfig br0:1 $pixelHost netmask "`ifconfig br0 | grep inet | awk '{ print $4 }' | awk -F ":" '{ print $2 }'`" broadcast "`ifconfig br0 | grep inet | awk '{ print $3 }' | awk -F ":" '{ print $2 }'`" up

logger_ads "Starting router admin GUI"
if [[ -z "`ps | grep -v grep | grep "httpd -p 81"`" && `nvram get http_lanport` -ne 81 ]] ; then
  stopservice httpd
  nvram set http_lanport=81
  nvram set aviad_changed_nvram=1
  startservice httpd
else
  logger_ads "Router admin GUI already running"
fi

logger_ads "Setting auto-refresh cron for every Monday at 4am"
if [[ -z "`cat $crontab | grep "$adblockScript"`" ]] ; then
  echo '0 4 * * 0 root ${adblockScript} -f' > $crontab
  stopservice cron && logger_ads "Stopped the cron service"
  startservice cron && logger_ads "Started the cron service"
else
  logger_ads "Script is already in cron"
fi

logger_ads "Firewall: redirect router admin GUI to port 81"
[[ -z "`iptables -L -n -t nat | grep $(nvram get lan_ipaddr) | grep 81`" ]] && logger_ads "Creating firewall rule: redirect router admin GUI to port 81" && /usr/sbin/iptables -t nat -I PREROUTING 1 -d $(nvram get lan_ipaddr) -p tcp --dport 80 -j DNAT --to $(nvram get lan_ipaddr):81
nvram get rc_firewall > /tmp/fw.tmp
if [[ -z "`cat /tmp/fw.tmp | grep "/usr/sbin/iptables -t nat -I PREROUTING 1 -d $(nvram get lan_ipaddr) -p tcp --dport 80 -j DNAT --to $(nvram get lan_ipaddr):81"`" ]] ; then
  logger_ads "Appending to firewall script"
  echo "/usr/sbin/iptables -t nat -I PREROUTING 1 -d $(nvram get lan_ipaddr) -p tcp --dport 80 -j DNAT --to $(nvram get lan_ipaddr):81" >> /tmp/fw.tmp
  nvram set rc_firewall="`cat /tmp/fw.tmp`"
  nvram set aviad_changed_nvram=1
else
  logger_ads "Firewall script is already setup"
fi
rm /tmp/fw.tmp

logger_ads "Starting pixelserv"
if [[ -n "`ps | grep -v grep | grep "$pixelserv"`" ]]
then
  logger_ads "Pixelserv is already running"
else
  $pixelserv $pixelHost -p 80
fi

logger_ads "Creating whitelist"
if [ ! -e $whitelist ]; then
  echo google-analytics > $whitelist
  echo googleadservices >> $whitelist
else
  logger_ads "Whitelist already exists"
fi

logger_ads "Fetching block lists"
if [[ -n "$(find "$hostsJffs" -mtime +7)" || -n "$(find "$dnsmasqJffs" -mtime +7)" || ! -e $hostsJffs || ! -e $dnsmasqJffs ]]; then
  logger_ads "Lists do not exist or are more than 1 week old"

  logger_ads "Downloading hosts file"
  wget -q -O - "$hostsUrl" | grep "^0.0.0.0" | grep -v localhost | tr -d '\015' > $hostsTmp
  logger_ads "Formatting hosts file"
  cat $whitelist | while read line; do sed -i /${line}/d $hostsTmp ; done
  sed -i s/0.0.0.0/$pixelHost/g $hostsTmp

  logger_ads "Downloading dnsmasq list"
  wget -q "$dnsmasqUrl" -O "$dnsmasqTmp"
  logger_ads "Formatting dnsmasq list"
  cat $whitelist | while read line; do sed -i /${line}/d $dnsmasqTmp ; done
  sed -i s/127.0.0.1/$pixelHost/g $dnsmasqTmp

  logger_ads "Moving dnsmasq list to JFFS"
  dnsmasqSize=`du -k "$dnsmasqTmp" | cut -f1`
  if [ "`df | grep /jffs | awk '{ print $4 }'`" -ge $dnsmasqSize ] ; then
    mv $dnsmasqTmp $dnsmasqJffs
    if [ "`echo $?`" -eq 0 ] ; then
      logger_ads "Succesfully moved dnsmasq list to JFFS"
    else
      insufficient_space $dnsmasqSize
      rm $dnsmasqJffs
      softlink_func $dnsmasqTmp $dnsmasqJffs dnsmasq
    fi
  else
    insufficient_space $dnsmasqSize
    rm $dnsmasqJffs
    softlink_func $dnsmasqTmp $dnsmasqJffs dnsmasq
  fi

  logger_ads "Moving hosts file to JFFS"
  hostsSize=`du -k "$hostsTmp" | cut -f1`
  if [ "`df | grep /jffs | awk '{ print $4 }'`" -ge $hostsSize ] ; then
    mv $hostsTmp $hostsJffs
    if [ "`echo $?`" -eq 0 ] ; then
      logger_ads "Succesfully moved hosts file to JFFS"
    else
      insufficient_space $hostsSize
      rm $hostsJffs
      softlink_func $hostsTmp $hostsJffs hosts
    fi
  else
    insufficient_space $hostsSize
    rm $hostsJffs
    softlink_func $hostsTmp $hostsJffs hosts
  fi
else
  logger_ads "The lists are less then 3 days old, saving on flash erosion and NOT refreshing them"
fi

logger_ads "Adding hosts and dnsmasq to nvram"
nvram get dnsmasq_options > $nvram
if [[ -z "`cat $nvram | grep "$dnsmasqJffs"`" || -z "`cat $nvram | grep "$hostsJffs"`" && -e $dnsmasqJffs && -e $hostsJffs ]] ; then
  echo "addn-hosts=$hostsJffs" >> $dnsmasqNvram
  echo "conf-file=$dnsmasqJffs" >> $dnsmasqNvram
  nvram set aviad_changed_nvram=1
else
  logger_ads "Hosts and dnsmasq already in nvram"
fi

logger_ads "Adding personal blacklist"
if [[ -z "`cat $dnsmasqTmp | grep conf-file=$blacklist`" && -z "`nvram get dnsmasq_options | grep "$blacklist"`" && -e $blacklist ]] ; then
  logger_ads "Removing whitelist from blacklist"
  cat $whitelist | while read line; do sed -i /${line}/d $blacklist ; done
  echo "conf-file=$blacklist" >> $nvram
  nvram set aviad_changed_nvram=1
else
  [ ! -e $blacklist ] && logger_ads "Personal blacklist not found"
fi

logger_ads "Final settings implementer"
if [ "`nvram get aviad_changed_nvram`" -eq 1 ] ; then
  nvram set dnsmasq_options="`cat $nvram`"
  logger_ads "Applying changes to nvram"
  nvram commit
  nvram set aviad_changed_nvram=0
  logger_ads "Refreshing DNS server"
  stopservice dnsmasq && logger_ads "Stopped dnsmasq service"
  startservice dnsmasq && logger_ads "Started dnsmasq service"
else
  logger_ads "Nothing to commit to nvram"
fi
rm $nvram

### Enable LED blinking ###
#logger_ads "Blinking the router LED"
#tmp=20
#while [ $tmp -ge 0 ]; do
#	/sbin/gpio enable 3
#	ping "`nvram get lan_ipaddr`" -c 1 > /dev/null
#	/sbin/gpio disable 3
#	tmp=`expr $tmp - 1`
#done
#/sbin/gpio enable 2
#/sbin/gpio disable 3

logger_ads "### END: AdBlock ###"
