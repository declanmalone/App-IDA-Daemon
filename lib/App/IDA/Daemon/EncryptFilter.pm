package App::IDA::Daemon::EncryptFilter;
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

1;
__END__

=pod

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 

=cut
