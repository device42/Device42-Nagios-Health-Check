#!/usr/bin/perl
# -- Author:        Skribnik Evgeny, hemulll@gmail.com
# -- Description:   d42 instance health check

use warnings FATAL => 'all';
use strict;
use Data::Dumper;
use JSON;
use LWP::Simple;
use Nagios::Plugin;

use vars qw($VERSION $PROGNAME  $verbose $timeout $result);
$VERSION = '1.0';

use File::Basename;
$PROGNAME = basename($0);

my $plugin = Nagios::Plugin->new(
    usage => "Usage: %s [ -v|--verbose ] [-t|--timeout <timeout>]
    [ -H|--host=<hostname> ]
    [ -P|--port=<port number, default is 4242> ]
    [ -I|--item=<item to check (e.g: dbsize, backup_status, disk_used_percent, etc. )> ]
    [ -c|--critical=<threshold> ] [ -w|--warning=<threshold> ]
    [ -t|--timeout=<Time out> ]",


    version => $VERSION,
    blurb => "Check D42 instance health",
    extra => "
  Examples:
    $PROGNAME -H example.com -P 4343 -I disk_used_percent,
"
);


$plugin->add_arg(
	spec => 'host|H=s',
	required => 1,
	help => '-H, --host=STRING The domain address to check. REQUIRED.');

$plugin->add_arg(
	spec => 'port|P=s',
	required => 0,
	default => 4242,
	help => '-P, --port=STRING The port number to check.');

$plugin->add_arg(
	spec => 'item|I=s',
	required => 1,
	help => '-I, --item=STRING The item to check, should be one of (backup_status, disk_used_percent, etc.).');

# -- add warning thresholds
$plugin->add_arg(
 spec => 'warning|w=s',
 help => '-w, --warning=INTEGER:INTEGER',
);

# -- add critical thresholds
$plugin->add_arg(
 spec => 'critical|c=s',
 help => '-c, --critical=INTEGER:INTEGER',
);



# Parse arguments and process standard ones (e.g. usage, help, version)
$plugin->getopts;

local $SIG{ALRM} = sub { $plugin->nagios_exit(CRITICAL, "script execution time out") };
alarm $plugin->opts->timeout;

my $url = "http://" . $plugin->opts->host . ":" . $plugin->opts->port . "/healthstats/";

my $memory_param = "memory_in_MB";
my %variables = (
    cpu_used_percent    => undef,
    dbsize              => '',
    backup_status       => '',
    disk_used_percent   => undef,
    cached              => $memory_param,
    buffers             => $memory_param,
    swaptotal           => $memory_param,
    memfree             => $memory_param,
    swapfree            => $memory_param,
    memtotal            => $memory_param

);

# -- check items exist
$plugin->nagios_exit(UNKNOWN, "item " . $plugin->opts->item . " is not defined") unless exists($variables{$plugin->opts->item});

# -- read JSON message from URL
my $jsonResponse = loadFromURL($url);



my $data = "";

eval {
    # -- decode JSON to Perl structure
    $data = decode_json($jsonResponse);

    $plugin->nagios_exit(UNKNOWN, "no data received from server") if $data eq "";
}; if ($@) {
    $plugin->nagios_exit(UNKNOWN, "can not parse JSON received from server");
}

my $data_val = undef;

# -- print data from $memory_param hash
if (defined($variables{$plugin->opts->item})) {
    # -- access to  $memory_param hash
    $data_val =  $data->{$variables{$plugin->opts->item}}->{$plugin->opts->item};
} else {
    $data_val =  $data->{$plugin->opts->item};
}

# Threshold methods
my $code = $plugin->check_threshold(
    check => $data_val,
    warning => $plugin->opts->warning,
    critical => $plugin->opts->critical,
);

# -- return thresholds check result
$plugin->nagios_exit( $code, "Threshold check failed" ) if $code != OK;



# -- load data from URL
sub loadFromURL {
    my $url = shift;
    printLog("load $url");
    my $data = get $url;
    $plugin->nagios_exit(UNKNOWN, "Couldn't get $url") unless defined $data;
    return $data;
}

# -- print log in STDOUT in verbose mode only
sub printLog {
    my $context = shift;
    print "$context\n" if $plugin->opts->verbose;
}