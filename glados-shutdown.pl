#!/usr/bin/perl
# Shuts down machine when not in use for a period of time.
# By Daniel Collins. Released to public domain.

use strict;
use warnings;

# --- START OF CONFIGURATION --- #

# Connections to any of the ports listed here will delay the shutdown.
use constant SERVICE_PORTS  => (22);

# Number of seconds to wait before shutting down.
use constant SHUTDOWN_DELAY => 600;

# --- END OF CONFIGURATION --- #

use Proc::ProcessTable;
use Sys::Utmp;

my $last_used = time();

while(1)
{
	# Check for logged in users
	
	{
		my $utmp = Sys::Utmp->new();
		
		while(my $utent = $utmp->getutent()) 
		{
			if($utent->user_process())
			{
				$last_used = time();
				last;
			}
		}
		
		$utmp->endutent();
	}
	
	# Check for open TCP connections
	
	if(open(my $tcp, "<", "/proc/net/tcp"))
	{
		process_tcp_file($tcp);
	}
	else{
		die "Couldn't open /proc/net/tcp: $!";
	}
	
	if(open(my $tcp6, "<", "/proc/net/tcp6"))
	{
		process_tcp_file($tcp6);
	}
	
	# Check for running buildkite-agent jobs
	
	my @agent_pids;
	{
		my @processes = @{ Proc::ProcessTable->new()->table() };
		
		@agent_pids = map { $_->pid() }
			grep { $_->fname() eq "buildkite-agent" }
			@processes;
		
		my @agent_children = grep { my $ppid = $_->ppid(); grep { $ppid == $_ } @agent_pids }
			@processes;
		
		if(@agent_children)
		{
			$last_used = time();
		}
	}
	
	# Shut down?
	
	if(($last_used + SHUTDOWN_DELAY) < time())
	{
		# Time's up!
		
		# Send any buildkite-agent processes SIGTERM and wait for them
		# to shut down to ensure they don't get killed part-way through
		# a job.
		
		kill("TERM", @agent_pids);
		
		# Wait no longer than half an hour
		my $wait_until = time() + 1800;
		
		until(time() > $wait_until)
		{
			my @processes = @{ Proc::ProcessTable->new()->table() };
			
			unless(grep { $_->fname() eq "buildkite-agent" } @processes)
			{
				# All agents have exited
				last;
			}
			
			sleep(5);
		}
		
		system("shutdown", "-h", "now", "Automatic shutdown - system idle");
	}
	
	sleep(5);
}

sub process_tcp_file
{
	my ($fh) = @_;
	
	while(defined(my $line = <$fh>))
	{
		my $H = qr/[A-Z0-9]+/i;
		my ($local_port, $st) = ($line =~ m/^\s*\S+\s+$H:($H)\s+$H:$H\s+($H)/i);
		
		# Ignore lines we can't parse - should just be the headings and
		# trailing blank line.
		next unless(defined $local_port);
		
		# Ignore listen sockets.
		next if(hex($st) == 0x0A);
		
		# Convert port from hex string to an integer.
		$local_port = hex($local_port);
		
		if(grep { $local_port == $_ } SERVICE_PORTS)
		{
			$last_used = time();
		}
	}
}
