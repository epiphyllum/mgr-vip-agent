#!/usr/bin/env perl
use strict;
use warnings;
use DBI;
use Data::Dumper;
use POSIX;
use Getopt::Long

my $debug = 1;

sub help {
  my $item = shift;
  warn "缺少参数 $item\n";
  die <<'EOF';
例子:
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

EOF
}

#
#  1. yum install -y epel-release
#  2. yum install -y libdbi-dbd-mysql.x86_64  \
#        perl-DBD-MySQL.x86_64.0.4.023-6.el7 \
#        perl-DBI \
#        perl-Getopt-Long-Descriptive
#
# todo:  发送邮件  或者短信

# ./mgr_vip_agent.pl \
#   --vip 192.168.70.79 \
#   --vip_mask 24 \
#   --vip_dev ens3 \
#   --timeout 3 \
#   --interval=5 \
#   --mysql_user=root \
#   --mysql_pass jessie1234 \
#   --mysql_port=3306 \
#   --notify_max=10 \
#   --logfile /tmp/mgr-agent.log \
#   --mode=front

#
##########################################################
my $vip;                            # VIP
my $vip_mask;                       # VIP子网掩码
my $vip_dev;                        # VIP所在接口名称
my $mysql_user;                     # 本机mysql用户名
my $mysql_pass;                     # 密码

my $timeout = 2;                    # 检测超时
my $interval = 5;                   # 检测时间间隔
my $mysql_port = 3306;              # 端口
my $notify_max = 10;                #
my $logfile = "/tmp/mgr-agent.log"; #
my $mode = "front";                 # 后台/前台运行
##########################################################

GetOptions(
   "vip=s" => \$vip,
   "vip_mask=s" => \$vip_mask,
   "vip_dev=s" => \$vip_dev,
   "timeout=i" => \$timeout,
   "interval=i" => \$interval,
   "mysql_user=s" => \$mysql_user,
   "mysql_pass=s" => \$mysql_pass,
   "mysql_port=i" => \$mysql_port,
   "notify_max=i" => \$notify_max,
   "logfile=s" => \$logfile,
   "mode=s" => \$mode,
);

&help("vip")  unless  $vip;
&help("vip_mask")  unless  $vip_mask;
&help("vip_dev") unless $vip_dev;
&help("mysql_user") unless $mysql_user;
&help("mysql_pass") unless $mysql_pass;

my $add_vip_cmd = "ip addr add $vip/$vip_mask dev $vip_dev";
my $del_vip_cmd = "ip addr del $vip/$vip_mask dev $vip_dev";
my $arp_vip_cmd = "arping -q -c 2 -U -I $vip_dev $vip";
my $chk_vip_cmd = "ip addr list dev $vip_dev | grep -q $vip";
my $png_vip_cmd = "ping -c 3 $vip 1>/dev/null 2>&1";

my $hostname = `hostname`; chomp($hostname);
my $dsn = "DBI:mysql:database=performance_schema;host=$hostname:$mysql_port";
my $sql = "select member_role from replication_group_members  where member_host = '$hostname' and MEMBER_STATE = 'ONLINE'";
my @msgs = ();

my $log;
if ($mode ne "front") {
   open($log, ">>", $logfile);
} else {
   $log = *STDOUT;
}

sub datetime {
  my ($sec,$min,$hour,$mday,$mon,$year) = (localtime)[0..5];
  ($sec,$min,$hour,$mday,$mon,$year) = (
    sprintf("%02d", $sec),
    sprintf("%02d", $min),
    sprintf("%02d", $hour),
    sprintf("%02d", $mday),
    sprintf("%02d", $mon + 1),
    $year + 1900
  );
  return"$year-$mon-$mday $hour:$min:$sec";
}

# 后台运行
sub daemonize {
  my $pid = fork();
  exit if $pid;
  die "can not fork: $!" unless defined($pid);
  POSIX::setsid() or die "can not start new session: $!";
  $SIG{INT} = $SIG{TERM} = $SIG{HUP} = sub {
    die "收到信号";
    kill INT => $pid;
    exit;
  }
}

# 执行异常, 通知报警
sub notify {
  my $arg = shift;
  my $ts = &datetime();
  my $msg = "$ts\n$arg\n";
  print $log $msg;
  push @msgs, $msg;
  if (@msgs >= $notify_max) {
     print $log "通知...\n";
     @msgs = ();
  }
}

# 获取本机节点角色
sub get_node_role {
    my $role;

    eval {
      local $SIG{ALRM} = sub {
         alarm $timeout;
      };
      my $dbh = DBI->connect($dsn, $mysql_user, $mysql_pass, {'RaiseError' => 1});
      my @row = $dbh->selectrow_array($sql);
      if (@row == 0) {
         $role = "NO";
      }  else {
         $role = $row[0];
      }
      $dbh->disconnect();
    };

    if ($@) {
       return $@;
    }
    return $role;
}

# 添加VIP
sub add_vip {
   # print $log "add vip: $add_vip_cmd\n" if $debug;
   if (system("$add_vip_cmd") == 0) {
     return 1;  #
   }
   return 0;
}

# 广播vip
sub arp_vip {
   # print $log "arp vip: $arp_vip_cmd\n" if $debug;
   if (system("$arp_vip_cmd") == 0) {
     return 1;  #
   }
   return 0;
}

# 删除VIP
sub del_vip {
   # print $log "del vip: $del_vip_cmd\n" if $debug;
   if (system($del_vip_cmd) == 0 ) {
      return 1;
   }
   return 0;
}

# 检查vip
sub png_vip {
  # print $log "ping vip: $png_vip_cmd\n" if $debug;
  if(system($png_vip_cmd) == 0) {
    return 1;  # vip 存在
  }
  return 0;
}

# vip是否存在
sub chk_vip {
  # print $log "check vip: $chk_vip_cmd\n" if $debug;
  if (system("$chk_vip_cmd") == 0) {
     return 1;  # 存在
  }
  return 0; #
}

if ($mode ne "front") {
  &daemonize();
}

while(1) {
  sleep($interval);
  my $role = &get_node_role();
  if( $role eq 'NO') {
    &notify("检测失败");
    if (&chk_vip() == 1) {
      warn "删除vip $vip";
      &del_vip();
    } else {
      # secondary -> secondary
    }
  }

  #  发现自己是master
  elsif ($role eq "PRIMARY") {
    # 本机已有vip,  master -> master
    if (&chk_vip() == 1) {
    }
    # 本机没有vip添加vip
    else {
       warn "添加VIP";
       if (&add_vip() == 1) {
         &arp_vip();
         my $msg;
         if (&png_vip() && &chk_vip()) {
           $msg = "切换vip($vip)成功";
         } else {
           $msg = "切换vip($vip)失败";
         }
         &notify($msg);
      }
      # 添加IP失败
      else {
        &notify("add vip($vip)失败");
      }
    }
  }

  # 发现自己是secondary
  elsif ($role eq "SECONDARY") {
    # master -> secondary
    if (&chk_vip() == 1) {
      warn "删除vip $vip";
      &del_vip();
    } else {
      # secondary -> secondary
    }
  }
  else {
    # 异常
    &notify($role);
  }
}
