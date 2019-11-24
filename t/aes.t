#!/usr/bin/env perl              # -*- perl -*-

use Mojo::Base -strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::IOLoop;
use Mojo::Promise;

use v5.20;
use Carp;

# Testing both the EncryptFilter and DecryptFilter classes
# together, since they're complementary.

use_ok("App::IDA::Daemon::EncryptFilter");
use_ok("App::IDA::Daemon::DecryptFilter");

# Book-end the encryption-decryption chain
use App::IDA::Daemon::StringSource;
use App::IDA::Daemon::StringSink;

my $lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit,
sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut
enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi
ut aliquip ex ea commodo consequat. Duis aute irure dolor in
reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla
pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.\n";

my $sed = "Sed ut perspiciatis unde omnis iste natus error sit
voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque
ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae
dicta sunt explicabo. Nemo enim ipsam voluptatem quia voluptas sit
aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos
qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui
dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed
quia non numquam eius modi tempora incidunt ut labore et dolore magnam
aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum
exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex
ea commodi consequatur? Quis autem vel eum iure reprehenderit qui in
ea voluptate velit esse quam nihil molestiae consequatur, vel illum
qui dolorem eum fugiat quo voluptas nulla pariatur?\n";

my $message = $lorem;
my $key = "0123456789abcdef";	# 128-bit key (16 bytes) 

# set up our processing chain: string -> enc -> dec -> string

# Try out sending a byte at a time, since this may cause problems with
# the encryption/decryption routines themselves, since they work on
# blocks of data.

my $chunk_size = 16;

my $source = App::IDA::Daemon::StringSource
    ->new("Mojo::IOLoop", $message, $chunk_size);

my $enc = App::IDA::Daemon::EncryptFilter
    ->new($source, "read", "close", $key);

ok (ref($enc), "new Encoder?");

my $dec = App::IDA::Daemon::DecryptFilter
    ->new($enc, "read", "close", $key);

ok (ref($dec), "new Decoder?");

my $output = "";

my $sink = App::IDA::Daemon::StringSink
    ->new($dec, "read", "close", \$output);
ok (ref($sink), "new Sink?");

# We don't actually have subscribe to close events here
$source->start;
Mojo::IOLoop->start;

is ($output, $message, "Input/Output messages match?");

done_testing;