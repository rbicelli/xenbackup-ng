####################
What is xenbackup-ng
####################

xebackup-ng is a perl script for making backups of your xenserver
infrastructure.

**************************
Changelog and New Features
**************************

* 2019-05-14: added pigz support, updated readme, added cron example file
* 2017-09-29: added xe remote cli support
            if snapshot mode selected, no snapshot is taken when vm is halted
* 2017-05-09: added Tag and vApp support in selection

*******************
Requirements
*******************

You can execute this script directly on your XenServer host or on a dedicated machine.

XenServer 6.0 and up

For installation on a generic linux machine (for connecting via remote xe cli):
* libperl-switch
* xcp-xe (See https://wiki.xenproject.org/wiki/Archive/Installing_the_Xen_Cloud_Platform_(XCP)_Command_Line_Interface_(CLI)_(XE))
* pigz

**************
Installation
**************

The easiest way is to download it from github, so open a console and type:

```
cd ~

wget https://github.com/rbicelli/xenbackup-ng/archive/master.zip
unzip master -d /opt
mv /opt/xenbackup-ng-master /opt/xenbackup-ng

```
or

```
cd /opt

git clone https://github.com/rbicelli/xenbackup-ng.git
```

************
Configuration
************

Please refer to file conf/xenbackup.conf and to example job files located
in jobs folder.

Edit at least mount options and mail options.

For scheduling on your Xenserver host you have to edit root's crontab file.

*************
Scheduling via cron
*************

Create a file /etc/cron.d/xenbackup-ng, edit as your needs and restart/reload cron daemon

Below there's an example of cron file content, which starts example-job every working day at 21:00 PM
and a weekly job every sunday at 1:00 AM

```
# xenbackup-ng

# m h dom mon dow user    command

0 21  * * 1-5  xenbackup /opt/xenbackup-ng/xenbackup.pl example-job

0 1  * * 0 xenbackup /opt/xenbackup-ng/xenbackup.pl example-job-weekly`
```


*******
License
*******

xenbackup-ng is released under the MIT License (MIT)


***************
Acknowledgement
***************

xenbackup-ng is based on original work of Filippo Zanardo ( https://pipposan.wordpress.com/ )
