#!/usr/bin/perl
# Wake glados when a "Build" job passes

use strict;
use warnings;

use constant BUILDKITE_TOKEN => "...";
use constant HOSTNAME        => "glados.solemnwarning.net";

use JSON;
use Net::DNS;

my $token = $ENV{HTTP_X_BUILDKITE_TOKEN};

unless(defined($token) && $token eq BUILDKITE_TOKEN)
{
	print "Status: 400 Bad Request\r\n";
	print "Content-Type: text/plain\r\n";
	print "\r\n";
	print "Token missing or incorrect\n";
	
	exit(0);
}

binmode(STDIN, ":raw");
my $payload = eval { decode_json(do { local $/; <STDIN> }) };

unless(defined $payload)
{
	print "Status: 400 Bad Request\r\n";
	print "Content-Type: text/plain\r\n";
	print "\r\n";
	print "Could not parse request body\n";
	
	exit(0);
}

if($payload->{event} eq "job.finished"
	&& $payload->{job}->{name} eq "Build"
	&& $payload->{job}->{state} eq "passed")
{
	warn "Sending WOL packet to ".HOSTNAME."\n";
	
	my $res = Net::DNS::Resolver->new();
	
	my $ip  = ($res->query(HOSTNAME, "A")  ->answer())[0]->address();
	my $mac = ($res->query(HOSTNAME, "TXT")->answer())[0]->txtdata();
	
	# Run with qx to discard stdout noise
	qx(wakeonlan -i $ip $mac)
}

print "Status: 200 OK\r\n";
print "Content-Type: text/plain\r\n";
print "\r\n";
print "OK\n";
