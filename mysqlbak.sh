#!/usr/bin/env bash

### Author: Adam Courtemanche
### Last Modified: 05/04/2010
###
### This script makes it easy to:
###    backup a remote or local MySQL database to a SQL file.
###    import a remote MySQL database into your local database.
###    export your local MySQL database to a remote database.
###
### Note that you must already have a database set up on your local machine.
### This script will not do that for you.
###
### run script with --help or -h for usage instructions 

echo "" #add padding above messages

# Set some colors to use in messages
blue="\033[34m"
red="\033[1;31m"
green="\033[32m"
white="\033[37m"

# Writes error message to screen and exits script if error is found
errorCheck() { echo -e "${red}$1\n"; tput sgr0; exit 1;}

###########################################
### Create help screen
###########################################
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
	echo -e "${blue}  Syntax:"
	echo -e "${white}  mysqlbak.sh configfile [--import | --export | --remotebackup | --localbackup] "
	echo ""
	echo -e "${blue}  Configuration:"
	echo -e "${white}  To backup a database, you need to have a configuration file for it."
	echo -e "  Simply copy the example configuration file (example.conf) and modify its values."
	echo -e "  This new file must have a .conf extension."
	echo ""
	echo -e "${blue}  Options:"
	echo -e "${white}  --export : copies MySQL data/structure from LOCAL --> REMOTE"
	echo -e "  --import : copies MySQL data/structure from REMOTE --> LOCAL"
	echo -e "  --remotebackup : create LOCAL SQL file backup of REMOTE database"
	echo -e "  --localbackup : create LOCAL SQL file backup of LOCAL database"
	echo ""
	echo "     *note that --import and --export will DROP existing data during copy"
	echo "      after backing it up first, of course!"
	echo ""
	echo -e "${blue}  Example:"
	echo -e "${white}  ./mysqlbak.sh serverx.conf --remotebackup"
	echo ""
	exit 0
fi

# If no configuration file argument or file not found, show message and exit 
if  [ "$1" == "" ] || [ ! -f $1 ]; then
	errorCheck "  You must provide a valid configuration file!\n\n  Use --help \
or -h for usage tips."
fi

# If no method of operation, show message and exit
if [ -z "$2" ]; then
	errorCheck "  You must provide a method!\n\n  Use --help or -h for \
usage tips."
fi

# Pull in the configuration settings (variables)
source $1

# Make sure export paths don't end with "/", create a good date variable
localSQL=${localBackupTargetOnLocal%/}
remoteSQL=${remoteBackupTargetOnLocal%/}
date=$(date +%Y%m%d_%H%M%S)

# Dump SQL code to a file
createSQL(){
	# determine which database we are dealing with; set variables appropriately
	if [ "$1" == "local" ]; then
		host=$localHostname
		db=$localDatabaseName
		dbuser=$localUsername
		dbpass=${localPassword}
		sqlFile=${localSQL}"/"${host}"_"${db}"_"${date}".sql.gz"
	elif [ "$1" == "remote" ]; then
		host=$remoteHostname
		db=$remoteDatabaseName
		dbuser=$remoteUsername
		dbpass=${remotePassword}
		sqlFile=${remoteSQL}"/"${host}"_"${db}"_"${date}".sql.gz"
	fi

	# if SSH information is provided, use it to gzip on the server before transfer
	if [ ! -z "$sshServer" ] && [ ! -z "$sshUsername" ] && [ "$1" == remote ]; then
		if [ -z "$sshPort" ]; then
			sshPort=22
		fi
		ssh -v -p ${sshPort} ${sshUsername}@${sshServer} "mysqldump -u ${dbuser} --password='${dbpass}' --compress -h '${sshDBHostname}' ${db} | gzip -9 -c -f" > ${sqlFile} || errorCheck "  Could not backup to local SQL file"
	else
		mysqldump -u ${dbuser} --password="${dbpass}" --compress -h "${host}" ${db} | gzip -9 -c > ${sqlFile} || errorCheck "  Could not backup to local SQL file"
	fi

	# if this is the source, unzip the gz file and store filename for mysql cli
	if [ "$2" == "sourceDB" ]; then
		sqlForImport=${sqlFile%.*z}
		gunzip -c -q ${sqlFile} > ${sqlForImport} || errorCheck "  Could not gunzip sql dump file"
	fi
}

# Dumps SQL code from computer#1
# backs up database from computer#2
# imports SQL code from computer#1 to computer#2
# DO NOT CHANGE THE ORDER HERE! the 2nd "createSQL" MUST be the target
updateDatabase(){
	if [ "$1" == "local" ]; then
		createSQL "remote" "sourceDB" #copy remote db and use as source
		createSQL "local" #make backup of local DB
	elif [ "$1" == "remote" ]; then
		createSQL "local" "sourceDB"
		createSQL "remote"
	fi

	# drop all tables in the database
	(
	set -o pipefail
	mysqldump -u ${dbuser} --password="${dbpass}" -h "${host}" --add-drop-table --no-data \
	${db} | grep ^DROP | mysql -u ${dbuser} --password="${dbpass}" -h "${host}" \
	-D ${db} || errorCheck "  Could not drop all tables from database ${db};\n  database may contain leftover tables!"
	)

	# import the data
	mysql -u ${dbuser} --password="${dbpass}" -h "${host}" -D \
	${db} < "${sqlForImport}" || errorCheck "  Could not update database ${db} on ${host}"

	rm ${sqlForImport} #remove the .sql file (we still have the .gz version)
}

###########################################
### Handle user choices and perform actions
###########################################
if [ "$2" = "--remotebackup" ]; then
	createSQL "remote"
	echo -e "${green}  Dumped SQL file to:\n  "${sqlFile}
elif [ "$2" = "--localbackup" ]; then
	createSQL "local"
	echo -e "${green}  Dumped SQL file to:\n  "${sqlFile}
elif [ "$2" = "--import" ]; then
	updateDatabase "local"
	echo -e "${green}  Backed up local database"
	echo -e "${green}  Imported SQL from remote server into local database"
elif [ "$2" = "--export" ]; then
	updateDatabase "remote"
	echo -e "${green}  Made local backup of remote server database"
	echo -e "${green}  Exported local SQL data to remote server"
else
	echo -e "${red}  ${2} is not a valid option!\n\n  Use --help or -h for \
usage tips.\n"
	tput sgr0; exit 1
fi
echo ""
tput sgr0
exit 0
