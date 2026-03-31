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
    f1200_interval_ms => 1000,
    debug           => 0,
);

my ($do_connect, $do_name, $do_services, $do_info, $do_chars, $do_listen) = (0) x 6;
my ($service_uuid, $read_handle, $write_req_handle, $write_cmd_handle, $write_hex, $subscribe_handle, $notify_handle);
my ($do_f1200_poll, $do_f1200_stream, $do_f1200_diff) = (0, 0, 0);
my $f1200_raw = 0;
my $f1200_diff_csv;

GetOptions(
    'device|d=s'        => \$opts{device},
    'addr-type=s'       => \$opts{addr_type},
    'connect-timeout=f' => \$opts{connect_timeout},
    'mtu=i'             => \$opts{mtu},
    'response-timeout-ms=i' => \$opts{response_timeout_ms},
    'listen-sec=f'      => \$opts{listen_sec},
    'f1200-interval-ms=i' => \$opts{f1200_interval_ms},
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
    'f1200-poll'        => \$do_f1200_poll,
    'f1200-stream'      => \$do_f1200_stream,
    'f1200-diff'        => \$do_f1200_diff,
    'f1200-raw'         => \$f1200_raw,
    'f1200-diff-csv=s'  => \$f1200_diff_csv,
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
if (defined($opts{f1200_interval_ms}) && ($opts{f1200_interval_ms} < 100 || $opts{f1200_interval_ms} > 10000)) {
    print STDERR "Error: --f1200-interval-ms must be in 100..10000\n";
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
    && !$do_f1200_poll && !$do_f1200_stream && !$do_f1200_diff
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
    f1200_poll => $do_f1200_poll,
    f1200_stream => $do_f1200_stream,
    f1200_diff => $do_f1200_diff,
    f1200_raw => $f1200_raw,
    f1200_diff_csv => $f1200_diff_csv,
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

    # Inferred from provided F1200 capture
    F1200_SERVICE_UUID      => 0xA002,
    F1200_WRITE_HANDLE      => 0x0036,
    F1200_NOTIFY_HANDLE     => 0x0038,
    F1200_CCCD_HANDLE       => 0x0039,
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
        f1200_interval_sec => ($o{f1200_interval_ms} // 1000) / 1000.0,
        f1200_raw       => $o{f1200_raw} ? 1 : 0,
        f1200_diff_csv  => $o{f1200_diff_csv},
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

    if ($todo{f1200_poll}) {
        my $ok = $self->f1200_enable_notifications();
        if (!$ok) {
            print STDERR "ERROR: F1200 poll setup failed (CCCD write)\n";
        } else {
            my $rsp = $self->f1200_request_status();
            if ($rsp) {
                printf "F1200 poll rsp (0x%04X)\n", $rsp->{handle};
                if (defined $rsp->{expected_len} && !$rsp->{complete}) {
                    printf "Note:         partial frame (%d/%d bytes), waiting window may be too short\n",
                        scalar(@{$rsp->{value}}), $rsp->{expected_len};
                }
                $self->print_f1200_decoded($rsp->{value});
                printf "Raw:          %s\n", hex_bytes($rsp->{value}) if $self->{f1200_raw};
            } else {
                print STDERR "ERROR: F1200 poll timed out waiting for notification\n";
            }
        }
    }

    if ($todo{f1200_stream}) {
        my $ok = $self->f1200_enable_notifications();
        if (!$ok) {
            print STDERR "ERROR: F1200 stream setup failed (CCCD write)\n";
        } else {
            my $end = time() + $self->{listen_sec};
            print "F1200 stream: polling and waiting for notifications\n";
            while (time() < $end) {
                my $rsp = $self->f1200_request_status();
                if ($rsp) {
                    printf "F1200 notify (0x%04X)\n", $rsp->{handle};
                    if (defined $rsp->{expected_len} && !$rsp->{complete}) {
                        printf "Note:         partial frame (%d/%d bytes)\n",
                            scalar(@{$rsp->{value}}), $rsp->{expected_len};
                    }
                    $self->print_f1200_decoded($rsp->{value});
                    printf "Raw:          %s\n", hex_bytes($rsp->{value}) if $self->{f1200_raw};
                }
                select(undef, undef, undef, 0.2);
            }
        }
    }

    if ($todo{f1200_diff}) {
        my $ok = $self->f1200_enable_notifications();
        if (!$ok) {
            print STDERR "ERROR: F1200 diff setup failed (CCCD write)\n";
        } else {
            my $csvfh;
            if (defined $self->{f1200_diff_csv} && length $self->{f1200_diff_csv}) {
                if (open($csvfh, '>', $self->{f1200_diff_csv})) {
                    print $csvfh "epoch,reg_hex,old_hex,new_hex,old_dec,new_dec\n";
                    print "Diff CSV:      $self->{f1200_diff_csv}\n";
                } else {
                    print STDERR "ERROR: cannot open diff csv '$self->{f1200_diff_csv}' for writing\n";
                }
            }

            my $end = time() + $self->{listen_sec};
            my $prev;
            print "F1200 diff:   tracking changed registers\n";
            while (time() < $end) {
                my $rsp = $self->f1200_request_status();
                if ($rsp) {
                    my $snap = $self->extract_modbus_register_snapshot($rsp->{value});
                    if ($snap && $prev) {
                        my $changes = $self->diff_register_snapshots($prev, $snap);
                        if (@$changes) {
                            my $ts = time();
                            print "Changes:\n";
                            for my $c (@$changes) {
                                my $extra = $self->f1200_register_pretty($c->{reg}, $c->{new});
                                printf "  [0x%04X] %04X -> %04X (%d -> %d)\n",
                                    $c->{reg}, $c->{old}, $c->{new}, $c->{old}, $c->{new};
                                print "           $extra\n" if defined($extra) && length($extra);
                                if ($csvfh) {
                                    printf $csvfh "%d,0x%04X,%04X,%04X,%d,%d\n",
                                        $ts, $c->{reg}, $c->{old}, $c->{new}, $c->{old}, $c->{new};
                                }
                            }
                        }
                    }
                    $prev = $snap if $snap;
                }
                select(undef, undef, undef, $self->{f1200_interval_sec});
            }
            close($csvfh) if $csvfh;
        }
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

sub f1200_enable_notifications {
    my ($self) = @_;
    return $self->att_write_req_handle(F1200_CCCD_HANDLE, 0x01, 0x00);
}

sub f1200_send_poll {
    my ($self) = @_;
    # Seen repeatedly in capture as status request payload to handle 0x0036.
    return $self->att_write_req_handle(F1200_WRITE_HANDLE, 0x11, 0x04, 0x00, 0x00, 0x00, 0x50, 0xA6, 0xF2);
}

sub f1200_expected_frame_len {
    my ($self, $bytes) = @_;
    return undef unless defined $bytes && @$bytes >= 2;

    my $addr = $bytes->[0];
    my $func = $bytes->[1];
    return undef unless $addr == 0x11;

    if ($func == 0x06) {
        return 8;
    }

    if ($func == 0x04 && @$bytes >= 6) {
        my $count = f1200_u16_be($bytes, 4);
        return 6 + ($count * 2) + 2;
    }

    return undef;
}

sub f1200_request_status {
    my ($self) = @_;
    return undef unless $self->f1200_send_poll();

    my $first = $self->read_notification($self->{response_timeout}, F1200_NOTIFY_HANDLE);
    return undef unless $first;

    my @buf = @{$first->{value}};
    my $expected = $self->f1200_expected_frame_len(\@buf);

    my $deadline = time() + $self->{response_timeout};
    while (defined $expected && scalar(@buf) < $expected && time() < $deadline) {
        my $left = $deadline - time();
        last if $left <= 0;

        my $next = $self->read_notification($left < 0.5 ? $left : 0.5, F1200_NOTIFY_HANDLE);
        last unless $next;

        push @buf, @{$next->{value}};
    }

    if (defined $expected && scalar(@buf) > $expected) {
        splice @buf, $expected;
    }

    return {
        handle => $first->{handle},
        value  => \@buf,
        expected_len => $expected,
        complete => (defined($expected) ? (scalar(@buf) == $expected ? 1 : 0) : 1),
    };
}

sub f1200_u16_be {
    my ($bytes, $off) = @_;
    return undef if !defined($bytes) || $off < 0 || $off + 1 > $#$bytes;
    return (($bytes->[$off] << 8) | $bytes->[$off + 1]);
}

sub f1200_u16_le {
    my ($bytes, $off) = @_;
    return undef if !defined($bytes) || $off < 0 || $off + 1 > $#$bytes;
    return ($bytes->[$off] | ($bytes->[$off + 1] << 8));
}

sub modbus_crc16 {
    my ($bytes) = @_;
    my $crc = 0xFFFF;
    for my $b (@$bytes) {
        $crc ^= ($b & 0xFF);
        for (1..8) {
            if ($crc & 0x0001) {
                $crc = (($crc >> 1) ^ 0xA001) & 0xFFFF;
            } else {
                $crc = ($crc >> 1) & 0xFFFF;
            }
        }
    }
    return $crc;
}

sub swap16 {
    my ($v) = @_;
    return (($v & 0x00FF) << 8) | (($v & 0xFF00) >> 8);
}

sub decode_f1200_payload {
    my ($self, $bytes) = @_;
    return { kind => 'empty' } unless defined $bytes && @$bytes;

    my $len = scalar(@$bytes);
    my $addr = $bytes->[0] // 0;
    my $func = $bytes->[1] // 0;

    my $d = {
        kind => 'modbus-rtu-over-ble',
        len  => $len,
        slave => $addr,
        function => $func,
    };

    if ($len >= 4) {
        my @body = @$bytes[0 .. $len - 3];
        $d->{crc16_rx_le} = f1200_u16_le($bytes, $len - 2);
        $d->{crc16_calc_modbus} = modbus_crc16(\@body);
        $d->{crc16_calc_le} = swap16($d->{crc16_calc_modbus});
        $d->{crc_ok}      = ($d->{crc16_rx_le} == $d->{crc16_calc_le}) ? 1 : 0;
    }

    if ($func == 0x06 && $len == 8) {
        $d->{message_type} = 'write-single-register';
        $d->{register} = f1200_u16_be($bytes, 2);
        $d->{value}    = f1200_u16_be($bytes, 4);
        return $d;
    }

    if ($func == 0x04 && $len == 8) {
        $d->{message_type} = 'read-input-registers-request';
        $d->{start_register} = f1200_u16_be($bytes, 2);
        $d->{register_count} = f1200_u16_be($bytes, 4);
        return $d;
    }

    if ($func == 0x04 && $len >= 10) {
        $d->{message_type} = 'read-input-registers-tunneled-response';
        $d->{start_register} = f1200_u16_be($bytes, 2);
        $d->{register_count} = f1200_u16_be($bytes, 4);

        my $data_offset = 6;
        my $data_len = $len - $data_offset - 2;
        $d->{data_bytes} = $data_len;
        $d->{expected_data_bytes} = (defined $d->{register_count}) ? $d->{register_count} * 2 : undef;
        $d->{length_match} = (defined $d->{expected_data_bytes} && $d->{expected_data_bytes} == $data_len) ? 1 : 0;

        my @regs;
        for (my $i = 0; $i + 1 < $data_len; $i += 2) {
            my $off = $data_offset + $i;
            push @regs, f1200_u16_be($bytes, $off);
        }
        $d->{register_words} = \@regs;

        return $d;
    }

    $d->{message_type} = 'unknown';

    return $d;
}

sub print_f1200_decoded {
    my ($self, $bytes) = @_;
    my $d = $self->decode_f1200_payload($bytes);

    print "Decoded:\n";
    print "  Kind:         $d->{kind}\n";
    print "  Length:       $d->{len}\n" if defined $d->{len};
    printf "  Slave/Func:   0x%02X / 0x%02X\n", $d->{slave}, $d->{function}
        if defined $d->{slave} && defined $d->{function};
    print "  Msg Type:     $d->{message_type}\n" if defined $d->{message_type};

    if (defined $d->{crc16_rx_le}) {
        printf "  CRC16 Rx:     0x%04X (LE)\n", $d->{crc16_rx_le};
    }
    if (defined $d->{crc16_calc_modbus}) {
        printf "  CRC16 Calc:   0x%04X (modbus order)\n", $d->{crc16_calc_modbus};
    }
    if (defined $d->{crc16_calc_le}) {
        printf "  CRC16 Calc:   0x%04X (wire LE)\n", $d->{crc16_calc_le};
    }
    if (defined $d->{crc_ok}) {
        print "  CRC Valid:    " . ($d->{crc_ok} ? 'yes' : 'no') . "\n";
    }

    if ($d->{message_type} eq 'write-single-register') {
        printf "  Register:     0x%04X\n", $d->{register} if defined $d->{register};
        printf "  Value:        0x%04X (%d)\n", $d->{value}, $d->{value} if defined $d->{value};
        return;
    }

    if ($d->{message_type} =~ /^read-input-registers/) {
        printf "  Start Reg:    0x%04X\n", $d->{start_register} if defined $d->{start_register};
        printf "  Reg Count:    %d\n", $d->{register_count} if defined $d->{register_count};
    }

    if ($d->{message_type} eq 'read-input-registers-tunneled-response') {
        printf "  Data Bytes:   %d\n", $d->{data_bytes} if defined $d->{data_bytes};
        if (defined $d->{expected_data_bytes}) {
            printf "  Expected:     %d\n", $d->{expected_data_bytes};
        }
        if (defined $d->{length_match}) {
            print "  Length Match: " . ($d->{length_match} ? 'yes' : 'no') . "\n";
        }

        if ($d->{register_words} && @{$d->{register_words}}) {
            my $show = @{$d->{register_words}} < 16 ? scalar(@{$d->{register_words}}) : 16;
            print "  Registers:    ";
            for my $i (0 .. $show - 1) {
                my $reg = ($d->{start_register} // 0) + $i;
                my $val = $d->{register_words}->[$i];
                printf "[%04X]=%04X", $reg, $val;
                print($i == $show - 1 ? "\n" : " ");
            }
            if (@{$d->{register_words}} > $show) {
                printf "  Registers:    ... (%d total words)\n", scalar(@{$d->{register_words}});
            }

            my $r = $d->{register_words};
            my $base = $d->{start_register} // 0;

            # SOC conversion inferred from observed values: register value appears to be 0.5% units.
            for my $off (3, 6) {
                next unless $off <= $#$r;
                my $reg = $base + $off;
                my $raw = $r->[$off];
                my $soc = $self->f1200_soc_percent($raw);
                next unless defined $soc;
                printf "  SOC 0x%04X:   %.1f %% (raw=%d)\n", $reg, $soc, $raw;
            }

            # Additional likely engineering values seen changing in live diff mode.
            for my $off (0x0014, 0x001E, 0x0027, 0x003B, 0x0012, 0x0015, 0x0016, 0x0029, 0x002A) {
                next if $off < $base;
                my $idx = $off - $base;
                next if $idx < 0 || $idx > $#$r;
                my $pretty = $self->f1200_register_pretty($off, $r->[$idx]);
                print "  Reg 0x" . sprintf('%04X', $off) . ":  $pretty\n" if length($pretty);
            }
        }
        return;
    }
}

sub f1200_soc_percent {
    my ($self, $raw) = @_;
    return undef unless defined $raw;
    return $raw / 2.0;
}

sub f1200_register_pretty {
    my ($self, $reg, $value) = @_;
    return '' unless defined $reg && defined $value;

    if ($reg == 0x0003 || $reg == 0x0006) {
        my $soc = $self->f1200_soc_percent($value);
        return sprintf('SOC candidate: %.1f %% (raw=%d)', $soc, $value);
    }

    # 0x0014 is AC presence status: 0 when AC input is available, 2 when on battery.
    if ($reg == 0x0014) {
        my $status = $value == 0 ? 'AC present' : ($value == 2 ? 'Battery mode' : 'Unknown');
        return sprintf('AC status: %s (raw=%d)', $status, $value);
    }
    # 0x001E is USB output power in 0.1 W units.
    # Confirmed: raw=39-40 matches device display of 3 W (3.9-4.0 W).
    if ($reg == 0x001E) {
        return sprintf('USB output power: %.1f W (raw=%d)', $value / 10.0, $value);
    }
    # 0x0027 changes on USB charge connect/disconnect; behaves as a bit-field status register.
    # Observed values: 0 (idle), 3 (0b011), 6 (0b110), 7 (0b111) during plug/negotiation.
    if ($reg == 0x0027) {
        return sprintf('Charging status flags: 0x%02X (raw=%d)', $value, $value);
    }
    # 0x003B is time remaining in minutes. Without load: ~4496 units = 3d 2h 56m.
    # With load, decreases proportionally. Jitters ±60 min due to AC ripple/estimation.
    if ($reg == 0x003B) {
        my $hours = int($value / 60);
        my $mins = $value % 60;
        my $days = int($hours / 24);
        $hours = $hours % 24;
        return sprintf('Time remaining: %dd %dh %dm (%d min, raw=%d)', $days, $hours, $mins, $value, $value);
    }
    # Based on observed jitter ranges during live diffing.
    if ($reg == 0x0012) {
        return sprintf('AC output voltage: %.1f V (raw=%d)', $value / 10.0, $value);
    }
    if ($reg == 0x0015) {
        return sprintf('AC input voltage: %.1f V (raw=%d)', $value / 10.0, $value);
    }
    if ($reg == 0x0016) {
        return sprintf('AC input frequency: %.2f Hz (raw=%d)', $value / 100.0, $value);
    }
    # 0x0029 changes with AC on/off (~2052 counts) and DC on/off (~640 counts).
    # Consistent with total output power in 0.1 W units.
    if ($reg == 0x0029) {
        return sprintf('Output power: %.1f W (raw=%d)', $value / 10.0, $value);
    }
    # 0x002A tracks DC bus output current (DC and USB outputs share this register).
    # Both DC and USB enable produce raw=216 (2.16 A) for comparable loads.
    if ($reg == 0x002A) {
        return sprintf('DC bus output current: %.2f A (raw=%d)', $value / 100.0, $value);
    }

    return '';
}

sub extract_modbus_register_snapshot {
    my ($self, $bytes) = @_;
    my $d = $self->decode_f1200_payload($bytes);
    return undef unless $d->{message_type}
        && $d->{message_type} eq 'read-input-registers-tunneled-response'
        && $d->{register_words}
        && defined $d->{start_register};

    my %regs;
    for my $i (0 .. $#{$d->{register_words}}) {
        $regs{$d->{start_register} + $i} = $d->{register_words}->[$i];
    }
    return \%regs;
}

sub diff_register_snapshots {
    my ($self, $old, $new) = @_;
    return [] unless $old && $new;

    my @changes;
    for my $reg (sort { $a <=> $b } keys %$new) {
        next unless exists $old->{$reg};
        next if $old->{$reg} == $new->{$reg};
        push @changes, {
            reg => $reg,
            old => $old->{$reg},
            new => $new->{$reg},
        };
    }
    return \@changes;
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
    --f1200-poll    Capture-based F1200 status poll (write 0x0036, notify 0x0038)
    --f1200-stream  Repeated F1200 status polling + notifications for --listen-sec
    --f1200-diff    Show only changed Modbus registers over time
    --f1200-raw     With F1200 poll/stream, also print raw hex notification
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
    --f1200-interval-ms N   Poll interval for --f1200-diff (default: 1000)
    --f1200-diff-csv PATH   Write changed-register events to CSV
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
    $0 -d AA:BB:CC:DD:EE:FF --f1200-poll
    $0 -d AA:BB:CC:DD:EE:FF --f1200-stream --listen-sec 30
    $0 -d AA:BB:CC:DD:EE:FF --f1200-diff --listen-sec 60 --f1200-interval-ms 1000
    $0 -d AA:BB:CC:DD:EE:FF --f1200-diff --f1200-diff-csv f1200-diff.csv
  $0 -d AA:BB:CC:DD:EE:FF --info -v
EOF
}
