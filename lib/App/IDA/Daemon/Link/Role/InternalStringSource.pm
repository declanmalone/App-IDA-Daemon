package App::IDA::Daemon::Link::Role::InternalStringSource;

# Concrete trait providing an internal string source
use Mojo::Base -role;
use Mojo::Promise;

has qw(source_buffer);

# Using BUILDARGS means we have a new kind of unavoidable boilerplate.
#
# Still, we've got the validation code close to our attribute
# declarations, and the overall intent of the code is easy to see.
around BUILDARGS => sub {
    my ($orig, $self, $args, $errors) = @_;
    warn "In InternalStringSource's BUILDARGS\n";
    warn "orig is a " . ref($orig) . "\n";
    warn "self is a " . ref($self) . "\n";
    warn "args is a " . ref($args) . "\n";
    warn "errors is a " . ref($errors) . "\n";

    if (defined $args->{source_buffer}) {
	warn "source_buffer is defined!\n";
	$self->{source_buffer} = $args->{source_buffer};
    } else {
	push @$errors,
	"Role::InternalStringSource requires 'source_buffer' arg";
    }
    # chain other BUILDARGS
    $orig->($self, $args, $errors);
};

sub read_from_internal {
    my ($self, $bytes) = @_;
    my ($data, $eof, $avail);

    $avail = length $self->{source_buffer};
    $bytes = $avail if $avail < $bytes or $bytes == 0;
    $data  = substr $self->{source_buffer}, 0, $bytes, "";
    $eof   = length $self->{source_buffer} ? 0 : 1;

    ($data, $eof);
}




1;
