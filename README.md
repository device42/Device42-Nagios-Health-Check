# README #

### How to install? ###

Install perl libs

`yum install perl-JSON.noarch perl-Nagios-Plugin.noarch`

copy file d42.cfg to Nagios configuration path (e.g: /etc/nagios/servers/)

copy file check_d42_health to Nagios library directory (e.g: /usr/lib64/nagios/plugins/)

set permission with command `chmod +x check_d42_health`


uncomment next line in nagios.cfg file

cfg_dir=/etc/nagios/servers


###  How to run ?###

perl <check_d42_health path> -H <hostname> -P <port number> -I <metric name> -c <critical threshold> -w <warn threshold>

`perl check_d42_health -H svnow01.device42.com -P 4242 -I cpu_used_percent -w 10 -c 20`

List of available metrics

* cpu_used_percent
* dbsize
* disk_used_percent
* memtotal
* cached
* swapfree
* swaptotal
* memfree
* buffers

### Messages/Events ###
* UNKNOWN Item is not defined - no item found in server respose
* UNKNOWN Can not parse JSON received from server
* UNKNOWN No data received from server
* CRITICAL script execution time out
* UNKNOWN - no data for item <item name>