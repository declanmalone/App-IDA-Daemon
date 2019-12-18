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
	    is ($_[0], substr("Lorem ipsum", $port,1),
		"First byte of stripe $port OK")
	},
	sub {
	    ok (0, "Not OK: read_p promise rejected with error $_[0]");
	})
	->wait 
}
# I expect the following to hang because there's no way to fulfil the
# internal promise(s) that Stripe should be waiting for.

# warn "Starting ioloop after first read";
# sleep 3;
# Mojo::IOLoop->start;

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

# warn "Doing second read";
# sleep 3;

for my $port (0..2) {
    $striper->read_p($port, 1)->then(
	sub {
	    # run tests on successful read_p
	    is (length($_[0]), 1, "read_p for stripe $port returns 1 char");
	    is ($_[0], substr("Lorem ipsum", 3 + $port,1),
		"Second byte of stripe $port OK")
	},
	sub {
	    ok (0, "Not OK: read_p promise rejected with error $_[0]");
	})
	->wait 
}

# warn "Starting ioloop after second read";
# sleep 3;
# Mojo::IOLoop->start;
# warn "Doing third read";

for my $port (0..2) {
    $striper->read_p($port, 1)->then(
	sub {
	    # run tests on successful read_p
	    is (length($_[0]), 1, "read_p for stripe $port returns 1 char");
	    is ($_[0], substr("Lorem ipsum dolor", 6 + $port,1),
		"Third byte of stripe $port OK")
	},
	sub {
	    ok (0, "Not OK: read_p promise rejected with error $_[0]");
	})
	->wait 
}
# warn "Starting ioloop after third read";
# sleep 3;
# Mojo::IOLoop->start;

# EOF-handling bug (and other stuff)
#
# After refactoring to move Stripe-specific functionality out of
# +Split, I noticed that I have bugs relating to eof handling, among
# other things. I need some tests to trigger them.

# Four EOF cases to test, assuming 3 output rows:
# * null input
# * 1 byte of input
# * 2 bytes of input
# * 3 bytes of input

# sanity check StringSource
my $expect_string = "Should keep returning eof";
$source = App::IDA::Daemon::Link::StringSource->new(
    source_buffer => $expect_string);
$source -> read_p (0, 0) -> then(
    sub {
	my ($data, $eof) = @_;
	is ($data, $expect_string, "Sanity check source (get all data)");
	ok ($eof, "Sanity check source (first eof)");
    },
    sub {
	ok (0, "Sanity check source not OK (shouldn't get here)");
    }) ->wait;
$source -> read_p (0, 0) -> then(
    sub {
	my ($data, $eof) = @_;
	is ($data, "", "Sanity check source (want any amount -> none)");
	ok ($eof, "Sanity check source (still eof)");
    },
    sub {
	ok (0, "Sanity check source not OK (shouldn't get here)");
    }) ->wait;
$source -> read_p (0, 1) -> then(
    sub {
	my ($data, $eof) = @_;
	is ($data, "", "Sanity check source (want up to 1 byte -> none)");
	ok ($eof, "Sanity check source (still eof)");
    },
    sub {
	ok (0, "Sanity check source not OK (shouldn't get here)");
    }) ->wait;

# done_testing; exit;

my $test_string = "ABCDEF...";	# three chars would suffice
# Window size *shouldn't* be a factor, but I'll test values of 1 and 2
# to be sure.
for my $ws (1,2) {
    for my $in_bytes (0,1,2,3) {
	my $in_string = substr($test_string, 0, $in_bytes);

	$source = App::IDA::Daemon::Link::StringSource->new(
	    source_buffer => $in_string);

	# I'm actually going to implement the idea that a non-zero EOF
	# value will indicate 1 more than the number of *input* bytes that
	# the algorithm consumed, so as well as testing that eof is
	# actually propagated (and properly considers whether there's any
	# pending data in the processing pipeline), I'll be testing that
	# new feature. I'll keep them both as separate tests, though.

	$striper = App::IDA::Daemon::Link::Stripe->new(
	    upstream_object => $source,
	    upstream_port => 0,
	    window => $ws,
	    stripes => 3,
	);

	for my $port (0..2) {
	    $striper->read_p($port, 1) -> then(
		sub {
		    my ($data, $eof) = @_;
		    my $expect_len = $in_bytes ? 1 : 0;
		    is (length($data), $expect_len, "Expected number of bytes");

		    # expect eof to propagate for all stripes
		    ok ($eof, "EOF is non-zero");

		    # expected eof value
		    is ($eof, $in_bytes + 1, "Expect eof value is input bytes + 1");

		    my $expect_data =
			$in_bytes > 0
			# either something from $in_string or null pad
			? ($port >= $in_bytes ? "\0" : substr($in_string, $port, 1))
			# or no data
			: "";
		    is ($data, $expect_data, "Expected data")
		},
		sub {
		    ok (0, "Not OK: read_p promise rejected with error $_[0]");
		}
	    )-> wait;
	    # Mojo::IOLoop->start;
	}
	#die;		# never gets here (∞ loop)
    }
}

done_testing; exit;
