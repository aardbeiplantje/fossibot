#!/usr/bin/perl
#
# fossibot.pl - BLE connector/inspector for Fossibot F1200
#
# This script is intentionally lightweight: it establishes a BLE ATT/L2CAP
# connection to the battery and can print basic device details and GATT
# primary services.
#
# Usage:
#   ./fossibot.pl -d AA:BB:CC:DD:EE:FF --connect
#   ./fossibot.pl -d AA:BB:CC:DD:EE:FF --name
#   ./fossibot.pl -d AA:BB:CC:DD:EE:FF --services
#   ./fossibot.pl -d AA:BB:CC:DD:EE:FF --info
#

use strict;
use warnings;
use bytes;
use Getopt::Long;

my %opts = (
    device          => undef,
    addr_type       => 'public',
    connect_timeout => 6,
    mtu             => 160,
    response_timeout_ms => 2500,
    listen_sec      => 10,
    debug           => 0,
);

my ($do_connect, $do_name, $do_services, $do_info, $do_chars, $do_listen) = (0) x 6;
my ($service_uuid, $read_handle, $write_req_handle, $write_cmd_handle, $write_hex, $subscribe_handle, $notify_handle);

GetOptions(
    'device|d=s'        => \$opts{device},
    'addr-type=s'       => \$opts{addr_type},
    'connect-timeout=f' => \$opts{connect_timeout},
    'mtu=i'             => \$opts{mtu},
    'response-timeout-ms=i' => \$opts{response_timeout_ms},
    'listen-sec=f'      => \$opts{listen_sec},
    'connect'           => \$do_connect,
    'name'              => \$do_name,
    'services'          => \$do_services,
    'chars'             => \$do_chars,
    'service-uuid=s'    => \$service_uuid,
    'read-handle=s'     => \$read_handle,
    'write-req-handle=s' => \$write_req_handle,
    'write-cmd-handle=s' => \$write_cmd_handle,
    'write-hex=s'       => \$write_hex,
    'subscribe-handle=s' => \$subscribe_handle,
    'notify-handle=s'   => \$notify_handle,
    'listen'            => \$do_listen,
    'info'              => \$do_info,
    'debug|v+'          => \$opts{debug},
    'help|h'            => sub { print_usage(); exit 0; },
) or do { print_usage(); exit 1; };

unless ($opts{device}) {
    print STDERR "Error: -d / --device is required\n";
    print_usage();
    exit 1;
}
unless ($opts{device} =~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/) {
    print STDERR "Error: Invalid Bluetooth address format\n";
    exit 1;
}
if ($opts{addr_type} !~ /^(?:public|random)$/i) {
    print STDERR "Error: --addr-type must be 'public' or 'random'\n";
    exit 1;
}
if ($opts{mtu} < 23 || $opts{mtu} > 517) {
    print STDERR "Error: --mtu must be in 23..517\n";
    exit 1;
}
if ($opts{response_timeout_ms} < 100 || $opts{response_timeout_ms} > 30000) {
    print STDERR "Error: --response-timeout-ms must be in 100..30000\n";
    exit 1;
}
if ($opts{listen_sec} <= 0 || $opts{listen_sec} > 3600) {
    print STDERR "Error: --listen-sec must be >0 and <=3600\n";
    exit 1;
}

if (defined $service_uuid) {
    $service_uuid = normalize_uuid($service_uuid)
        or do { print STDERR "Error: --service-uuid must be UUID16 (e.g. fff0) or UUID128\n"; exit 1; };
}

for my $ref (\$read_handle, \$write_req_handle, \$write_cmd_handle, \$subscribe_handle, \$notify_handle) {
    next unless defined $$ref;
    my $h = parse_handle($$ref);
    defined($h)
        or do { print STDERR "Error: Handle values must be hex or decimal in range 0x0001..0xFFFF\n"; exit 1; };
    $$ref = $h;
}

if (defined $write_req_handle || defined $write_cmd_handle) {
    defined $write_hex
        or do { print STDERR "Error: --write-hex is required with --write-req-handle / --write-cmd-handle\n"; exit 1; };
}

