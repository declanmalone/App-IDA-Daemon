package App::IDA::Daemon::Link::Role::Sink;

# Sink trait
use Mojo::Base -role;

use Mojo::IOLoop;

# Some other role must supply the concrete methods below:
requires qw(write_to_internal finish_message);

# TODO: Having finish_message in requires should cause test errors!

# Supplied Roles that provide the concrete implementation:
# * +InternalStringSink
# * +InternalNullSink
# * +InternalStreamSink
# * +InternalDigestSink

# Our attributes/parameters
has [qw(running preferred_bytes)];
around BUILDARGS => sub {
    my ($orig, $self, $args, $errors) = @_;

    # Always silently create the object in 'not running' state,
    # regardless of any user-supplied arg.
    $self->{running} = 0;

    # TODO: handle preferred_bytes parameter

    # Call the rest of the BUILDARGS chain
    $orig->($self, $args, $errors);
};

# Filters and Sinks pull (call read_p) from upstream, so we compose
# an internal role in here to handle those upstream_* parameters.
use Role::Tiny::With;
with 'App::IDA::Daemon::Link::Role::PullsFromUpstream';

# Sink comes at the end of the processing chain, so it's responsible
# for scheduling itself (directly via start/stop/_thunk) and
# everything upstream of it (indirectly, via repeated calls to
# $upstream->read_p())
sub stop { $_[0]->{running} = 0 }
sub start {
    my $self = shift;
    return if $self->{running}++;
    Mojo::IOLoop->next_tick(sub { $self->_thunk });
}
# The name _thunk should be OK (shouldn't conflict with other roles)
sub _thunk {
    my $self = shift;
    return unless $self->{running};
    
    $self->{upstream_object}
    ->read_p($self->{upstream_port}, $self->{preferred_bytes})
	->then(
	sub {
	    my ($data, $eof) = @_;
	    # TODO: make this promise-based
	    $self->write_to_internal($data);
	    if ($eof) {
		# TODO: call finish_message() instead
		$self->emit(finished => ${$self->{strref}});
	    } else {
		Mojo::IOLoop->next_tick(sub { $self->_thunk });
	    }
	},
	sub {
	    $self->emit(error => $_[0]);
	});
}


1;
