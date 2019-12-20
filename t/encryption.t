#!/usr/bin/env perl              # -*- perl -*-

# Tests for:
# * App::IDA::Daemon::Link::EncryptFilter
# * App::IDA::Daemon::Link::DecryptFilter

use Mojo::Base -strict;

use FindBin qw($Bin);
push @INC, "$Bin/../lib", "$Bin";

use Test::More;
use Test::Mojo;

use Mojo::IOLoop;
use Mojo::Promise;

use v5.10;
use Carp;

use_ok("App::IDA::Daemon::Link::EncryptFilter");
use_ok("App::IDA::Daemon::Link::DecryptFilter");

# Import "Lorem ipsum" texts ($Lorem::lorem and $Lorem::sed)
use_ok("Lorem");
ok ($Lorem::lorem, "Lorem ipsum text imported");

my $message = $Lorem::lorem;
my $key = "0123456789abcdef";	# 128-bit key (16 bytes) 

# AES uses a block size of 16 bytes, so want to test text that is not a
# multiple of that.
ok (length($message) % 16, "Lorem text not a multiple of 16 bytes");




done_testing; exit;
