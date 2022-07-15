# mgr-vip-agent
msyql mgr vip agent

##  依赖安装
```bash
yum install -y epel-release
yum install -y libdbi-dbd-mysql.x86_64  \
        perl-DBD-MySQL.x86_64.0.4.023-6.el7 \
        perl-DBI \
        perl-Getopt-Long-Descriptive
```


## example

例子:
```bash
./mgr_vip_agent.pl \
   --vip 192.168.70.79 \
   --vip_mask 24 \
   --vip_dev ens3 \
   --timeout 3 \
   --interval=5 \
   --mysql_user=root \
   --mysql_pass jessie1234 \
   --mysql_port=3306 \
   --notify_max=10 \
   --logfile /tmp/mgr-agent.log \
   --mode=front
```


## arguments
```text
参数说明:
   --vip        vip地址
   --vip_mask   子网掩码, 默认24
   --vip_dev    vip绑定的网卡接口
   --timeout    检测超时时间秒, 默认3
   --interval   检测时间间隔, 默认5
   --mysql_user 检查mysql的用户, 必需字段
   --mysql_pass 检查mysql的密码, 必需字段
   --mysql_port 默认3306
   --notify_max
   --logfile    日志文件, 默认: /tmp/mgr-agent.log
   --mode       运行模式, 默认前台模式(front), 可选: front, backend
```