my $write_bytes;
if (defined $write_hex) {
    $write_bytes = parse_hex_bytes($write_hex);
    defined($write_bytes)
        or do { print STDERR "Error: --write-hex must be bytes like 'AA BB 01 02' or 'AABB0102'\n"; exit 1; };
}

if (defined $write_req_handle && defined $write_cmd_handle) {
    print STDERR "Error: Use only one of --write-req-handle or --write-cmd-handle\n";
    exit 1;
}

# Default: behave like --info if no action was requested.
if (!$do_connect && !$do_name && !$do_services && !$do_info && !$do_chars && !$do_listen
    && !defined($read_handle) && !defined($write_req_handle) && !defined($write_cmd_handle)
    && !defined($subscribe_handle)) {
    $do_info = 1;
}

my $f1200 = Fossibot::F1200->new(%opts);
exit $f1200->run(
    connect  => $do_connect,
    name     => $do_name,
    services => $do_services,
    chars    => $do_chars,
    service_uuid => $service_uuid,
    read_handle => $read_handle,
    write_req_handle => $write_req_handle,
    write_cmd_handle => $write_cmd_handle,
    write_bytes => $write_bytes,
    subscribe_handle => $subscribe_handle,
    notify_handle => $notify_handle,
    listen  => $do_listen,
    info     => $do_info,
);

# ============================================================================
# Fossibot::F1200 class
# ============================================================================

package Fossibot::F1200;

use Errno  qw(EAGAIN EINPROGRESS);
use Fcntl  qw(O_NONBLOCK F_SETFL F_GETFL);
use Socket qw(SOCK_SEQPACKET SOL_SOCKET SO_ERROR);

use constant {
    AF_BLUETOOTH            => 31,
    BTPROTO_L2CAP           => 0,
    BDADDR_LE_PUBLIC        => 0x01,
    BDADDR_LE_RANDOM        => 0x02,

    ATT_ERROR_RSP           => 0x01,
    ATT_EXCHANGE_MTU_REQ    => 0x02,
    ATT_EXCHANGE_MTU_RSP    => 0x03,
    ATT_READ_REQ            => 0x0A,
    ATT_READ_RSP            => 0x0B,
    ATT_READ_BY_TYPE_REQ    => 0x08,
    ATT_READ_BY_TYPE_RSP    => 0x09,
    ATT_READ_BY_GROUP_REQ   => 0x10,
    ATT_READ_BY_GROUP_RSP   => 0x11,
    ATT_WRITE_REQ           => 0x12,
    ATT_WRITE_RSP           => 0x13,
    ATT_HANDLE_VALUE_NOTIF  => 0x1B,
    ATT_WRITE_CMD           => 0x52,

    GATT_PRIMARY_SERVICE    => 0x2800,
    GATT_CHARACTERISTIC     => 0x2803,
    GATT_DEVICE_NAME        => 0x2A00,
};

