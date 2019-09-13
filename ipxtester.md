# Introduction

This document lists the steps to setup `ipxtester` and prepare its VM images.

# Generate an SSH keypair

An SSH keypair is needed to authenticate SSH connections to VMs in the test
environment. The secrecy of this key is unimportant as the test hosts are not
exposed to the network.

    ssh-keygen -t rsa -b 1024 -f ipxtest.rsa -N '' -C 'ipxtest insecure key'

This will produce `ipxtest.rsa` containing the private key and `ipxtest.rsa.pub`
containing the public key.

# Setting up user account

I recommend running `ipxtester` under a dedicated user account to simplify
configuration.

Create the user account (named `ipxtest` in this document) whose home directory
is on a btrfs filesystem and copy the `ipxtester` script to it.

Copy the insecure private key to `~ipxtest/.ssh/id_rsa` and place the following
in `~ipxtest/.ssh/config`:

    User ipxtest
    
    StrictHostKeyChecking no
    UserKnownHostsFile    /dev/null
    LogLevel              ERROR

You must run `ipxtester init` each time the system is booted before running
tests, easy way to do this is add something like the following to the ipxtest
user's crontab:

    @reboot /mnt/vmstore/ipxtest/ipxtester init

# Setting up network interfaces

`ipxtester` uses a number of dedicated host-only adapters to communicate with
the virtual machines it creates. Each network needs a DHCP server which assigns
a fixed IP to the VM.

The adapters and the IP addresses that will be assigned to the VMs should be
listed in `ipxtester.ini` like so:

    vboxnet4 = 192.168.99.2
    vboxnet5 = 192.168.99.6
    vboxnet6 = 192.168.99.10
    vboxnet7 = 192.168.99.14

The `make-interfaces.pl` script is provided to set up a pool of interfaces and
their associated DHCP servers. The script's output can be pasted into your
`ipxwrapper.ini` file.

    $ ./make-interfaces.pl 4 192.168.99.0/24
    ; VBoxManage hostonlyif create
    ; VBoxManage hostonlyif ipconfig vboxnet4 --ip 192.168.99.1 --netmask 255.255.255.252
    ; VBoxManage dhcpserver add --ifname vboxnet4 --ip 192.168.99.1 --netmask 255.255.255.252 --lowerip 192.168.99.2 --upperip 192.168.99.2 --enable
    vboxnet4 = 192.168.99.2
    
    ; VBoxManage hostonlyif create
    ; VBoxManage hostonlyif ipconfig vboxnet5 --ip 192.168.99.5 --netmask 255.255.255.252
    ; VBoxManage dhcpserver add --ifname vboxnet5 --ip 192.168.99.5 --netmask 255.255.255.252 --lowerip 192.168.99.6 --upperip 192.168.99.6 --enable
    vboxnet5 = 192.168.99.6
    
    ; VBoxManage hostonlyif create
    ; VBoxManage hostonlyif ipconfig vboxnet6 --ip 192.168.99.9 --netmask 255.255.255.252
    ; VBoxManage dhcpserver add --ifname vboxnet6 --ip 192.168.99.9 --netmask 255.255.255.252 --lowerip 192.168.99.10 --upperip 192.168.99.10 --enable
    vboxnet6 = 192.168.99.10
    
    ; VBoxManage hostonlyif create
    ; VBoxManage hostonlyif ipconfig vboxnet7 --ip 192.168.99.13 --netmask 255.255.255.252
    ; VBoxManage dhcpserver add --ifname vboxnet7 --ip 192.168.99.13 --netmask 255.255.255.252 --lowerip 192.168.99.14 --upperip 192.168.99.14 --enable
    vboxnet7 = 192.168.99.14

Make sure the subnet you use doesn't conflict with one used on your network or
the ones used by the test suite (172.16.1.0/24 and 172.16.2.0/24).

# Preparing the "director" Virtual Machine

The director VM is the Linux part of the test environment. It is where the
build tree is copied to and the test scripts are run.

Create a Linux VM in VirtualBox with the following network adapters:

    Adapter 1: NAT,          MAC address: 0800274155B4
    Adapter 2: Not attached, MAC address: 080027525F9E
    Adapter 3: Not attached, MAC address: 080027F5BE4C

All adapters should be of type "Intel PRO/1000 MT Desktop (82540EM)".

Install a Linux distribution on it, at this time Debian wheezy is known to work
fully with the test environment.

Configure the network interfaces under Linux with the following IP addresses:

    Adapter 1 (eth0): DHCP
    Adapter 2 (eth1): 172.16.1.11/24 (255.255.255.0)
    Adapter 3 (eth2): 172.16.2.11/24 (255.255.255.0)

Install the following Perl modules:

 * IPC::Run
 * Net::Libdnet::Eth
 * Net::Pcap
 * NetPacket
 * Test::Spec

Put the following in root's SSH configuration file (~root/.ssh/config):

    User ipxtest
    
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    
    ControlMaster  auto
    ControlPath    /tmp/ssh.%r@%h:%p
    ControlPersist 5m

Copy the insecure private key to `~root/.ssh/id_rsa` and the public key to
`~root/.ssh/authorized_keys`.

Create a directory named /srv/ipxwrapper/ and install Samba with the following
`/etc/smb.conf`:

    [global]
      workgroup     = WORKGROUP
      wins support  = no
      dns proxy     = no
      syslog        = 3
      security      = user
      guest account = nobody
      map to guest  = bad user
    
    [ipxwrapper]
      path       = /srv/ipxwrapper/
      guest ok   = yes
      guest only = yes
      read only  = yes

# Preparing the Windows Virtual Machines

I/O APIC: Disable during 32-bit installation.
Audio: Disabled

Network adapters

All network adapters should be of type "Intel PRO/1000 MT Desktop (8254EM)".
Windows XP will need the driver installing seperately.

    main:
      NIC 1: Not attached, 080027C36AE6, 172.16.1.21
      NIC 2: Not attached, 08002743475C, 172.16.2.21
      NIC 4: NAT,          080027DBD7F3
    
    dp1:
      NIC 1: Not attached, 08002748276B, 172.16.1.22
      NIC 4: NAT,          080027F3DAA6
    
    dp2:
      NIC 1: Not attached, 08002771C850, 172.16.1.23
      NIC 4: NAT,          080027FDAAED

Windows VM setup steps

1) Install Windows
2) Create non-Administrator "ipxtest" user
3) Disable Windows Firewall
4) Install Bitvise SSH
4a) Allow logins to ipxtest (or Everyone) using insecure key
4b) Map \\172.16.1.11\IPXWrapper to Z: (need to some creds under Windows 10)
5) Install WinPcap
6) Enable DirectPlay (Windows 8 onwards)
7) Install DirectPlay IPX registry key (Windows Vista onwards)
