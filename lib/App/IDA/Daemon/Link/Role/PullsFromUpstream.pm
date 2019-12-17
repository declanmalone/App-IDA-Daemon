package App::IDA::Daemon::Link::Role::PullsFromUpstream;

# Role for a class that calls:
#
# $self->{upstream_object}->read_p($self->{upstream_port}, $bytes)
#
# This Role just sets up and validates those attributes/parameters

use Mojo::Base -role;

# Role::Tiny doesn't support constructors or attributes, but
# Mojo::Base provides 'has' for attributes, and we can implement our
# own validation code easily enough.

# Attribute declaration
has [qw(upstream_object upstream_port)];

# Parameter validation (will be called from *::Link->new())

# There's no direct support for checking parameters to new, but we can
# implement it in a style similar to Class::Tiny by manually calling
# BUILDARGS in the constructor.

around BUILDARGS => sub {
    # Check parameters here, putting OK ones into self
    my ($orig, $self, $args, $errors) = @_;
    my ($object, $port);
    if (0) {
	warn "orig is a " . ref($orig) . "\n";
	warn "self is a " . ref($self) . "\n";
	warn "args is a " . ref($args) . "\n";
	warn "errors is a " . ref($errors) . "\n";
    }
    if (!exists($args->{upstream_object})) {
	push @$errors, "Required upstream_object arg not supplied";

    } elsif (!ref($object = $args->{upstream_object})) {
	push @$errors, "Supplied upstream_object arg not a reference";

    } elsif (!$object->can("read_p")) {
	push @$errors, "Supplied upstream_object arg can't read_p()";

    } elsif (!exists($args->{upstream_port})) {
	push @$errors, "Required upstream_port arg not supplied";

    } elsif (!$object->has_read_port($port = $args->{upstream_port})) {
	push @$errors, "Upstream object does not have port '$port'";

    } else {
	# All tests passed: install args in $self
	warn "Tests on upstream $object:$port passed\n";
	$self->{upstream_object} = $object;
	$self->{upstream_port}   = $port;
    }

    # Call the rest of the BUILDARGS chain
    $orig->($self, $args, $errors);
};

1;

__END__

=head1 NAME

Link Role +PullsFromUpstream - Internal Role consumed by +Filter, +Sink

=head1 DESCRIPTION

Gathers code relating to C<upstream_object> and C<upstream_port>
attributes shared by Filter and Sink roles into one place.

=over

=item * declares the C<upstream_object> and C<upstream_port> attributes

=item * error-checks them during new()

=back