sub new {
    my ($class, %o) = @_;
    bless {
        device          => $o{device},
        addr_type       => lc($o{addr_type} // 'public'),
        connect_timeout => $o{connect_timeout} // 6,
        mtu             => $o{mtu} // 160,
        response_timeout => ($o{response_timeout_ms} // 2500) / 1000.0,
        listen_sec      => $o{listen_sec} // 10,
        debug           => $o{debug} // 0,
        socket          => undef,
    }, $class;
}

sub run {
    my ($self, %todo) = @_;

    print "Fossibot F1200 BLE Tool\n";
    print "=======================\n\n";
    print "Device: $self->{device}\n";

    unless ($self->ble_connect()) {
        print STDERR "ERROR: BLE connection failed\n";
        return 1;
    }

    print "Connected:    yes\n";

    my $mtu = $self->exchange_mtu($self->{mtu});
    if (defined $mtu) {
        print "ATT MTU:      $mtu\n";
    }

    if ($todo{info} || $todo{name}) {
        my $name = $self->read_ble_device_name();
        if (defined $name && length $name) {
            print "Name:         $name\n";
        } else {
            print "Name:         (not available)\n";
        }
    }

    if ($todo{info} || $todo{services}) {
        my $services = $self->discover_primary_services();
        if (defined $services && @$services) {
            print "Services:\n";
            for my $svc (@$services) {
                printf "  - %s  [0x%04X..0x%04X]\n", $svc->{uuid}, $svc->{start}, $svc->{end};
            }
        } else {
            print "Services:     (none discovered)\n";
        }
    }

    if ($todo{chars}) {
        my $chars = $self->discover_characteristics($todo{service_uuid});
        if (defined $chars && @$chars) {
            print "Characteristics:\n";
            for my $c (@$chars) {
                printf "  - svc=%s decl=0x%04X value=0x%04X props=0x%02X uuid=%s\n",
                    $c->{service_uuid}, $c->{decl_handle}, $c->{value_handle}, $c->{properties}, $c->{uuid};
            }
        } else {
            print "Characteristics: (none discovered)\n";
        }
    }

    if (defined $todo{read_handle}) {
        my $v = $self->att_read_handle($todo{read_handle});
        if (defined $v) {
            printf "Read 0x%04X:  %s\n", $todo{read_handle}, hex_bytes($v);
        } else {
            printf STDERR "ERROR: Read failed for handle 0x%04X\n", $todo{read_handle};
        }
    }

    if (defined $todo{write_req_handle}) {
        my $ok = $self->att_write_req_handle($todo{write_req_handle}, @{$todo{write_bytes}});
        if ($ok) {
            printf "Write req 0x%04X: %s\n", $todo{write_req_handle}, hex_bytes($todo{write_bytes});
        } else {
            printf STDERR "ERROR: Write request failed for handle 0x%04X\n", $todo{write_req_handle};
        }
    }

    if (defined $todo{write_cmd_handle}) {
        my $ok = $self->att_write_cmd_handle($todo{write_cmd_handle}, @{$todo{write_bytes}});
        if ($ok) {
            printf "Write cmd 0x%04X: %s\n", $todo{write_cmd_handle}, hex_bytes($todo{write_bytes});
        } else {
            printf STDERR "ERROR: Write command failed for handle 0x%04X\n", $todo{write_cmd_handle};
        }
    }

    if (defined $todo{subscribe_handle}) {
        my $cccd = $todo{subscribe_handle} + 1;
        my $ok = $self->att_write_req_handle($cccd, 0x01, 0x00);
        if ($ok) {
            printf "Subscribed:   value=0x%04X cccd=0x%04X\n", $todo{subscribe_handle}, $cccd;
        } else {
            printf STDERR "ERROR: Subscribe failed for value handle 0x%04X (cccd 0x%04X)\n", $todo{subscribe_handle}, $cccd;
        }
    }

    if ($todo{listen}) {
        my $target = defined $todo{notify_handle} ? sprintf('0x%04X', $todo{notify_handle}) : 'any';
        print "Listening:    handle=$target for $self->{listen_sec}s\n";
        $self->listen_notifications($self->{listen_sec}, $todo{notify_handle});
    }

    $self->ble_disconnect();
    return 0;
}

sub ble_connect {
    my ($self) = @_;
    my @oct    = split(':', $self->{device});
    my $bdaddr = pack('C6', map { hex($_) } reverse @oct);
    my $atype  = ($self->{addr_type} eq 'random') ? BDADDR_LE_RANDOM : BDADDR_LE_PUBLIC;

    socket(my $sock, AF_BLUETOOTH, SOCK_SEQPACKET, BTPROTO_L2CAP) or return 0;

    bind($sock, pack('S S a6 S S', AF_BLUETOOTH, 0, "\0" x 6, 4, BDADDR_LE_PUBLIC))
        or do { close($sock); return 0; };

    my $peer = pack('S S a6 S S', AF_BLUETOOTH, 0, $bdaddr, 4, $atype);
    fcntl($sock, F_SETFL, fcntl($sock, F_GETFL, 0) | O_NONBLOCK);

    my $connected = connect($sock, $peer);
    if (!$connected && !($! == EINPROGRESS || $! == EAGAIN)) {
        $self->debug("connect() immediate fail: $!");
        close($sock);
        return 0;
    }

    unless ($connected) {
        my $deadline = time() + ($self->{connect_timeout} > 0 ? $self->{connect_timeout} : 6);
        my $done = 0;
        while (time() < $deadline) {
            my $fh = fileno($sock);
            my $wvec = '';
            vec($wvec, $fh, 1) = 1;
            my $n = select(undef, $wvec, my $evec = $wvec, 0.5);
            next unless defined($n) && $n > 0;
            my $err = getsockopt($sock, SOL_SOCKET, SO_ERROR);
            my $eno = $err ? unpack('I', $err) : 0;
            if (!$eno)                                { $done = 1; last; }
            next if $eno == EINPROGRESS || $eno == EAGAIN;
            last;
        }
        unless ($done) {
            $self->debug('connect timeout');
            close($sock);
            return 0;
        }
    }

    my $err = getsockopt($sock, SOL_SOCKET, SO_ERROR);
    if ($err && unpack('I', $err)) {
        close($sock);
        return 0;
    }

    fcntl($sock, F_SETFL, fcntl($sock, F_GETFL, 0) & ~O_NONBLOCK);
    $self->{socket} = $sock;
    return 1;
}

sub ble_disconnect {
    my ($self) = @_;
    if ($self->{socket}) {
        close($self->{socket});
        $self->{socket} = undef;
    }
}

sub att_request {
    my ($self, $req, $timeout) = @_;
    $timeout //= 2.0;
    return unless $self->{socket};

    syswrite($self->{socket}, $req) or return;

    my $rin = '';
    vec($rin, fileno($self->{socket}), 1) = 1;
    my $n = select(my $rout = $rin, undef, undef, $timeout);
    return unless defined($n) && $n > 0;

    my ($rsp, $r) = ('');
    $r = sysread($self->{socket}, $rsp, 512);
    return unless defined($r) && $r > 0;
    return $rsp;
}

sub exchange_mtu {
    my ($self, $client_mtu) = @_;
    my $rsp = $self->att_request(pack('C S<', ATT_EXCHANGE_MTU_REQ, $client_mtu), 2.0);
    return undef unless defined $rsp && length($rsp) >= 3;
    return undef unless ord(substr($rsp, 0, 1)) == ATT_EXCHANGE_MTU_RSP;

    my $server_mtu = unpack('S<', substr($rsp, 1, 2));
    my $effective  = $client_mtu < $server_mtu ? $client_mtu : $server_mtu;
    $self->debug("MTU negotiated: client=$client_mtu server=$server_mtu effective=$effective");
    return $effective;
}

sub read_ble_device_name {
    my ($self) = @_;
    my $rsp = $self->att_request(
        pack('C S< S< S<', ATT_READ_BY_TYPE_REQ, 0x0001, 0xFFFF, GATT_DEVICE_NAME),
        2.0
    );

    return undef unless defined $rsp && length($rsp) >= 5;
    return undef unless ord(substr($rsp, 0, 1)) == ATT_READ_BY_TYPE_RSP;

    my $name = substr($rsp, 4);
    $name =~ s/\x00.*//s;
    return $name;
}

sub discover_primary_services {
    my ($self) = @_;
    my @services;
    my $start = 0x0001;

    while ($start <= 0xFFFF) {
        my $rsp = $self->att_request(
            pack('C S< S< S<', ATT_READ_BY_GROUP_REQ, $start, 0xFFFF, GATT_PRIMARY_SERVICE),
            2.0
        );

        last unless defined $rsp && length($rsp) >= 1;

        my $op = ord(substr($rsp, 0, 1));
        if ($op == ATT_ERROR_RSP) {
            # Most devices reply with Attribute Not Found once enumeration ends.
            last;
        }
        last unless $op == ATT_READ_BY_GROUP_RSP;
        last unless length($rsp) >= 2;

        my $entry_len = ord(substr($rsp, 1, 1));
        last if $entry_len < 6;

        my $pos = 2;
        my $last_end = 0;
        while ($pos + $entry_len <= length($rsp)) {
            my $entry = substr($rsp, $pos, $entry_len);
            my ($h_start, $h_end) = unpack('S< S<', substr($entry, 0, 4));
            my $uuid_raw = substr($entry, 4);
            my $uuid = format_uuid($uuid_raw);

            push @services, {
                start => $h_start,
                end   => $h_end,
                uuid  => $uuid,
            };

            $last_end = $h_end;
            $pos += $entry_len;
        }

        last if !$last_end || $last_end == 0xFFFF;
        $start = $last_end + 1;
    }

    return \@services;
}

sub discover_characteristics {
    my ($self, $wanted_service_uuid) = @_;
    my $services = $self->discover_primary_services();
    return [] unless defined $services && @$services;

    my @chars;
    for my $svc (@$services) {
        if (defined $wanted_service_uuid && lc($svc->{uuid}) ne lc($wanted_service_uuid)) {
            next;
        }

        my $start = $svc->{start};
        while ($start <= $svc->{end}) {
            my $rsp = $self->att_request(
                pack('C S< S< S<', ATT_READ_BY_TYPE_REQ, $start, $svc->{end}, GATT_CHARACTERISTIC),
                $self->{response_timeout}
            );
            last unless defined $rsp && length($rsp) >= 2;
            last unless ord(substr($rsp, 0, 1)) == ATT_READ_BY_TYPE_RSP;

            my $entry_len = ord(substr($rsp, 1, 1));
            last if $entry_len < 7;

            my $pos = 2;
            my $last_decl = 0;
            while ($pos + $entry_len <= length($rsp)) {
                my $e = substr($rsp, $pos, $entry_len);
                my $decl = unpack('S<', substr($e, 0, 2));
                my $props = ord(substr($e, 2, 1));
                my $val = unpack('S<', substr($e, 3, 2));
                my $uuid_raw = substr($e, 5);

                push @chars, {
                    service_uuid => $svc->{uuid},
                    decl_handle  => $decl,
                    value_handle => $val,
                    properties   => $props,
                    uuid         => format_uuid($uuid_raw),
                };

                $last_decl = $decl;
                $pos += $entry_len;
            }

            last if !$last_decl;
            $start = $last_decl + 1;
        }
    }

    return \@chars;
}

sub att_read_handle {
    my ($self, $handle) = @_;
    my $rsp = $self->att_request(pack('C S<', ATT_READ_REQ, $handle), $self->{response_timeout});
    return undef unless defined $rsp && length($rsp) >= 1;
    return undef unless ord(substr($rsp, 0, 1)) == ATT_READ_RSP;
    return [unpack('C*', substr($rsp, 1))];
}

sub att_write_req_handle {
    my ($self, $handle, @bytes) = @_;
    my $rsp = $self->att_request(pack('C S< C*', ATT_WRITE_REQ, $handle, @bytes), $self->{response_timeout});
    return defined($rsp) && length($rsp) >= 1 && ord(substr($rsp, 0, 1)) == ATT_WRITE_RSP;
}

sub att_write_cmd_handle {
    my ($self, $handle, @bytes) = @_;
    return 0 unless $self->{socket};
    return syswrite($self->{socket}, pack('C S< C*', ATT_WRITE_CMD, $handle, @bytes)) ? 1 : 0;
}

sub read_notification {
    my ($self, $timeout, $expected_handle) = @_;
    return undef unless $self->{socket};

    my $rin = '';
    vec($rin, fileno($self->{socket}), 1) = 1;
    my $n = select(my $rout = $rin, undef, undef, $timeout);
    return undef unless defined($n) && $n > 0;

    my ($raw, $r) = ('');
    $r = sysread($self->{socket}, $raw, 512);
    return undef unless defined($r) && $r > 0;

    return undef unless length($raw) >= 3;
    return undef unless ord(substr($raw, 0, 1)) == ATT_HANDLE_VALUE_NOTIF;

    my $handle = unpack('S<', substr($raw, 1, 2));
    return undef if defined $expected_handle && $handle != $expected_handle;

    my @value = unpack('C*', substr($raw, 3));
    return {
        handle => $handle,
        value  => \@value,
    };
}

sub listen_notifications {
    my ($self, $seconds, $expected_handle) = @_;
    my $deadline = time() + $seconds;

    while (time() < $deadline) {
        my $left = $deadline - time();
        my $notif = $self->read_notification($left < 1 ? $left : 1, $expected_handle);
        next unless $notif;
        printf "Notify 0x%04X: %s\n", $notif->{handle}, hex_bytes($notif->{value});
    }
}

sub format_uuid {
    my ($raw) = @_;
    if (length($raw) == 2) {
        return sprintf('0x%04X', unpack('S<', $raw));
    }
    if (length($raw) == 16) {
        my @b = unpack('C*', $raw);
        my @be = reverse @b;
        return sprintf(
            '%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x',
            @be
        );
    }
    return '0x' . uc(unpack('H*', $raw));
}

sub debug {
    my ($self, $msg) = @_;
    print "  [DEBUG] $msg\n" if $self->{debug};
}

sub hex_bytes {
    my ($bytes) = @_;
    return join(' ', map { sprintf('%02X', $_) } @$bytes);
}

1;

# ============================================================================
# Main package helpers
# ============================================================================

package main;

sub parse_handle {
    my ($s) = @_;
    return undef unless defined $s;
    $s =~ s/^\s+|\s+$//g;
    my $n;
    if ($s =~ /^0x([0-9A-Fa-f]{1,4})$/) {
        $n = hex($1);
    } elsif ($s =~ /^([0-9]{1,5})$/) {
        $n = int($1);
    } else {
        return undef;
    }
    return ($n >= 1 && $n <= 0xFFFF) ? $n : undef;
}

sub parse_hex_bytes {
    my ($s) = @_;
    return undef unless defined $s;
    $s =~ s/^\s+|\s+$//g;
    return [] if $s eq '';

    my $norm = $s;
    $norm =~ s/0x//gi;
    $norm =~ s/[^0-9A-Fa-f]//g;
    return undef if length($norm) == 0 || (length($norm) % 2);

    my @bytes = map { hex($_) } ($norm =~ /(..)/g);
    return \@bytes;
}

sub normalize_uuid {
    my ($u) = @_;
    return undef unless defined $u;
    $u = lc($u);
    $u =~ s/^0x//;
    if ($u =~ /^[0-9a-f]{4}$/) {
        return sprintf('0x%04X', hex($u));
    }
    if ($u =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/) {
        return $u;
    }
    return undef;
}

sub print_usage {
    print <<"EOF";
Usage: $0 -d AA:BB:CC:DD:EE:FF [actions] [options]

Actions (defaults to --info):
  --connect       Connect test only
  --name          Read BLE Device Name (GATT 0x2A00)
  --services      Enumerate GATT primary services
    --chars         Enumerate characteristics (all services or --service-uuid)
    --read-handle H Read a value from attribute handle H
    --write-req-handle H --write-hex BYTES  Write with ATT Write Request
    --write-cmd-handle H --write-hex BYTES  Write with ATT Write Command
    --subscribe-handle H    Enable notify on H by writing 0x0001 to H+1 (CCCD)
    --listen        Print notifications for --listen-sec seconds
    --notify-handle H       Filter --listen to notifications from handle H
  --info          Connect + name + services summary

Required:
  -d, --device ADDR       BLE MAC address of the F1200

Options:
  --addr-type TYPE        public|random (default: public)
  --connect-timeout SEC   Connect timeout in seconds (default: 6)
  --mtu N                 ATT MTU request size (23..517, default: 160)
    --service-uuid UUID     Filter --chars to one service UUID
    --response-timeout-ms N Timeout for ATT req/rsp operations (default: 2500)
    --listen-sec SEC        Notification listen duration (default: 10)
    --write-hex BYTES       Hex bytes e.g. "AA BB 01 02" or "AABB0102"
  -v, --debug             Verbose output
  -h, --help              Show this help

Examples:
  $0 -d AA:BB:CC:DD:EE:FF --connect
  $0 -d AA:BB:CC:DD:EE:FF --name
  $0 -d AA:BB:CC:DD:EE:FF --services
    $0 -d AA:BB:CC:DD:EE:FF --chars --service-uuid fff0
    $0 -d AA:BB:CC:DD:EE:FF --read-handle 0x0025
    $0 -d AA:BB:CC:DD:EE:FF --write-req-handle 0x0028 --write-hex "01 00"
    $0 -d AA:BB:CC:DD:EE:FF --subscribe-handle 0x0028 --listen --listen-sec 20
  $0 -d AA:BB:CC:DD:EE:FF --info -v
EOF
}
