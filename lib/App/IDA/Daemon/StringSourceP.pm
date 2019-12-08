package App::IDA::Daemon::StringSourceP;
use Mojo::Base 'Mojo::EventEmitter';

use warnings;

use Mojo::Promise;
use Mojo::IOLoop;

use v5.20;

# A promise-based string Source
#
# Apparently, we can return a pre-resolved promise. The following
# code works and prints "1":
#
# # this would be in the object code:
# use Mojo::Promise;
# my $a=0;
# my $p = Mojo::Promise->new;#
# $p->resolve("yes");
#
# # ... control would pass back to caller:
# $p->then(sub {++$a})->wait;
# say $a;

# This makes this code easy since we just wrap the data and eof in a
# resolved promise and send back straight away from within read_p.
# There's no messing about with the event loop or the need for
# start/stop methods.

sub new {
    my ($class, $string) = @_;
    bless [ $string ], $class;
}

sub read_p {
    my ($self,$port,$bytes) = @_;
    my $p = Mojo::Promise->new;

    $port //= 0; $bytes //= 0;
    
    return $p->reject("port should be 0 or undef")   if  $port != 0;
    return $p->reject("bytes should be >0 or undef") if !($bytes >= 0);

    # Compare requested bytes with what's available (0 bytes -> all bytes)
    my $avail = length($self->[0]);
    $bytes = $avail if $bytes == 0 or $bytes > $avail;
    
    # splice out the next chunk
    my $data = substr($self->[0], 0, $bytes,"");

    my $eof = ($self->[0] eq "") ? 1 : 0;

    # return resolved promise
    $p->resolve($data, $eof);
}

1;
__END__

=head1 SYNOPSIS

 use App::IDA::Daemon::StringSourceP;
 use Mojo::Promise;

 my $stream = App::IDA::Daemon::StringSourceP
  ->new("My String");

 # read string 3 bytes at a time
 my ($output,$data,$eof) = ("","",0);
 until ($eof) {
   $stream->read_p(0,3)->then(sub {
      ($data,$eof) = @_;
      $output .= $data;
   })->catch(sub {
      my $err = shift;
      die "Stream died with error '$err'\n"; 
   })->wait;
 }

 die unless $output eq "My String";

=head1 DESCRIPTION

This module implements streaming a string using a Promise-based
interface.

Its main purpose is as a Source for testing processing pipelines that
use the same Promise mechanism for reading and writing the data
stream.

The then/catch callbacks that are attached to the returned promise
will not actually run unless:

=over

=item * there is an active Mojo::IOLoop; or

=item * the promise is scheduled by calling its wait() method

=back

