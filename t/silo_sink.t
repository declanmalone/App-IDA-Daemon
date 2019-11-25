#!/usr/bin/env perl              # -*- perl -*-

use Mojo::Base -strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;

use App::IDA::Daemon::StringSource;

use v5.20;
use Carp;

# Unit test class
my $ut_class = "App::IDA::Daemon::SiloSink";
use_ok($ut_class);

# Things to test...
#
# * writing without configuring class first
# * streaming from Mojo::IOLoop::Stream (file)
# * streaming from Mojo::IOLoop::Stream (fifo/socket pair)
# * block attempt to traverse out of allowed dir with ..
# * recursive creation of output directory
# * raise error on read-only file
# * raise error on read-only dir
# * Unicode chars in path

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

mkdir "$Bin/silos" unless -d "$Bin/silos";

# By default, perl interpreter lets you open a string
my ($in, $is);
if (0) {
    unless (open $in, "<", \$lorem) {
	warn "Your perl interpreter doesn't support opening a string\n";
	plan skip_all => "Can't use required PerlIO feature";
	exit;
    }
    # input stream
    $is = Mojo::IOLoop::Stream->new($in);
    # (but Mojo::IOLoop::Stream is having none of it)
} else {
    # so ...
    $is = App::IDA::Daemon::StringSource
	->new("Mojo::IOLoop", $lorem, 20);
    ok(ref($is), "Made a StringSource?");
}



ok(ref($is), "Create Stream from string?");

sub unlink_if_exists {
    unlink $_[0] if -f $_[0];
}

unlink_if_exists("$Bin/silos/output");

my $writer = $ut_class->new($is, "read", "error", "$Bin/silos/output");

ok(!ref($writer), "Expect error if $ut_class not configured");
warn "Return was $writer\n";

# Class should not have subscribed to $is events
ok(!$is->has_subscribers("read"),  "No spurious read subs?");
ok(!$is->has_subscribers("close"), "No spurious close subs?");

# Configure an allowed write directory (path relative to t/)
$ut_class->config("$Bin/silos");

$writer = $ut_class->new($is, "read", "close", "$Bin/silos/output");

ok($is->has_subscribers("read"),  "Subscribed to read?");
ok($is->has_subscribers("close"), "Subscribed to close?");

ok(-f "$Bin/silos/output", "Created file?");
is(0, (stat "$Bin/silos/output")[7], "File size zero?");

# Will use a promise to track completion of chain
my $promise = Mojo::Promise->new;

$writer->on(close => sub { $promise->resolve(shift) });

$is->start;



done_testing;
