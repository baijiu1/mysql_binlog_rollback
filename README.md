# mysql_binlog_rollback
mysqlbinlog shell script;rollback data
用SHELL写的一个mysql binlog回滚脚本，利用mysqlbinlog工具先解析出原始语句，然后利用sed工具还原格式，最后还原为回滚语句
mysqlbinlog原生工具比python快
该脚本只适合于某个单一的方面，UPDATE或DELETE语句可用
使用前提：
1、mysql服务器必须要设置login-path=db_root
2、必须指定binlog文件和目录
3、mysql必须要可以连接，需要查找到需要表的元数据
4、必须指定某个表，某个库进行精确查找
