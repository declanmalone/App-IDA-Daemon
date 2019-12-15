#!perl
use v5.10;
use strict;
use warnings;
use Test::More;

use FindBin qw($Bin);
use lib "$Bin/../lib";

plan tests => 1;

BEGIN {
    use_ok( 'App::IDA::Daemon' ) || print "Bail out!\n";
}

diag( "Testing App::IDA::Daemon $App::IDA::Daemon::VERSION, Perl $], $^X" );
