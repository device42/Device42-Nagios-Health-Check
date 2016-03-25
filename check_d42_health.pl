#!/usr/bin/perl
# -- Author:        Skribnik Evgeny, hemulll@gmail.com
# -- Description:   d42 instance health check

use warnings FATAL => 'all';
use strict;
use Data::Dumper;
use JSON;
use LWP::UserAgent;
use Nagios::Plugin;
use Fcntl qw(:flock SEEK_END );

use vars qw($VERSION $PROGNAME  $verbose $timeout $result);
$VERSION = '0.1';

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

# -- add ssl option
$plugin->add_arg(
 spec => 'ssl',
 help => '-S, --ssl Use HTTP protocol to fetch data',
);

# -- cache param
$plugin->add_arg(
 spec => 'cache|C=s',
 default => 60,
 help => '-C, --cache=INTEGER Enable Cache time expired after N seconds. Default 60 secs'
);

# Parse arguments and process standard ones (e.g. usage, help, version)
$plugin->getopts;

# -- cache variables
my $cache_enabled           = $plugin->opts->cache eq '' ? 1 : 0;
my $cache_dir_path          = "c:\\Temp\\"; # -- TODO: change in prod
my $cache_file_name         = $plugin->opts->host . ".cache";
my $cache_file_path         = $cache_dir_path . $cache_file_name;
my $cache_expired_duration  = $plugin->opts->cache ? $plugin->opts->cache : 60 ; # -- cache expired after N seconds


# -- measure global script execution time out
local $SIG{ALRM} = sub { $plugin->nagios_exit(CRITICAL, "script execution time out") };
alarm $plugin->opts->timeout;

# -- define protocol type HTTPS or HTTP
my $url_protocol = $plugin->opts->ssl ? "https" : "http";

# -- build URL path
my $url =   "$url_protocol://" . $plugin->opts->host . ":" . $plugin->opts->port . "/healthstats/";

# -- list of available metrics. TODO: move to external XML file in future
my $memory_param = "memory_in_MB";
my %variables = (
    cpu_used_percent    => undef,
    dbsize              => undef,
    backup_status       => undef,
    disk_used_percent   => undef,
    cached              => $memory_param,
    buffers             => $memory_param,
    swaptotal           => $memory_param,
    memfree             => $memory_param,
    swapfree            => $memory_param,
    memtotal            => $memory_param
);

# -- check that passed in item is exist in metric scope
$plugin->nagios_exit(UNKNOWN, "item " . $plugin->opts->item . " is not defined") unless exists($variables{$plugin->opts->item});

# -- read JSON message from URL
# -- check if data exist in cache
my $jsonResponse;

 if ($cache_enabled) {
    printLog("cache is enabled");
    $jsonResponse = readFromCache();
 } else {
    printLog("cache is disabled");
    $jsonResponse = loadFromURL($url);
 }


my $data = "";

eval {
    # -- decode JSON to Perl structure
    $data = decode_json($jsonResponse);
    $plugin->nagios_exit(UNKNOWN, "no data received from server") if $data eq "";
}; if ($@) {
    $plugin->nagios_exit(UNKNOWN, "can not parse JSON received from server");
}



my $data_val = undef;

# -- find where data is stored.
# -- print data from $memory_param hash
if (defined($variables{$plugin->opts->item})) {
    # -- access to  $memory_param hash
    $data_val =  $data->{$variables{$plugin->opts->item}}->{$plugin->opts->item};
} else {
    $data_val =  $data->{$plugin->opts->item};
}

# -- remove MB or Gb string from the dbsize value.
$data_val =~s/ MB|GB//ig if ($plugin->opts->item eq 'dbsize');

$plugin->nagios_exit(UNKNOWN, "Item " . $plugin->opts->item . " is empty or not defined") unless $data_val;

# -- prepare default output message for all checks
my $output_text = $plugin->opts->item . " = " . $data_val;

# -- set thresholds
$plugin->set_thresholds(warning => $plugin->opts->warning, critical => $plugin->opts->critical);

# -- compare thresholds
if ($plugin->opts->warning || $plugin->opts->critical) {

    # -- exit with threshold error if any
	$plugin->nagios_exit(
		return_code => $plugin->check_threshold($data_val),
		message     => $output_text
	  );
}

# -- exit with OK status if all is good
$plugin->nagios_exit(OK, $plugin->opts->item . " = " . $data_val);

# -- read from cache
sub readFromCache {

    my $data;

    # -- if cache is expired or not exists
    if (isCacheExpired() || ! -e $cache_file_path) {
        printLog("cache file is expired or does not exists");
        $data = loadFromURL($url);
        storeInCache($data);
    } else {
        printLog("read data from cache");
        open(my $fh, '<:encoding(UTF-8)', $cache_file_path) or die "Could not open file '$cache_file_path' $!";
        $data =  <$fh>;
        close $fh;
    }

    return $data;
}

# -- check if cache file is expired or does not exist
sub isCacheExpired {
    return (-e $cache_file_path ) && (time - (stat ($cache_file_path))[9]) > $cache_expired_duration;
}

# -- put data to cache file
sub storeInCache {
    my $context = shift;

    open(my $fh, '>:encoding(UTF-8)', $cache_file_path) or die "Could not open file '$cache_file_path' $!";
#    lock($fh);
    print $fh $context;
#    unlock($fh);
    close $fh;
}

# -- load data from URL
sub loadFromURL {
    my $url = shift;

    my $data;
    printLog("load $url");

     my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0x00 });


     my $response = $ua->get($url);

    if ($response->is_success) {
        $data =  $response->decoded_content;
    } else {
        my $err = "Couldn't get $url ," . $response->status_line;
        printLog($err);
        $plugin->nagios_exit(UNKNOWN, $err);
    }

    unless (defined ($data)) {
        my $err = "Couldn't get $url";
        printLog($err);
        $plugin->nagios_exit(UNKNOWN, $err) ;
    }

    return $data;
}

# -- print log in STDOUT in verbose mode only
sub printLog {
    my $context = shift;
    print "$context\n" if $plugin->opts->verbose;
}

sub lock {
    my ($fh) = @_;
    flock($fh, LOCK_EX) or die "Cannot lock $cache_file_path - $!\n";
    seek($fh, 0, SEEK_END) or die "Cannot seek - $!\n";
}
sub unlock {
    my ($fh) = @_;
    flock($fh, LOCK_UN) or die "Cannot unlock $cache_file_path - $!\n";
}