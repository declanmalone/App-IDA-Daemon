package App::IDA::Daemon::Link::Role::Source;

# Filter trait
use Mojo::Base -role;

# Some other role must supply the concrete method below:
requires qw(read_from_internal);

# we provide default implementation for output
sub read_p;   			# called by downstream

# During downstream object construction, this method will be called to
# make sure that downstream is connecting to port 0.
sub has_read_port { $_[1] == 0 }

has qw(eof);

# we provide read_p, and some other role supplies read_from_internal()
sub read_p {
    my ($self, $port, $bytes) = @_;

    # To make this work whether we're using a string or a Mojo Stream,
    # we should really pass the promise into read_from_internal().
    # That way, if there's an I/O error on the stream we can catch the
    # error and propagate it with $promise->reject()
    Mojo::Promise->new->resolve( $self->read_from_internal($bytes) );

    # Another way in which the two types of internal sources differ is
    # in their ability to detect EOF. A Mojo::IOLoop::Stream emits a
    # 'close' event, which won't be available to us until after we've
    # returned data. Thus we would need to make two calls to read_p at
    # eof: the first returning the data (possibly less than $bytes)
    # and the second returning ("", 1);
}

1;

    
