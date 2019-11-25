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

#use CryptX;
use Crypt::Mode::CBC;
use Crypt::PRNG::RC4 qw(random_bytes);

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
	iv     => undef,
    }, $class;

    # Set up the decryptor in CBC mode
    my $dec = Crypt::Mode::CBC->new($settings{cipher});
    unless (defined $dec) {
	warn "Failed to create $settings{cipher} decryptor in CBC mode\n";
	return undef;
    }
    # we start the decryptor within the callback
    
    $source->on($read =>
		sub {
		    my ($s, $indata) = @_;
		    if (!defined $self->{iv}) {
			if (length($indata) < 16) {
			    die "DecryptFilter needs a 16-byte iv to start\n";
			}
			my $iv = substr($indata, 0, 16, '');
			$dec->start_decrypt($key, $iv);
			$self->{iv} = $iv;
		    }
		    $self->emit(read => $dec->add($indata));
		});
    unless (defined $close) {
	# On eof, we need to finish the encryption
	warn "DecryptFilter must subscribe to a close event\n";
	return undef;
    };
    $source->on($close =>
		sub {
		    $self->emit(read => $dec->finish);
		    $self->emit("close")
		});
    $self;
}

1;
__END__

=pod

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 

=cut
