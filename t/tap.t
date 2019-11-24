#!/usr/bin/env perl              # -*- perl -*-

use Mojo::Base -strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;

use v5.20;
use Carp;

# Unit test class
my $ut_class = "App::IDA::Daemon::TapFilter";
use_ok($ut_class);

done_testing;
