#!/usr/bin/env perl              # -*- perl -*-

use Mojo::Base -strict;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Mojo;

use Mojo::Promise;

use App::IDA::Daemon::StringSource;

use v5.20;
use Carp;


# Chainable is a rewrite/refactoring of the existing Source, Filter
# and Sink modules. It uses the same basic ideas of those, but:
#
# * Uses roles ("traits") to compose new classes
# * Adds explicit flow control to the chain
#
# 

# Test role composition 
