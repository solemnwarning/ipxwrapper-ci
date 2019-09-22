#!/usr/bin/perl
# Configure a pool of vboxnet adapters and DHCP servers for ipxtester use
# By Daniel Collins (2019)
# Released to public domain

use strict;
use warnings;

use IPC::Run qw(run);
use NetAddr::IP;

if((scalar @ARGV) != 2)
{
	die "Usage: $0 <number of interfaces> <subnet>\n";
}

my ($n_interfaces, $subnet_string) = @ARGV;

my $net = NetAddr::IP->new($subnet_string) or die "Invalid subnet: $subnet_string\n";

die "Subnet must be IPv4\n" unless($net->version() == 4);
die "Subnet is not a subnet, did you mean ".$net->network()."?\n" unless($net == $net->network());

die "Not enough IPs in $subnet_string, provide a bigger subnet\n" unless($net->masklen() <= 30);

# Allocate a /30 subnet for each interface from the full subnet.

my @interfaces = ();

{
	my $subnet = NetAddr::IP->new($net->addr()."/30") or die;
	
	do
	{
		push(@interfaces, {
			host_ip  => $subnet->first()->addr(),
			guest_ip => $subnet->last()->addr(),
			netmask  => $subnet->mask(),
		});
		
		my $next_net = NetAddr::IP->new($subnet->broadcast()->addr()."/".$net->masklen()) + 1;
		$subnet = NetAddr::IP->new($next_net->addr()."/30");
	} while((scalar @interfaces) < $n_interfaces && $subnet->addr() ne $net->addr());
	
	if((scalar @interfaces) < $n_interfaces)
	{
		die "Not enough IPs in $subnet_string, provide a bigger subnet\n";
	}
}

# Configure the interfaces and DHCP server

foreach my $interface(@interfaces)
{
	my $create_output = VBoxManage("hostonlyif", "create");
	
	my ($ifname) = ($create_output =~ m/'(vboxnet\d+)'/);
	unless(defined($ifname))
	{
		cleanup();
		die "Unexpected output from `VBoxManage hostonlyif create` command:\n$create_output";
	}
	
	$interface->{name} = $ifname;
	
	VBoxManage("hostonlyif", "ipconfig", $ifname,
		"--ip"      => $interface->{host_ip},
		"--netmask" => $interface->{netmask});
	
	VBoxManage("dhcpserver", "add",
		"--ifname"  => $ifname,
		"--ip"      => $interface->{host_ip},
		"--netmask" => $interface->{netmask},
		"--lowerip" => $interface->{guest_ip},
		"--upperip" => $interface->{guest_ip},
		"--enable");
	
	print "$ifname = ", $interface->{guest_ip}, "\n\n";
}

sub VBoxManage
{
	my (@args) = @_;
	
	print "; VBoxManage ", join(" ", @args), "\n";
	
	my $output = "";
	unless(run([ "VBoxManage", @args ], ">&" => \$output))
	{
		cleanup();
		die $output;
	}
	
	return $output;
}

sub cleanup
{
	# Destroy any interfaces or DHCP servers we made.
	
	foreach my $interface(@interfaces)
	{
		# Skip interfaces which never got as far as being created.
		next unless(defined $interface->{name});
		
		run([ "VBoxManage", "dhcpserver", "remove", "--ifname" => $interface->{name} ],
			">&" => "/dev/null");
		
		run([ "VBoxManage", "hostonlyif", "remove", $interface->{name} ],
			">&" => "/dev/null");
	}
}
