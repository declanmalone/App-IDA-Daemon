package App::IDA::Daemon::EncryptFilterP;
use Mojo::Base 'Mojo::EventEmitter';

# Promise-based chainable encryption filter

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

use Crypt::Mode::CBC;
use Crypt::PRNG::RC4 qw(random_bytes);

sub new {
    my ($class, $upstream, $key) = @_;

    die "Upstream undefined or can't read_p\n"
	unless defined $upstream and $upstream->can("read_p");

    # create a random initialisation vector
    my $iv = random_bytes(16);	# AES iv size
    my $self = bless {
	source => $source,
	read   => $read,
	close  => $close,
	iv     => $iv,
    }, $class;

    # Set up the encryptor in CBC mode
    my $enc = Crypt::Mode::CBC->new($settings{cipher});
    unless (defined $enc) {
	warn "Failed to create $settings{cipher} encryptor in CBC mode\n";
	return undef;
    }
    $enc->start_encrypt($key, $iv);

    $self;
}

sub _old {
    my $self = shift;
    # The IV will be passed unencrypted at the start of the data
    # stream. We can't emit anything right now, though (since there
    # can't be any subscribers), so we'll have to arrange to pass it
    # during a regular emit chain.
    $source->on($read => 
		sub {
		    my $indata = $_[1];
		    my $outdata = $enc->add($indata);
		    if (defined $iv) {
			$outdata = $iv . $outdata;
			$iv = undef;
		    }
		    $self->emit(read => $outdata);
		});
    unless (defined $close) {
	# On eof, we need to finish the encryption
	warn "EncryptFilter must subscribe to a close event\n";
	return undef;
    };
    $source->on($close =>
		sub {
		    $self->emit(read => $enc->finish);
		    $self->emit("close")
		});
}

sub read_p {
    my ($self,$port,$bytes) = @_;
    my $p = Mojo::Promise->new;

    $port //= 0; $bytes //= 0;
    
    return $p->reject("port should be 0 or undef")   if  $port != 0;
    return $p->reject("bytes should be >0 or undef") if !($bytes >= 0);

    
}

1;
__END__

=pod

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 

=cut
