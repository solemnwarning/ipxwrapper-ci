#!/usr/bin/perl
# Proxy Buildkite webhook events to Github commit statuses
# By Daniel Collins (2017)
# Released to public domain.

# Enable the following events when configuring the hook on Buildkite:
#
# build.scheduled
# job.started
# job.finished

use strict;
use warnings;

use constant {
	BUILDKITE_TOKEN => "...",
	
	GITHUB_API_KEY  => "...",
	
	GITHUB_REPO_OWNER => "solemnwarning",
	GITHUB_REPO_NAME  => "ipxwrapper",
};

use JSON;
use LWP::UserAgent;

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

if($payload->{event} eq "build.scheduled")
{
	my @steps = map { $_->{name} }
		grep { defined $_->{name} }
		@{ $payload->{pipeline}->{steps} };
	
	foreach my $step_desc(@steps)
	{
		gh_push_status($payload->{build}->{commit},
			context     => $step_desc,
			state       => "pending",
			description => "Pending...",
		);
	}
}
elsif($payload->{event} eq "job.started")
{
	my $commit = $payload->{build}->{commit};
	my $name   = $payload->{job}->{name};
	my $state  = $payload->{job}->{state};
	
	gh_push_status($commit,
		context     => $name,
		state       => "pending",
		description => "Running...",
		target_url  => $payload->{job}->{web_url},
	);
}
elsif($payload->{event} eq "job.finished")
{
	my $commit = $payload->{build}->{commit};
	my $name   = $payload->{job}->{name};
	my $state  = $payload->{job}->{state};
	
	my %state_map = (
		passed   => [ "success", "Passed" ],
		failed   => [ "failure", "Failed" ],
		canceled => [ "error",   "Cancelled" ],
	);
	
	gh_push_status($commit,
		context     => $name,
		state       => ($state_map{$state}->[0] // "error"),
		description => ($state_map{$state}->[1] // "Unknown state: $state"),
		target_url  => $payload->{job}->{web_url},
	);
}

print "Status: 200 OK\r\n";
print "Content-Type: text/plain\r\n";
print "\r\n";
print "OK\n";

sub gh_push_status
{
	my ($commit_sha, %status) = @_;
	
	my $ua = LWP::UserAgent->new(
		env_proxy => 1,
	);
	
	my $url  = "https://api.github.com/repos/".GITHUB_REPO_OWNER."/".GITHUB_REPO_NAME."/statuses/$commit_sha";
	my $body = encode_json(\%status);
	
	my $res = $ua->post($url,
		"Accept" => "application/vnd.github.v3+json",
		"Authorization" => "token ".GITHUB_API_KEY,
		"Content" => $body);
	
	if($res->code() != 200)
	{
		warn "POST to $url failed\n"
			."Request body: $body\n"
			."Response code: ".$res->code()."\n"
			."Response body:".$res->content();
	}
}
