package App::IDA::Daemon::Link::Role::Filter;

# Filter trait
use Mojo::Base -role;

# Some other role must supply the concrete method below:
requires qw(filter_process);

# we provide default implementation for input/output

# These will get pushed out to new roles later, but for now implement
# them here (just declarations for now; code is below):
# 
sub connect_upstream;   	# called during new()
sub read_upstream;   		# called in our loop

sub read_p;   			# called by downstream

# Code for checking upstream_* args moved to +PullsFromUpstream
use Role::Tiny::With;


# This was failing with Role::Tiny versions 2.000006 and 2.000005, but
# the most recent version (2.001004) fixes it. Perhaps the failure was
# because we don't define any methods in the role below?
with 'App::IDA::Daemon::Link::Role::PullsFromUpstream';

# Role::Tiny doesn't seem to pick up that the attributes set up with
# Mojo::Base's 'has' are fulfilling the requires below:
#
# # use App::IDA::Daemon::Link::Role::PullsFromUpstream;
# requires qw(upstream_object upstream_port);

#
# Since I've factored out some upstream related code, I could also
# factor out some downstream code here.
#
# TODO: add roles +SingleDownstreamPort, +MultipleDownstreamPort
#
# If I go with the single/multi breakdown (to account for
# split/combine), then I may have to rename the roles to something
# snappier. Or, I can just treat split/combine as special cases and
# don't decompose the port-related stuff into separate roles...
#
# Anyway, it probably does make sense to keep +PullsFromUpstream as a
# separate role because it can be composed in from both +Filter and
# +Sink roles.

# During downstream object construction, this method will be called to
# make sure that downstream is connecting to port 0. (see BUILDARGS)
sub has_read_port { $_[1] == 0 }

# we provide read_p, and some other role supplies filter_process()
sub read_p {
    my $self = shift;
    my $bytes = shift;

    # New promise that we return
    my $promise = $self->{promise} = Mojo::Promise->new;

    # Chain into upstream promise
    $self->{upstream}->read_p($bytes)
        ->then(
        sub {
            my ($data, $eof) = @_;
            # warn "in Filter::read_p (data: $data, eof: $eof)\n";
            $data = $self->filter_process($data);
            $promise->resolve($data, $eof);
            $promise = undef;
        },
        sub {
            $promise->reject($_[0]);
            $promise = undef;
        });

    $promise;
}


1;

    
# The idea with refactoring the above is that:
#
# A source will have an internal "upstream", eg a string or an
# encapsulated Mojo::IOLoop::Stream object, while Filters and Sinks
# will have an external upstream (ie, another Link)
#
# Likewise, a Sink won't have read_p, but will have some other way of
# scheduling itself to run.
#
# An example of naming the new roles:
#
# Source does EmbeddedSource, LinksDownstream
#
# Filter does LinksUpstream, LinksDownstream
#
# Sink does LinksUpstream, EmbeddedSink
