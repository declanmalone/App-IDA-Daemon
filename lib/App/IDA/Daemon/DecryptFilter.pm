package App::IDA::Daemon::DecryptFilter;
use Mojo::Base 'Mojo::EventEmitter';

# Class variables/method
our %settings = (
    cipher => 'Crypt::Cipher::AES',
    key_bits => 128,
);
sub config {
    %settings = (
	%settings,
	@_
    );
}

use CryptX;

sub new {
    my ($class, $source, $read, $close, $key) = @_;
    unless ($source->isa("Mojo::EventEmitter")) {
	warn "StringSink needs a Mojo::EventEmitter as input\n";
	return undef;
    }

    # For now, just implement NullFilter (input -> output unchanged)
    my $self = bless {
	source => $source,
	read   => $read,
	close  => $close,
    }, $class;

    $source->on($read => sub { $self->emit(read => $_[1]) });
    return $self unless defined($close);
    $source->on($close => sub { $self->emit("close") });
    $self;
}

1;
__END__

=pod

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 

=cut
