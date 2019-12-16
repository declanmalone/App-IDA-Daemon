package App::IDA::Daemon::Link::Role::PullsFromUpstream;

# Role for a class that calls:
#
# $self->{upstream_object}->read_p($self->{upstream_port}, $bytes)
#
# All we do here is set up and validate a couple of attributes

use Mojo::Base -role;

# Role::Tiny doesn't support constructors or attributes, but
# Mojo::Base provides 'has' for attributes.

has qw(upstream_object upstream_port);

# There's no support for checking parameters to new, but we can
# implement it in a style similar to Class::Tiny by manually calling
# BUILDARGS from the constructor.

around BUILDARGS => sub {
    # Check parameters here, putting OK ones into self
    my ($orig, $self,$args, $errors) = @_;
    # warn "orig is a " . ref($orig) . "\n";
    # warn "self is a " . ref($self) . "\n";
    # warn "args is a " . ref($args) . "\n";
    # warn "errors is a " . ref($errors) . "\n";
    if (ref($args->{upstream_object}) and
	$args->{upstream_object}->can("read_p") and
	$args->{upstream_object}->has_read_port($args->{upstream_port})) {
	# OK... install in $self directly
	$self->{upstream_object} = $args->{upstream_object};
	$self->{upstream_port}   = $args->{upstream_port};
    } else {
	push @$errors, "Problem with upstream_object/upstream_port";
    }
    # Call the rest of the BUILDARGS chain
    $orig->($self, $args, $errors);
};

1;
1;

__END__
