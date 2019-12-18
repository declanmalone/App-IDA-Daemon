#!/usr/env/perl

use Mojo::Base -strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;
use Mojo::IOLoop;

# Test use of Crypt::IDA to do striping

use_ok("App::IDA::Daemon::Link::Stripe");

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

use App::IDA::Daemon::Link::StringSource;

my $source = App::IDA::Daemon::Link::StringSource->new(
    source_buffer => $lorem);

ok (ref $source, "Created lorem string source");

my $striper;

eval{
    $striper = App::IDA::Daemon::Link::Stripe->new(
	upstream_object => $source,
	upstream_port => 0,
    );
};
ok ($@, "Expect splat with no window arg");

eval{
    $striper = App::IDA::Daemon::Link::Stripe->new(
	upstream_object => $source,
	upstream_port => 0,
	window => 2,
    );
};
ok ($@, "Expect splat with no stripes arg");

$striper = App::IDA::Daemon::Link::Stripe->new(
    upstream_object => $source,
    upstream_port => 0,
    window => 2,
    stripes => 3,
);
ok ($source, "Yes, source evals to true");
ok (ref $striper, "Created striper");
is ($striper->upstream_object, $source, "Stashed upstream_object method");
is ($striper->upstream_port,   0,       "Stashed upstream_port method");
is ($striper->{upstream_object}, $source, "Stashed {upstream_object}");
is ($striper->{upstream_port},   0,       "Stashed {upstream_port}");

# Test if accessors were created from parameters
ok ($striper->can("window"), "object has 'window' attribute");
ok ($striper->can("stripes"), "object has 'stripes' attribute");
is (2, $striper->window, "window accessor return value OK");
is (3, $striper->stripes, "stripes accessor return value OK");

# How BUILDARGS sets up other variables (test via accessor methods)
ok (defined($striper->xform_matrix()), "Constructed transform matrix");
is (3, $striper->k, "calculated k value equals 'stripes'");
is (1, $striper->w, "default w value equals 1");
ok (ref ($striper->ida_splitter), "Can see internal IDA splitter");
ok (ref ($striper->sw), "Can access sliding window obect");

# Test existence of ports
ok ($striper->has_read_port($_), "Striper has port $_?") for (0..2);

# Non-existent port
ok (!$striper->has_read_port(3), "Port 3 shouldn't exist");

# Most of +Split and Stripe aren't implemented yet. Our starting
# point:
ok ($striper->can("read_p"), "Can striper read_p?");

for my $port (0..2) {
    $striper->read_p($port, 1)->then(
	sub {
	    # run tests on successful read_p
	    is (length($_[0]), 1, "read_p for stripe $port returns 1 char");
	    is ($_[0], substr("Lorem ipsum", $port,1), "First byte of stripe $port OK")
	},
	sub {
	    ok (0, "Not OK: read_p promise rejected with error $_[0]");
	})
	->wait 
}
# I expect the following to hang because there's no way to fulfil the
# internal promise(s) that Stripe should be waiting for.
warn "Starting ioloop after first read";
#sleep 3;
Mojo::IOLoop->start;
# Hmm. It doesn't hang. It seems that the algorithm is not so greedy
# (or loopy?) after all. Am I not requesting that more processing is
# done once some output buffer space becomes available? Something to
# think about tomorrow...

# OK. I think that this behaviour is correct. I was just
# misunderstanding how ioloop interacts with pending promises. The
# ioloop won't block unless there's an explicit wait called on a
# pending promise. In other words, you can have many pending promises,
# and the IO loop will still return unless you call wait on one of
# them.

warn "Doing second read";
#sleep 3;

for my $port (0..2) {
    $striper->read_p($port, 1)->then(
	sub {
	    # run tests on successful read_p
	    is (length($_[0]), 1, "read_p for stripe $port returns 1 char");
	    is ($_[0], substr("Lorem ipsum", 3 + $port,1), "Second byte of stripe $port OK")
	},
	sub {
	    ok (0, "Not OK: read_p promise rejected with error $_[0]");
	})
	->wait 
}

warn "Starting ioloop after second read";
#sleep 3;
Mojo::IOLoop->start;

warn "Doing third read";
#sleep 3;

for my $port (0..2) {
    $striper->read_p($port, 1)->then(
	sub {
	    # run tests on successful read_p
	    is (length($_[0]), 1, "read_p for stripe $port returns 1 char");
	    is ($_[0], substr("Lorem ipsum dolor", 6 + $port,1), "Third byte of stripe $port OK")
	},
	sub {
	    ok (0, "Not OK: read_p promise rejected with error $_[0]");
	})
	->wait 
}
warn "Starting ioloop after third read";
#sleep 3;
Mojo::IOLoop->start;


done_testing; exit;
