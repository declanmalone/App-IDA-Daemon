package App::IDA::Daemon::Link::Role::Filter;

# Filter trait
use Mojo::Base -role;
#use Role::Tiny;

# Some other role must supply the concrete method below:
requires qw(filter_process);

# we provide default implementation for input/output

# These will get pushed out to new roles later, but for now implement
# them here (just declarations for now; code is below):
# 
sub connect_upstream;   	# called during new()
sub read_upstream;   		# called in our loop

sub read_p;   			# called by downstream

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

# Role::Tiny doesn't support constructors or attributes, but
# Mojo::Base provides 'has' for attributes.

# Upstream side (these can be passed to new)
has 'upstream_object';
has 'upstream_port';

# There's no support for checking parameters to new, but we can
# implement it in the style of Class::Tiny by manually calling
# BUILDARGS from the constructor.
#
around BUILDARGS => sub {
    # would check parameters here, putting OK ones into self
    my ($orig, $self,$args, $errors) = @_;
    # warn "orig is a " . ref($orig) . "\n";
    # warn "self is a " . ref($self) . "\n";
    # warn "args is a " . ref($args) . "\n";
    # warn "errors is a " . ref($errors) . "\n";
    if (ref($args->{upstream_object}) and
	$args->{upstream_object}->can("read_p") and
	$args->{upstream_object}->has_read_port($args->{upstream_port})) {
	# OK... install in $self directly
	# (or wrap this in connect_upstream())
	$self->{upstream_object} = $args->{upstream_object};
	$self->{upstream_port}   = $args->{upstream_port};
    } else {
	push @$errors, "Problem with upstream_object/upstream_port";
    }
    # We have to manually call the rest of the BUILDARGS chain
    $orig->($self, $args, $errors);
};

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

    
