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

 # stream the string 3 bytes at a time
 my ($output, $data, $eof) = ("", "", 0);
 until ($eof) {
   $stream->read_p(0,3)->then(sub {
      ($data,$eof) = @_;
      $output .= $data;
   })->catch(sub {
      my $err = shift;
      die "Stream died with error '$err'\n"; 
   })->wait;
 }

 die "'$output' ne 'My String'\n" if $output ne "My String";

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

=head1 METHODS

The class implements a constructor and the C<read_p> method.

=head2 Constructor

 my $source = App::IDA::Daemon::StringSourceP
    ->new($string);

Creates a streaming Source.

=head2 read_p() method

 # Get a promise of some data from the stream
 my $promise = $source -> read_p( $port, $bytes );

 # Extract data from the promise
 $promise -> then(sub {
   my ($data,$eof) = @_;
   ...
 });
 
 # Catch errors (ie, invalid read_p arguments)
 $promise -> catch(sub {
   my $err = shift;
   ...
 });
 
 # then/catch callbacks don't get called until the promise is
 # scheduled to run. Use one of:
 $promise->wait;
 Mojo::IOLoop->start;
 Mojo::IOLoop->one_tick;

The arguments to C<read_p()> are:

=over

=item $port

This argument is accepted by all Source and Filter classes, but only
those classes that split a stream into multiple output streams allow
this to be non-zero. Since this class does not split the string, this
argument should be set to 0 or left undefined.

=item $bytes

C<read_p()> returns a promise to return I<up to> this number of bytes
of the current string. Setting this to 0 or leaving it undefined will
return the full string.

=back
