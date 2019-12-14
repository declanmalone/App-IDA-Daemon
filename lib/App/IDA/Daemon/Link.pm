package App::IDA::Daemon::Link;

# I want to use roles to split up different functionality Should I
# also base on EventEmitter, since some roles might need it?

# If you use -role here, then composing using with_roles succeeds
# regardless of whether all requires are satisfied or not
#
# my $new_class = App::IDA::Daemon::Link -> with_roles("+Filter");


use Mojo::Base  'Mojo::EventEmitter';

use warnings;


# Roles will declare 'around BUILDARGS => sub { ...}' to check
# attributes passed to new
sub BUILDARGS {};

sub new {
    my $class = shift;
    my $self = bless { }, $class;
    my $errors = [];
    $self->BUILDARGS( {@_}, $errors);
    if (@$errors) {
	warn "Link: there were some problems with arguments\n";
	foreach my $err (@$errors) {
	    warn "$err\n";
	}
	die "Link: quitting\n";
    }
    $self;
};

1;


=pod

=head1 NAME

App::IDA::Daemon::Link - A link in an asynchronous processing chain

=cut

# Goals...
#
# Overall, I want to refactor the various Source, Filter and Sink bits
# of code (currently separate classes) to reuse code where possible
# and practical.
#
# I'm more in favour of using read_p and Promises to do
# pull-based/lazy evaluation of data in each processing step.
#
# The alternative is push-based processing, where upstream elements
# emit data whenever it becomes available.

# Abstraction
#
# I'm going to focus on an asynchronous process as the main
# abstraction. The Link base class will be an abstract class since it
# has no processing functionality. Each sub-class will implement its
# own processing function.
#
# The base class will implement the abstract idea of three types of
# processing elements:
#
# * pass-through (1 input, 1 output)
# * split/map (1 input, n outputs)
# * combine/reduce (n inputs, 1 output)
#
# It will also provide an abstraction based on an execution context
# with:
#
# * input buffer(s)
# * the asynchronous process (handled in subclass)
# * output buffer(s)
#
# In this way, I hope that I can completely decouple the processing
# from any I/O considerations.
#
# In order to achieve code re-use with regard to upstream/downstream
# linkage, I will use Roles to allow selection of different methods
# for filling input buffers and emptying output buffers:
#
# * null source/sink
# * string buffer
# * encapsulated file handle
# * encapsulated Mojo::IOLoop::Stream
# * emit/subscribe-based connection to upstream/downstream
# * read_p/promise-based connection to upstream/downstream


# # OO Description
#
# To get an overview of how this all fits together, I'll distinguish
# between the inheritance style of OO design, and the role/trait-based
# design.
#
# We can say that:
#
# * the inheritance model focuses on what an object *is*
# * the role/trait model focuses on what an object *does*
#
# ## What it is
#
# The Link class is effectively a scheduler for chunks of work on a
# data stream. It works within an event loop framework, which in this
# case is Mojo.
#
# The base class only provides for scheduling of work, but it does not
# do any processing itself, since it is only an abstract scheduling
# class.
#
# The sub classes provide the concrete implementation, thus becoming,
# eg, a stream encryptor or a stream hasher or an IDA splitter.
#
# ## What it does
#
# By itself, Link doesn't actually *do* anything. It is missing
# functionality relating to filling and emptying input/output buffers
# and connecting to upstream/downstream links and the event loop in
# general.
#
# This is where Roles come in.
#
# Subclasses of Link can be scheduled to do chunks of work, but only
# if the extra functionality relating to input/output or other events
# is composed into it via one or more Roles.
#
# Roles can be composed into a Link class either dynamically or
# statically.
#
# Roles are named after whether they provide input or output for the
# processing element. Depending on which particular role is
# implemented on the upstream and downstream interfaces, the Link can
# also be tagged with a "typing" role of Source, Filter or Sink.
#
# For example, we can create a Link::ToUpper Filter by:
#
# * implementing Link::ToUpper
# * composing in a Role that provides input
# * composing in a Role that provides output
# * composing in the typing role "Filter"
#
# The input role could be named something like "CallsUpstreamReadp" or
# "SubscribesToUpstream", for example, to indicate whether the Link
# connects to the upstream using the pull-based promise interface, or
# responds to a push-based upstream element by subscribing to its
# on-read and on-close events.
#
# The "Filter" role, if implemented, would only be for typing
# purposes. It would have no implementation itself, but would specify
# a set of 'required' behaviours. The role itself might also include a
# bit of self-check code for dynamically checking that an object
# satisfies the role at run time, as opposed to static checking that's
# done at 'use' or 'compose' time.
#

# Organisation
#



    
