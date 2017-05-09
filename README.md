###################
What is xenbackup-ng
###################

xebackup-ng is a perl script for making backups of your xenserver
infrastructure.

**************************
Changelog and New Features
**************************


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
unzip master -d /opt/

************
Configuration
************

Please refer to file conf/xenbackup.conf and to example job files located
in jobs folder.

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
