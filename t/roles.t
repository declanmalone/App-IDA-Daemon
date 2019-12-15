#!/usr/bin/env perl              # -*- perl -*-

package main;

use Mojo::Base -strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;
use Mojo::IOLoop;

use App::IDA::Daemon::StringSource;

use v5.20;
use Carp;

use_ok("App::IDA::Daemon::Link");

# A "null" filter simply copies input to output

# Two ways to create it:
#
# 1. the class itself takes care of 'with'
# 2. we compose it manuallt into a suitable class

# The Filter *Role* looks like:

=begin Filter.pm

package App::IDA::Daemon::Link::Role::Filter;

# ::Filter trait
use Mojo::Base -role; # we are a role!

requires qw(filter_process);

# provide default implementation for other subs
sub connect_upstream { }
sub read_p { }
=cut

# method 1: class explicitly calls "with". 
use_ok("App::IDA::Daemon::Link::NullFilter");

# NullFilter is a *class* that implements the Filter role

=begin ::NullFilter.pm

package App::IDA::Daemon::Link::NullFilter;

use parent App::IDA::Daemon::Link;

# we consume/implement roles
use Role::Tiny::With;

with App::IDA::Daemon::Link::Role::Filter;

# satisfiy the Filter role requirement:
sub filter_process {}

1;
=cut
    

# method 2: we compose it in
package ConcreteRole;

# This *role* can be composed in to satisfy the requirements of Filter

use Role::Tiny;

sub filter_process {}		# required by trait
1;

package FooWithRequiredMethod;	# This *class* has the required sub

use Mojo::Base -base;

sub filter_process {}		# required by trait
1;

package BarWithout;		# this *class* doesn't

use Mojo::Base -base;
1;

package main;


# Don't import this: it's only to declare that the class is???
#use Role::Tiny;

my $new_class;

# Filter adds an unsatisfied requirement to define filter_process()
eval {
    $new_class = App::IDA::Daemon::Link
	->with_roles("+Filter");
};
ok ($@, "Expected splat: $@");

# ConcreteRole is a Role that provides an implementation of it
$new_class = App::IDA::Daemon::Link
    ->with_roles("+Filter", "ConcreteRole");

# warn $new_class; # we get back a class name, not a ref!
ok (defined $new_class, "Apply role using with_roles");

# Change test of new() to expect splat (missing upstream_* args)

my $obj;
eval {
    $obj = $new_class->new;
};
ok ($@, "Expected splat: $@");

# Can't test setting upstream_object/upstream_port yet (don't have a
# valid upstream_object yet...)

# Expect OK if we include required args
#$obj = $new_class->new( upstream_object
#ok (ref $obj, "Composed class returned an object");

# another way of composing uses Mojo::Base->with_roles

# Try to use our classes above, which 'use Mojo::Base -base'
my $next_class = FooWithRequiredMethod->
    with_roles("App::IDA::Daemon::Link::Role::Filter");

# This one doesn't have filter_process()
my $bad_class;
eval {
 $bad_class = BarWithout->
	with_roles("App::IDA::Daemon::Link::Role::Filter");
};
ok ($@, "Expected splat: $@");

# Move on to testing functionality
#
# Make StringSource and StringSink classes that do Source, Sink
# roles.
#
# Chain them together (making sure that constructors work) and then do
# functionality tests.
#
# The code will be based on promise_chain.pl in my mojo-experiments
# repo, so the main changes will be in terms of object/role
# decomposition and parameter checking.
#

### Unit test Link::StringSource (pre-composed class)
use_ok("App::IDA::Daemon::Link::StringSource");

# StringSource needs source_buffer
eval { $obj = App::IDA::Daemon::Link::StringSource -> new() };

ok ($@, "Expect splat if no source_buffer arg: $@");

# Give constructor a source_buffer argument
$obj = App::IDA::Daemon::Link::StringSource
    ->new(source_buffer => "This is some buffer text");

ok(ref($obj), "StringSource->new with source_buffer OK?");

# test its read_p functionality with a number of bytes
my $got = "";
my $eof = 0;
my $p = $obj->read_p(0, 7);

is (ref($p), "Mojo::Promise", "read_p returns a Mojo::Promise?");

# wait for promise to be resolved
$p->then(sub { ($got, $eof) = @_ })->wait;
is ($got, "This is", "read_p 7 bytes gets 'This is'?");
is ($eof, 0, "String at eof already?!");

# If we set bytes to 0, we should get the rest of the string
$p = $obj->read_p(0, 0);
$p->then(sub { ($got, $eof) = @_ })->wait;
is ($got, " some buffer text", "read_p 0 bytes gets remaining text?");
ok ($eof, "eof as expected?");

$obj = App::IDA::Daemon::Link::StringSource
    ->new(source_buffer => "Short text");

# test reading from invalid port
# This should die, since it's a programming error
eval {
    $p = $obj->read_p(1, 0);
};
ok ($@, "Expected splat: $@");

# test reading more than available bytes
$p = $obj->read_p(0, 10_000);
$p->then(sub { ($got, $eof) = @_ })->wait;
is ($got, "Short text", "read_p > avail bytes gets all text?");
ok ($eof, "eof as expected?");


### Unit Test Link::StringSink (pre-composed class)
#use_ok("App::IDA::Daemon::Link::StringSink");



done_testing; exit;


# I will use this set of tests to figure out how best to refactor
# the various promise-based Sources, Filters and Sinks to use
# roles.

# Eventually, all the classes will use Role::Tiny::With internally, so
# that when you 'use Class', all the relevant roles will already have
# been composed into that class.

# For the purposes of testing and experimentation, however, I will try
# to compose classes manually. See the with_roles method in Mojo::Base
# for details.

# It seems that the way to refactor my Source/Filter/Sink classes to
# use roles needs to account for two types of Role:
#
# * structural (or "abstract") roles that provide the basic
#   scaffolding for how the class operates
#
# * concrete roles that include specialisation that's unique to that
#   Source, Filter or Sink
#
# (Examining the Role::Tiny source, I see that it also uses a similar
# "concrete" nomenclature---"concrete methods" there are methods that
# fulfill some 'requires' statement, and can come from roles or
# classes)
#
# For example, consider how read_p is implemented in a filter like
# ToUpper:
#
# # ...
# my $promise = Mojo::Promise->new;
# $self->{upstream}->read_p(0,$bytes)->then(
# 	sub {
# 	    my ($data, $eof) = @_;
# 	    $data =~ y/a-z/A-Z/;
# 	    $promise->resolve($data, $eof);
# 	},
# 	sub {
# 	    $promise->reject($_[0]);
# 	});
# $promise;
#
# This is a stateless filter. We have the concrete implementation in
# the y/// line, and the rest of the code is structural. For other
# stateless filters, we can reuse the structural role and simply
# provide a new concrete implementation.
#
# Contrast this with an Encryption filter. It needs to maintain state
# in a variety of ways:
#
# * in the constructor, it needs to construct an IV and an encryption
#   object
# * it prepends the unencrypted IV to the outgoing data stream
# * it needs to detect eof so that it can flush any data left in the
#   encryption object, appending it to the output stream
#
# The scaffolding (structural) part of the implementation will thus
# be slightly different.
#
# Actually, there is always more than one way to organise the code. We
# can make the above two types of filter (stateless/stateful) use the
# same code base if we have an output buffer for all filters/sources.
# Thus, if we wanted to, we could implement read_exact_p functionality
# as well as read_p with a bytes parameter of 0 (unlimited) or n (up
# to that many).
