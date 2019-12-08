#!/usr/env/perl

use Mojo::Base -strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;

# Does high-level functionality testing on promise-based processing
# pipelines.
#
# The various promise-based Sources, Filters and Sinks don't have much
# in the way of callable methods, so there's not much unit testing we
# can do.
#
#

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

die "output '$output' ne 'My String'\n" unless $output eq "My String";
