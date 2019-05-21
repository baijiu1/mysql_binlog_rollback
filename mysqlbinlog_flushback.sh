#!/bin/bash
#mysql UPDATE DELETE恢复脚本
#set fileformat=unix
#:%s/\r\+$//e
function usage(){
cat <<-EOF
	usage:$0 -b [binlog_name] -d [database_name] -t [table_name] -s [start_time] -o [stop_time] -p [start_position] -z [stop_position] -f [format]
	OPTIONS:
		mysql必须可以连接，且必须有login-path已经设置，并且login-path=db_root
		必须要指定相应的数据库名称和表名称
		只支持INSERT|UPDATE|DELETE回滚
		-f参数在执行脚本时需要指定回滚的类型，必须指定,如果不指定，那么默认为UPDATE类型
		最好输入starttime和stoptime来指定到一个范围,默认开始时间为前一天，结束时间为当前时间
		如果不输入开始的position或结束的position，默认为二进制日志的开头和结束，需要指定一个开始的position
		-b:		binlogname for mysql 必须是绝对路径指定
		-d:		database_name
		-t:		tablename
		-s:		start-datetime
		-o:		stop-datetime
		-p:		start-position
		-z:		stop-position
		-f:		format mode(INSERT|UPDATE|DELETE)
EOF
}
while getopts b:d:t:s:o:p:z:f: flag
do
	case $flag in
		b)
			binlog=$OPTARG
		;;
		d)
			database_name=$OPTARG
		;;
		t)
			table_name=$OPTARG
		;;
		s)
			starttime=$OPTARG
		;;
		o)
			stoptime=$OPTARG
		;;
		p)
			start_p=$OPTARG
		;;
		z)
			stop_p=$OPTARG
		;;
		f)
			format=$OPTARG
		;;
	esac
done

if [ $OPTIND -eq 1 ];then
	usage
	exit 0;
fi
start_posi=$(mysql --login-path=db_root -e "show binlog events in '"$binlog"'" 2>/dev/null | awk 'NR==2{print $5}')
stop_posi=$(mysql --login-path=db_root -e "show binlog events in '"$binlog"'" 2>/dev/null | awk 'END{print $5}')
col=$(mysql --login-path=db_root -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS where TABLE_SCHEMA = '$database_name' and TABLE_NAME = '$table_name'" 2>/dev/null | awk '{print}'|grep -Ev 'COLUMN_NAME'|awk '{printf("%s,",$1)}'|sed 's/,/ /g')
arr=($col)
arr_len=${#arr[@]}
c=1
sleep 3
function ch_parameter(){
	if [ -z $starttime ];then
		starttime=`date -d '-1 days' +'%Y-%m-%d %H:%M:%S'`
	fi
	if [ -z $stoptime ];then
		stoptime=`date +'%Y-%m-%d %H:%M:%S'`
	fi
	if [ -z $start_p ];then
		start_p=$start_posi
		is_null='1'
		echo "开始position为空，设置为: $start_posi"
	fi
	if [ -z $stop_p ];then
		stop_p=$stop_posi
		echo "结束position为空，设置为: $stop_posi"
	fi
	if [ -z $format ];then
		format='update'
	fi
}
function update_delete_r(){
	ch_parameter
	if [ "$format" == "update" ] || [ "$format" == "UPDATE" ];then
			mysqlbinlog --no-defaults -v -v --base64-output=DECODE-ROWS --database=$database_name --start-datetime="$starttime" --stop-datetime="$stoptime" --start-position="${start_p}" --stop-position="${stop_p}" $binlog > recover.sql
			if [ "$is_null" == "1" ];then
				tac recover.sql | sed -n "/### UPDATE `$database_name`.`$table_name`/,/BEGIN/p" > update_roll.sql
			else
				cat recover.sql | sed -n "/# at $start_p/,/COMMIT/p" > update_roll.sql
			fi
			sed '/WHERE/{:a;N;/SET/!ba;s/\([^\n]*\)\n\(.*\)\n\(.*\)/\3\n\2\n\1/}' update_roll.sql | sed 's/### //g;s/\/\*.*/,/g' | sed  '/@'$arr_len'/s/,//g' | sed '/WHERE/{:a;N;/@'$arr_len'/!ba;s/,/AND/g};s/#.*//g;s/COMMIT,//g' | sed '/^$/d'  >  rollback.sql &&
			sed  -i -r  '/WHERE/{:a;N;/@'$arr_len'/!ba;s/(@'$arr_len'=.*)/\1\;/g}' rollback.sql &&
			for i in ${arr[@]}
			do
				sed -i "s/@${c}\?=/${i}=/" rollback.sql
				((c++))
			done
			rm -rf recover.sql
			rm -rf update_roll.sql
			echo "UPDATE语句回滚完成，回滚后的文件为：rollback.sql"
	fi
	if [ "$format" == "delete" ] || [ "$format" == "DELETE" ];then
			mysqlbinlog --no-defaults -v -v --base64-output=DECODE-ROWS --database=$database_name --start-datetime="$starttime" --stop-datetime="$stoptime" --start-position="${start_p}" --stop-position="${stop_p}" $binlog > delete.sql
			if [ "$is_null" == "1" ];then
				tac delete.sql | sed -n "/### DELETE FROM `$database_name`.`$table_name`/,/BEGIN/p" > del_roll.sql
			else
				sed -n "/# at $start_p/,/COMMIT/p" delete.sql > del_roll.sql
			fi
		sed -n "/# at $start_p/,/COMMIT/p" delete.sql  > del_roll.sql
		cat del_roll.sql  | sed -n '/###/p' | sed 's/### //g;s/\/\*.*/,/g;s/DELETE FROM/INSERT INTO/g;s/WHERE/SELECT/g;' | sed -r "s/(@$arr_len.*),/\1;/g" | sed 's/@[0-9]*=//g' > rollback.sql
		rm -rf delete.sql
		rm -rf del_roll.sql
		echo "DELETE语句回滚完成，回滚后的文件为：rollback.sql"
	fi

}
update_delete_r
