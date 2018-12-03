#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use IO::CaptureOutput qw(capture);
use IO::Tee;
use Net::OpenSSH::Parallel;
use POSIX qw(strftime);
use Sys::Hostname;
my $hostname = hostname;
my $log_dir = '/root/push-logs';
my %opts = ( workers => 10, connections => 10, reconnections => 1 );
my %ssh_opts = ( user => 'root', port => 22, timeout => 10 );
my $key_path = '/root/.ssh/id_rsa';
my %hosts;
my $host_list = '/root/myhosts.ver2';
my $cmd = '/root/fix_resolvconf';
my $log_date = POSIX::strftime('%m-%d-%Y',localtime);
my ($month,$day,$year) = split(/-/,$log_date);
$log_dir = $log_dir.'/'.$year.'/'.$month.'/'.$day;
unless (-d $log_dir) {
        make_path($log_dir, { mode => 0750 });
}
my $log_file = time().'.log';
open(my $l, '>>', $log_dir.'/'.$log_file);
my $tee = new IO::Tee(\*STDOUT, $l);
sub main {
        unless (-s $cmd) { die("[!] Command file ($cmd) is empty or does not exist!\n"); }
        if (-s $host_list) {
                open(my $dat, '<', $host_list);
                while(<$dat>) {
                        chomp;
                        $hosts{$_} = 1;
                }
                close($dat);
        } else {
                open(my $dat, '<', '/etc/hosts');
                while(my $l = <$dat>) {
                        my @host = split(/\s+/,$l);
                        if ($host[1] =~ /^compute/) {
                                $hosts{$host[1]} = 1;
                        }
                }
                close($dat);
        }
        do_push($cmd);
}
sub do_push($) {
        my ($cmd_file) = @_;
#       print "[+] Running command file ($cmd_file) on $host.\n";
        my $pssh = Net::OpenSSH::Parallel->new(%opts);
        foreach my $host (sort keys %hosts) {
                _log('INFO',"Adding host $host to push list.");
                $pssh->add_host($host, key_path => $key_path, %ssh_opts);
        }
        _log('INFO',"Executing command file ($cmd_file) on ".scalar (keys %hosts)." hosts.");
        _log('INFO',"Command file ($cmd_file):");
        open(my $cmd_fh, '<', $cmd_file);
        while(<$cmd_fh>) {
                chomp;
                _log('INFO',$_);
        }
        close($cmd_fh);
        $pssh->push('*', cmd => { stdin_file => $cmd_file, stderr_to_stdout => 1 }, 'bash');
#       $pssh->add_host($host, key_path => $key_path, %ssh_opts);
        my ($stdout,$stderr);
        capture { $pssh->run(); } \$stdout, \$stderr;
        print $tee $stdout."\n";
        if ($pssh->get_errors) {
                print "\n[!] Errors:\n";
                foreach my $host (sort keys %hosts) {
                        if ($pssh->get_error($host)) {
                                print "[!] Failed! Host: $host Error: " . $pssh->get_error($host) . "\n";
                                _log('FAIL',"Host: $host Error: ".$pssh->get_error($host));
                        }
                }
                print "[!] ".$pssh->get_errors." error(s) occurred.\n";
                _log('INFO',$pssh->get_errors." error(s) occurred.");
        }
}
sub _log($$) {
        my ($type,$input) = @_;
        system('/usr/bin/logger', "$0 : $input");
        print $tee scalar localtime(time()) . ' - ' . $hostname . ' - [' . $type . '] ' . $input . "\n";
}
main();
