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
ok (ref $striper, "Created striper");

ok ($striper->can("window"));
ok ($striper->can("stripes"));

# How BUILDARGS sets up other variables
ok (defined($striper->xform_matrix()), "Constructed transform matrix");

is (3, $striper->k, "calculated k value equals 'stripes'?");

done_testing; exit;
