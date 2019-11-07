#!/bin/bash
# /home/oracle/dba/scripts/refresh/refresh_duplicatedb.sh SOURCE_DB SRC_DB_TNS DEST_DB DEST_DB_TNS
RES_COL=80
# Command to move out to the configured column number
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
# Command to set the color to SUCCESS (Green)
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
# Command to set the color to FAILED (Red)
SETCOLOR_FAILURE="echo -en \\033[1;31m"
# Command to set the color back to normal
SETCOLOR_NORMAL="echo -en \\033[0;39m"

step() {
    echo -n "$(date +"%m%d%Y_%H%M%S") $@"
    STEP_OK=0
    [[ -w /tmp ]] && echo $STEP_OK > /tmp/step.$$
}

try () {
  "$@"
  local EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]; then
    [[ -w /tmp ]] && echo $STEP_OK > /tmp/step.$$
    echo_failure
  else
    [[ -w /tmp ]] && echo $STEP_OK > /tmp/step.$$
    return $EXIT_CODE
  fi
}

next() {
    [[ -f /tmp/step.$$ ]] && { STEP_OK=$(< /tmp/step.$$); rm -f /tmp/step.$$; }
    [[ $STEP_OK -eq 0 ]]  && echo_success
    echo

    return $STEP_OK
}

echo_success() {
	$MOVE_TO_COL
	echo -n "["
	$SETCOLOR_SUCCESS
	echo -n $"  OK  "
	$SETCOLOR_NORMAL
	echo -n "]"
	echo -ne "\r"
	return 0
}

echo_failure() {
	export ERR_MAIL_LIST="support@team.com"
	$MOVE_TO_COL
	echo -n "["
	$SETCOLOR_FAILURE
	echo -n $"FAILED"
	$SETCOLOR_NORMAL
	echo -n "]"
	echo -ne "\r"
	echo
	echo -e "Error in function ${FUNCNAME[2]} \nError on Line Numer : ${BASH_LINENO[1]}" | mail -s "refresh : Error" ${ERR_MAIL_LIST}
	echo
	exit 1
}

setenv()
{
	step "Setting the environment variables for refresh :"
	try export SRC_DB=$1
	try export SRC_TNS=$2
	try export TAR_DB=$3
	try export TAR_TNS=$4
	try export USERNAME=sys
	try export PASSWD=`zcat /home/oracle/dba/control/.passwdfile.gz |grep -w "${USERNAME}"|grep -w "${SRC_DB}"| cut -d":" -f3 | head -1`
	try export ORACLE_HOME=/apps/oracle/product/11.2.0/dbhome_1
	try export ORACLE_BIN=${ORACLE_HOME}/bin
	try export MAIL_LIST="support@team.com"
	try export LOGLOC=/home/oracle/dba/logs/${TAR_DB}
	try export NOW=$(date +"%m%d%Y_%H%M")
	try export LOGS=${LOGLOC}/refresh_bg_${TAR_DB}_${NOW}.log
	next
	step "Setting database specific environment variable :"
	#get database specific environment variables for duplication
	try source /home/oracle/dba/scripts/refresh/.${TAR_DB}.env
	next
	
}

drop_db()
{
	step "Shutdown target database for dropping :"
	try export ORACLE_SID=${TAR_DB}

	try ${ORACLE_BIN}/sqlplus "/ as sysdba" <<-EOF > ${LOGS}
	show parameter name
	select name,open_mode from v\$database;
	shutdown immediate;
	exit;
	EOF
	next

        step "Mount database and Drop database :"
	try ${ORACLE_BIN}/sqlplus "/ as sysdba" <<-EOF >> ${LOGS}
	startup mount exclusive restrict;
	drop database;
	exit;
	EOF
	next
	
}

clean_env()
{
	step "Delete existing spfile if it exists :"
	try export FILE="${ORACLE_HOME}/dbs/spfile${TAR_DB}.ora"
	if [ -f "${FILE}" ]; 
	then
		rm -rf ${FILE}
	fi
	next
}

start_db()
{
        step "Start the database in nomount mode :"
        try export ORACLE_SID=${TAR_DB}

	try ${ORACLE_BIN}/sqlplus "/ as sysdba" <<-EOF >> ${LOGS}
	startup nomount;
	exit;
	EOF
	next

}

dupdb()
{
	step "Start Duplicate database from production :"
	try ${ORACLE_BIN}/rman target ${USERNAME}/${PASSWD}@${SRC_TNS} auxiliary ${USERNAME}/${PASSWD}@${TAR_TNS} <<-EOF >> ${LOGS}
	run {
	allocate channel ch1 device type disk;
	allocate channel ch2 device type disk;
	allocate channel ch3 device type disk;
	allocate channel ch4 device type disk;
	allocate channel ch5 device type disk;
	allocate channel ch6 device type disk;
	allocate channel ch7 device type disk;
	allocate channel ch8 device type disk;
	allocate auxiliary channel ch9 device type disk;
	allocate auxiliary channel ch10 device type disk;
	allocate auxiliary channel ch11 device type disk;
	allocate auxiliary channel ch12 device type disk;
	allocate auxiliary channel ch13 device type disk;
	allocate auxiliary channel ch14 device type disk;
	allocate auxiliary channel ch15 device type disk;
	allocate auxiliary channel ch16 device type disk;
	DUPLICATE DATABASE TO ${TAR_DB} from active database
	SPFILE
		parameter_value_convert ('${SRC_DB}','${TAR_DB}')
		SET CLUSTER_DATABASE='FALSE'
		set db_file_name_convert=${DB_FILE}
		set log_file_name_convert=${LOG_FILE}
		set control_files=${CONTROL_FILE}
		set db_name='${TAR_DB}'
		set log_archive_dest_1='location=/dump1/archivelogs/${TAR_DB}/'
		set audit_file_dest='/apps/oracle/admin/${TAR_DB}/adump'
		set audit_sys_operations='FALSE'
		set audit_trail='none'
		set log_archive_config=''
		set log_archive_dest_2=''
		set log_archive_dest_state_2='DEFER'
	BACKUP LOCATION '/dump1/backup' nofilenamecheck;
	release channel ch1;
	release channel ch2;
	release channel ch3;
	release channel ch4;
	release channel ch5;
	release channel ch6;
	release channel ch7;
	release channel ch8;
	release channel ch9;
	release channel ch10;
	release channel ch11;
	release channel ch12;
	release channel ch13;
	release channel ch14;
	release channel ch15;
	release channel ch16;
	}
	exit;
	EOF
	next
	step "Proceeding with verification of refresh :"
	next
}

appscript()
{
	step "Run Application specific script :"
        try ${ORACLE_BIN}/sqlplus "/ as sysdba" <<-EOF >> ${LOGS}
	@${SQLS};
	EOF
	next
}

chklog()
{
	step "Check and Notify RMAN log for warnings and errors :"
	if egrep -iv "ORA-00001" ${LOGS} | egrep -i "ORA-|RMAN-" 
	then
		echo -e "Refresh of ${TAR_DB} completed with errors or warnings.\nAttached herewith is the errorlog." | mail -a "${LOGS}" -s "${TAR_DB} refresh : Error" ${MAIL_LIST}
	else
		echo -e "${TAR_DB} has been refreshed successfully." | mail -a "${LOGS}" -s "${TAR_DB} refresh : Success" ${MAIL_LIST} 
	fi
	next
}

setenv "$@"
drop_db
clean_env
start_db
dupdb
appscript
chklog
