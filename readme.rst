####################
What is xenbackup-ng
####################

xebackup-ng is a perl script for making backups of your xenserver
infrastructure.

**************************
Changelog and New Features
**************************

2017-05-09: added Tag and vApp support in selection

*******************
Requirements
*******************

XenServer 6.0 and up

************
Installation
************

The script needs to be installed on your XenServer.

The easiest way it to download it from github, so open a console on your
Xenserver and type:

cd ~
wget https://github.com/rbicelli/xenbackup-ng/archive/master.zip
unzip master -o -d /opt/

************
Configuration
************

Please refer to file conf/xenbackup.conf and to example job files located
in jobs folder.

Edit at least mount options and mail options.

For scheduling you have to edit root's crontab file.

*******
License
*******

xenbackup-ng is released under the MIT License (MIT)

*********
Resources
*********


***************
Acknowledgement
***************

xenbackup-ng is based on original work of Filippo Zanardo ( https://pipposan.wordpress.com/ )
